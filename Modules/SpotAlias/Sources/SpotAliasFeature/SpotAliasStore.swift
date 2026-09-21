#if os(iOS)
import Foundation
import Combine
import SwiftUI
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

public struct SpotAliasStorageKeys: Sendable {
    public let items: String

    public init(items: String) {
        self.items = items
    }
}

public struct SpotAliasSpotlightAdapter: Sendable {
    public var indexItems: @Sendable ([AppAliasItem]) async throws -> Void
    public var deleteItems: @Sendable ([UUID]) async throws -> Void
    public var deleteAll: @Sendable () async throws -> Void

    public init(
        indexItems: @escaping @Sendable ([AppAliasItem]) async throws -> Void = { _ in },
        deleteItems: @escaping @Sendable ([UUID]) async throws -> Void = { _ in },
        deleteAll: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.indexItems = indexItems
        self.deleteItems = deleteItems
        self.deleteAll = deleteAll
    }
}

@MainActor
public final class SpotAliasStore: ObservableObject {
    @Published public private(set) var items: [AppAliasItem] = []
    @Published public var searchQuery: String = ""
    @Published public var statusMessage: String?
    @Published public var lastSyncResult: String?
    @Published public var lastSyncDate: Date?
    @Published public var isIndexing: Bool = false

    private let defaults: UserDefaults
    private let keys: SpotAliasStorageKeys
    private let spotlight: SpotAliasSpotlightAdapter

    public init(
        defaults: UserDefaults? = nil,
        keys: SpotAliasStorageKeys,
        spotlight: SpotAliasSpotlightAdapter = .init()
    ) {
        self.defaults = defaults ?? .standard
        self.keys = keys
        self.spotlight = spotlight
        load()
    }

    public var filteredItems: [AppAliasItem] {
        if searchQuery.isEmpty {
            return items.sorted { $0.title < $1.title }
        }
        return items
            .filter { $0.matches(query: searchQuery) }
            .sorted { $0.title < $1.title }
    }

    // MARK: - CRUD

    public func add(_ item: AppAliasItem) {
        var newItem = item
        newItem.updatedAt = Date()
        items.append(newItem)
        save()
        syncSpotlight(items: [newItem])
    }

    public func update(_ item: AppAliasItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()
        items[index] = updated
        save()
        syncSpotlight(items: [updated])
    }

    public func remove(at offsets: IndexSet) {
        let targets = offsets.map { filteredItems[$0] }
        let idsToDelete = targets.map(\.id)
        items.removeAll(where: { idsToDelete.contains($0.id) })
        save()
        deleteFromSpotlight(ids: idsToDelete)
    }

    public func delete(_ item: AppAliasItem) {
        items.removeAll(where: { $0.id == item.id })
        save()
        deleteFromSpotlight(ids: [item.id])
    }

    public func toggleEnabled(for item: AppAliasItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isEnabled.toggle()
        items[index].updatedAt = Date()
        let updated = items[index]
        save()
        if updated.isEnabled {
            syncSpotlight(items: [updated])
        } else {
            deleteFromSpotlight(ids: [updated.id])
        }
    }

    public func addPreset(_ preset: AppAliasPreset) {
        // Prevent duplicate title
        if let existing = items.first(where: { $0.title.lowercased() == preset.title.lowercased() }) {
            // Append missing aliases
            var updated = existing
            let currentSet = Set(updated.aliases)
            let newAliases = preset.aliases.filter { !currentSet.contains($0) }
            if !newAliases.isEmpty {
                updated.aliases.append(contentsOf: newAliases)
                update(updated)
            }
            return
        }
        add(preset.toItem())
    }

    // MARK: - Spotlight Sync & Diagnostics

    public func syncAllSpotlightImmediately() async throws {
        let activeItems = items.filter(\.isEnabled)
        guard !activeItems.isEmpty else { return }
        try await spotlight.indexItems(activeItems)
        lastSyncDate = Date()
        lastSyncResult = "✓ 登録成功: \(activeItems.count)件"
    }

