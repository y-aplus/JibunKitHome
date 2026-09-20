#if os(iOS)
import Foundation
import UIKit
import SwiftUI
import CoreSpotlight
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

    private static let store: SpotAliasStore = makeStore()

    private static func makeStore() -> SpotAliasStore {
        let keys = SpotAliasStorageKeys(items: context.storageKey("items"))
        let ns = namespace

        let adapter = SpotAliasSpotlightAdapter(
            indexItems: { items in
                let index = CSSearchableIndex.default()
                var searchableItems: [CSSearchableItem] = []
                for item in items {
                    let attributes = CSSearchableItemAttributeSet(contentType: .text)
                    attributes.title = item.title
                    attributes.keywords = item.allKeywords
                    attributes.contentDescription = "タップして \(item.title) を起動"
                    if !item.note.isEmpty {
                        attributes.comment = item.note
                    }
                    let sItem = ns.searchableItem(
                        localIdentifier: item.id.uuidString,
                        attributes: attributes
                    )
                    searchableItems.append(sItem)
                }
                guard !searchableItems.isEmpty else { return }
                try await index.indexSearchableItems(searchableItems)
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

        do {
            return SpotAliasStore(
                defaults: try MiniAppStorage.sharedDefaults(),
                keys: keys,
                spotlight: adapter
            )
        } catch {
            return SpotAliasStore(
                defaults: nil,
                keys: keys,
                spotlight: adapter
            )
        }
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
        UIApplication.shared.open(url)
        return true
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
        }
    ) { _ in
        SpotAliasRootView(store: store)
    }
}
#endif
