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
    @Published public var isIndexing: Bool = false

    private let defaults: UserDefaults?
    private let keys: SpotAliasStorageKeys
    private let spotlight: SpotAliasSpotlightAdapter

    public init(
        defaults: UserDefaults?,
        keys: SpotAliasStorageKeys,
        spotlight: SpotAliasSpotlightAdapter = .init()
    ) {
        self.defaults = defaults
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

    // MARK: - Spotlight Sync

    public func resyncAllSpotlight() {
        isIndexing = true
        statusMessage = "Spotlight インデックスを同期中..."
        let activeItems = items.filter(\.isEnabled)
        let adapter = spotlight
        Task {
            do {
                try await adapter.deleteAll()
                try await adapter.indexItems(activeItems)
                await MainActor.run {
                    self.isIndexing = false
                    self.statusMessage = "\(activeItems.count)件のアプリをSpotlightに登録しました"
                }
            } catch {
                await MainActor.run {
                    self.isIndexing = false
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
            try? await adapter.indexItems(activeItems)
        }
    }

    private func deleteFromSpotlight(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let adapter = spotlight
        Task {
            try? await adapter.deleteItems(ids)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let defaults else { return }
        guard let data = defaults.data(forKey: keys.items) else {
            // First launch: initialize with a few helpful presets if completely empty
            if items.isEmpty {
                let initial = SpotAliasPresets.builtin.prefix(3).map { $0.toItem() }
                self.items = Array(initial)
                save()
                syncSpotlight(items: items)
            }
            return
        }
        do {
            let decoded = try JSONDecoder().decode([AppAliasItem].self, from: data)
            self.items = decoded
        } catch {
            self.items = []
        }
    }

    private func save() {
        guard let defaults else { return }
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
        defaults?.removeObject(forKey: keys.items)
        let adapter = spotlight
        Task {
            try? await adapter.deleteAll()
        }
    }
}
#endif
