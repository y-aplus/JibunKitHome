#if os(iOS)
import Foundation
import UIKit
import SwiftUI
import CoreSpotlight
import OSLog
import JibunKitCore
import SpotAliasFeature

public extension MiniAppID {
    static let spotalias = MiniAppID("spotalias")
}

@MainActor
public enum SpotAliasMiniApp {
    public static let id = MiniAppID("spotalias")
    public static let lifetime = MiniAppFeatureLifetime(id: id)
    public static let schemaVersion = 1

    private static let context = MiniAppContext(id: id)
    private static let namespace = MiniAppSpotlightNamespace(context: context)
    nonisolated private static let logger = Logger(subsystem: "com.jibunkit.app", category: "SpotAlias")

    public static let store: SpotAliasStore = makeStore()

    private static func makeStore() -> SpotAliasStore {
        let keys = SpotAliasStorageKeys(items: context.storageKey("items"))
        let ns = namespace

        let adapter = SpotAliasSpotlightAdapter(
            indexItems: { items in
                guard CSSearchableIndex.isIndexingAvailable() else {
                    let err = NSError(
                        domain: "SpotAlias",
                        code: -1005,
                        userInfo: [NSLocalizedDescriptionKey: "この端末環境では Core Spotlight インデックスがサポートされていません"]
                    )
                    logger.warning("\(err.localizedDescription)")
                    throw err
                }
                let index = CSSearchableIndex.default()
                var searchableItems: [CSSearchableItem] = []
                for item in items {
                    let attributes = CSSearchableItemAttributeSet(contentType: .text)
                    attributes.title = item.spotlightTitle
                    attributes.displayName = item.spotlightTitle
                    attributes.alternateNames = item.aliases
                    attributes.keywords = item.allKeywords
                    attributes.textContent = "\(item.spotlightTitle) \(item.aliases.joined(separator: " ")) JibunKit ジブンキット \(item.note)"
                    attributes.contentDescription = "JibunKit: \(item.title) を起動"
                    attributes.containerTitle = "JibunKit"
                    attributes.containerDisplayName = "JibunKit"
                    attributes.rankingHint = 1.0
                    if !item.note.isEmpty {
                        attributes.comment = item.note
                    }
                    let sItem = ns.searchableItem(
                        localIdentifier: item.id.uuidString,
                        attributes: attributes
                    )
                    sItem.expirationDate = Date.distantFuture
                    searchableItems.append(sItem)
                }
                guard !searchableItems.isEmpty else { return }
                do {
                    try await index.indexSearchableItems(searchableItems)
                    logger.notice("Spotlight successfully indexed \(searchableItems.count) items.")
                } catch {
                    logger.error("Spotlight indexing failed: \(error.localizedDescription)")
                    throw error
                }
            },
            deleteItems: { ids in
                let index = CSSearchableIndex.default()
                for id in ids {
                    try? await ns.delete(localIdentifier: id.uuidString, from: index)
                }
            },
            deleteAll: {
                let index = CSSearchableIndex.default()
                try? await ns.deleteAll(from: index)
            }
        )

        let resolvedDefaults = (try? MiniAppStorage.sharedDefaults()) ?? .standard
        return SpotAliasStore(
            defaults: resolvedDefaults,
            keys: keys,
            spotlight: adapter
        )
    }

    private static let backup: MiniAppBackupProvider = {
        let owner = id
        let schema = schemaVersion
        return MiniAppBackupProvider(id: owner, export: {
            let json = await MainActor.run { SpotAliasMiniApp.store.exportBackupJSON() }
            return MiniAppBackupEntry(id: owner, schemaVersion: schema, payload: Data(json.utf8))
        }, prepare: { entry in
            guard entry.schemaVersion == schema else {
                throw MiniAppBackupError.unsupportedSchema(entry.schemaVersion)
            }
            let payload = entry.payload
            // Validate JSON decoding before confirm
            _ = try JSONDecoder().decode([AppAliasItem].self, from: payload)
            return MiniAppPreparedRestore {
                try await MainActor.run {
                    try SpotAliasMiniApp.store.importBackup(data: payload)
                }
            }
        })
    }()

    private static let removal = MiniAppRemovalProvider(
        id: id,
        dataDescription: "SpotAlias辞書データ（アプリ名・エイリアス・URLスキーム）",
        removeData: {
            await MainActor.run {
                SpotAliasMiniApp.store.removeOwnedData()
            }
        }
    )

    /// Launch external app immediately when routed from Spotlight
    private static func handleDestination(_ destination: String) -> Bool {
        guard let uuid = UUID(uuidString: destination),
              let item = store.items.first(where: { $0.id == uuid }),
              let url = URL(string: item.urlScheme) else { return false }
        
        store.setPendingLaunchItem(item)

        // Wait for iOS scene to become fully active before requesting openURL
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s delay for scene stabilization
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    logger.notice("Successfully opened URL from Spotlight: \(url.absoluteString)")
                    store.clearPendingLaunchItem()
                } else {
                    logger.error("Failed to open URL from Spotlight: \(url.absoluteString)")
                }
            }
        }
        return true
    }

    /// Eagerly evaluates the store and ensures Spotlight indexing on host launch
    public static func onLaunch() throws {
        _ = store
        Task {
            do {
                try await store.syncAllSpotlightImmediately()
            } catch {
                logger.error("Startup Spotlight sync failed: \(error.localizedDescription)")
            }
        }
    }

    public static let definition = MiniAppDefinition(
        id: id,
        title: "SpotAlias",
        systemImage: "magnifyingglass",
        backup: backup,
        lifetime: lifetime,
        removal: removal,
        appendDestination: { destination, _ in
            handleDestination(destination)
        },
        onHostLaunch: {
            try onLaunch()
        },
        onHostPhaseChange: { phase in
            if phase == .active {
                Task {
                    try? await store.syncAllSpotlightImmediately()
                }
            }
        }
    ) { _ in
        SpotAliasRootView(store: store)
    }
}
#endif