    /// Register a dedicated test item along with all active items to verify Core Spotlight integration
    public func testSpotlightSync() {
        isIndexing = true
        statusMessage = "疎通テスト項目と全アプリをSpotlightに登録中..."
        let testItem = AppAliasItem.makeDiagnosticTestItem()

        // Add or update test item in store so user can see it in the list
        if let idx = items.firstIndex(where: { $0.title == testItem.title }) {
            items[idx] = testItem
        } else {
            items.insert(testItem, at: 0)
        }
        save()

        let adapter = spotlight
        let activeItems = items.filter(\.isEnabled)
        Task {
            do {
                try await adapter.indexItems(activeItems)
                await MainActor.run {
                    self.isIndexing = false
                    self.lastSyncDate = Date()
                    self.lastSyncResult = "✓ 登録成功: \(activeItems.count)件 (テスト含む)"
                    self.statusMessage = "\(activeItems.count)件を登録完了。Spotlightで「マック」または「jibunkit」と検索してください。"
                }
            } catch {
                await MainActor.run {
                    self.isIndexing = false
                    self.lastSyncDate = Date()
                    self.lastSyncResult = "✗ 登録失敗: \(error.localizedDescription)"
                    self.statusMessage = "エラー: \(error.localizedDescription)"
                }
            }
        }
    }

    public func resyncAllSpotlight() {
        isIndexing = true
        statusMessage = "Spotlight インデックスを全再同期中..."
        let adapter = spotlight
        let activeItems = items.filter(\.isEnabled)
        Task {
            do {
                try await adapter.deleteAll()
                try await adapter.indexItems(activeItems)
                await MainActor.run {
                    self.isIndexing = false
                    self.lastSyncDate = Date()
                    self.lastSyncResult = "✓ 全同期成功: \(activeItems.count)件"
                    self.statusMessage = "\(activeItems.count)件のアプリをSpotlightに再登録しました"
                }
            } catch {
                await MainActor.run {
                    self.isIndexing = false
                    self.lastSyncDate = Date()
                    self.lastSyncResult = "✗ 全同期失敗: \(error.localizedDescription)"
                    self.statusMessage = "同期失敗: \(error.localizedDescription)"
                }
            }
        }
    }

    private func syncSpotlight(items: [AppAliasItem]) {
        let activeItems = items.filter(\.isEnabled)
        guard !activeItems.isEmpty else { return }
        let adapter = spotlight
        Task {
            do {
                try await adapter.indexItems(activeItems)
                await MainActor.run {
                    self.lastSyncDate = Date()
                    self.lastSyncResult = "✓ 登録成功: \(activeItems.count)件"
                }
            } catch {
                await MainActor.run {
                    self.lastSyncDate = Date()
                    self.lastSyncResult = "✗ 登録失敗: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteFromSpotlight(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let adapter = spotlight
        Task {
            try? await adapter.deleteItems(ids)
        }
    }

    // MARK: - Persistence & Migration

    private func load() {
        guard let data = defaults.data(forKey: keys.items) else {
            // First launch: initialize with all builtin presets
            if items.isEmpty {
                self.items = SpotAliasPresets.builtin.map { $0.toItem() }
                save()
                syncSpotlight(items: items)
            }
            return
        }
        do {
            let decoded = try JSONDecoder().decode([AppAliasItem].self, from: data)
            if decoded.isEmpty {
                self.items = SpotAliasPresets.builtin.map { $0.toItem() }
                save()
                syncSpotlight(items: items)
            } else {
                // Apply migrations to existing stored data:
                // 1. Remove obsolete items (e.g. Lopia)
                // 2. Fix known outdated URL schemes and sync optimized alias order (e.g. McDonald's)
                var migrated = decoded.filter { item in
                    item.title != "ロピア" && !item.urlScheme.hasPrefix("lopia://")
                }
                for i in 0..<migrated.count {
                    if migrated[i].title == "マクドナルド" {
                        if let mcd = SpotAliasPresets.builtin.first(where: { $0.title == "マクドナルド" }) {
                            migrated[i].aliases = mcd.aliases
                            migrated[i].urlScheme = mcd.urlScheme
                            migrated[i].updatedAt = Date()
                        }
                    } else if migrated[i].urlScheme == "mcdonalds://" {
                        migrated[i].urlScheme = "mcdonaldsjp://"
                        migrated[i].updatedAt = Date()
                    }
                }
                self.items = migrated
                save()
            }
        } catch {
            self.items = SpotAliasPresets.builtin.map { $0.toItem() }
            save()
            syncSpotlight(items: items)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            defaults.set(data, forKey: keys.items)
        } catch {
            // Keep in-memory
        }
    }

    // MARK: - Host Contracts (Backup & Removal)

    public func exportBackupJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    public func importBackup(data: Data) throws {
        let decoded = try JSONDecoder().decode([AppAliasItem].self, from: data)
        self.items = decoded
        save()
        resyncAllSpotlight()
    }

    public func removeOwnedData() {
        items = []
        defaults.removeObject(forKey: keys.items)
        let adapter = spotlight
        Task {
            try? await adapter.deleteAll()
        }
    }
}
#endif
