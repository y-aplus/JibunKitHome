import Foundation

/// Zaiko owns its backup schema and migration rules. Decode and validate the
/// entire candidate before the Store replaces any live inventory.
enum ZaikoBackup {
    private struct Header: Decodable {
        let version: Int?
    }

    static func decode(_ data: Data) throws -> BackupEnvelope {
        let object = try JSONSerialization.jsonObject(with: data)
        let decoder = makeDecoder()
        let envelope: BackupEnvelope
        if object is [String: Any] {
            if let version = try decoder.decode(Header.self, from: data).version {
                guard (1...3).contains(version) else {
                    throw ZaikoError.importFailed
                }
                if version == 3 {
                    // A malformed current backup must not fall back to the
                    // permissive legacy schema and silently discard fields.
                    envelope = try decoder.decode(BackupEnvelope.self, from: data)
                } else {
                    envelope = try migrate(decoder.decode(LegacyBackupEnvelope.self, from: data))
                }
            } else {
                let legacy = try decoder.decode(LegacyBackupEnvelope.self, from: data)
                guard !legacy.items.isEmpty else { throw ZaikoError.importFailed }
                envelope = try migrate(legacy)
            }
        } else {
            let items = try decoder.decode([LegacyInventoryItem].self, from: data)
            // An empty unversioned array cannot be identified as a backup.
            // Empty inventories remain supported in versioned envelopes.
            guard !items.isEmpty else { throw ZaikoError.importFailed }
            envelope = try migrate(LegacyBackupEnvelope(version: nil, items: items, app: nil))
        }
        try validate(envelope)
        return envelope
    }

    static func makeEncoder(prettyPrinted: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateCoding.string(from: date))
        }
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let date = DateCoding.date(from: rawValue) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid backup date")
            }
            return date
        }
        return decoder
    }

    private static func migrate(_ legacy: LegacyBackupEnvelope) throws -> BackupEnvelope {
        var usedIDs = Set<Int64>()
        for item in legacy.items {
            if let rawID = item.id {
                guard let id = Int64(exactly: rawID), usedIDs.insert(id).inserted else {
                    throw ZaikoError.importFailed
                }
            }
        }
        var nextID: Int64 = 1
        let items = try legacy.items.map { legacyItem -> InventoryItem in
            // Legacy fields are optional for compatibility, not permission to
            // accept arbitrary JSON objects or silently drop malformed rows.
            guard let stock = legacyItem.currentStock ?? legacyItem.lastStock,
                  stock.isFinite, stock >= 0 else { throw ZaikoError.importFailed }
            if let date = legacyItem.lastPurchased, DateCoding.date(from: date) == nil {
                throw ZaikoError.importFailed
            }
            guard var item = InventoryDomain.normalize(legacyItem) else { throw ZaikoError.importFailed }
            if legacyItem.id == nil {
                while usedIDs.contains(nextID) { nextID += 1 }
                item.id = nextID
                usedIDs.insert(nextID)
            }
            return item
        }
        var app = AppState.makeDefault()
        if let old = legacy.app {
            app.globalPause = old.globalPause ?? app.globalPause
            app.unitPreferences.merge(old.unitPreferences ?? [:]) { _, new in new }
            app.installMarker = old.installMarker ?? app.installMarker
            app.firstSavedAt = old.firstSavedAt
            app.alertThresholdDays = old.alertThresholdDays ?? app.alertThresholdDays
        }
        return BackupEnvelope(version: 3, items: items, app: app)
    }

    private static func validate(_ envelope: BackupEnvelope) throws {
        guard Set(envelope.items.map(\.id)).count == envelope.items.count,
              envelope.app.alertThresholdDays.isFinite,
              (1...30).contains(envelope.app.alertThresholdDays),
              !envelope.app.globalPause.active || envelope.app.globalPause.startedAt != nil else {
            throw ZaikoError.importFailed
        }
        for item in envelope.items {
            guard !item.name.trimmed.isEmpty, item.currentStock.isFinite,
                  item.currentStock >= 0, item.count > 0 else { throw ZaikoError.importFailed }
            if let rate = item.consumptionRatePerDay {
                guard rate.isFinite, rate > 0 else { throw ZaikoError.importFailed }
            } else if !item.needsConsumptionSetup {
                throw ZaikoError.importFailed
            }
        }
    }
}
