import Foundation
import XCTest
@testable import ZaikoFeature

final class ZaikoBackupTests: XCTestCase {
    func testPWAEnvelopeWithoutNativeNotificationFieldsIsSupported() throws {
        // Synthetic fixture matching zaiko/js/domain.js serializeData v3.
        let json = """
        {"version":3,"items":[{"id":1,"name":"水","category":"飲料","unit":"本",
        "lastPurchased":"2026-09-05T00:00:00.000Z","currentStock":2,
        "consumptionRatePerDay":1,"count":1,"needsConsumptionSetup":false}],
        "app":{"globalPause":{"active":false,"startedAt":null},
        "unitPreferences":{},"installMarker":"test","firstSavedAt":null,"alertThresholdDays":7}}
        """
        let result = try ZaikoBackup.decode(Data(json.utf8))
        XCTAssertEqual(result.items.first?.name, "水")
        XCTAssertTrue(result.app.notificationsEnabled)
        XCTAssertTrue(result.app.notificationRecords.isEmpty)
    }

    func testCurrentBackupRoundTripsAndAllowsExplicitlyEmptyInventory() throws {
        let item = try InventoryDomain.makeItem(from: ItemDraft(
            name: "水", category: "飲料", unit: "本", stock: "10", speed: "1", displayMode: .perDayAmount
        ))
        for items in [[item], []] {
            let backup = BackupEnvelope(version: 3, items: items, app: .makeDefault())
            let encoded = try ZaikoBackup.makeEncoder(prettyPrinted: true).encode(backup)
            let result = try ZaikoBackup.decode(encoded)
            XCTAssertEqual(result.items.map(\.id), items.map(\.id))
            XCTAssertEqual(result.items.first?.currentStock, items.first?.currentStock)
            XCTAssertEqual(result.app.installMarker, backup.app.installMarker)
        }
    }

    func testUnrelatedAndPartiallyInvalidJSONAreRejectedAsAWhole() {
        for json in [
            "[{}]", "[]", "{}", "{\"items\":[{}]}", "{\"items\":[]}",
            "{\"version\":true,\"items\":[]}",
            "[{\"name\":\"水\",\"currentStock\":2},{}]",
            "[{\"name\":\"水\"}]",
            "[{\"name\":\"水\",\"currentStock\":-1}]",
            "[{\"name\":\"水\",\"currentStock\":2,\"lastPurchased\":\"bad date\"}]",
        ] {
            XCTAssertThrowsError(try ZaikoBackup.decode(Data(json.utf8)), json)
        }
    }

    func testMalformedCurrentAndFutureVersionsNeverFallBackToLegacy() {
        for version in [3, 4, -1] {
            let json = "{\"version\":\(version),\"items\":[{\"name\":\"水\",\"currentStock\":2}]}"
            XCTAssertThrowsError(try ZaikoBackup.decode(Data(json.utf8)))
        }
    }

    func testLegacyMigrationRetainsEveryRowAndAssignsUniqueMissingIDs() throws {
        let json = "[{\"name\":\"水\",\"currentStock\":2},{\"name\":\"米\",\"lastStock\":3},{\"id\":1,\"name\":\"塩\",\"currentStock\":4}]"
        let result = try ZaikoBackup.decode(Data(json.utf8))
        XCTAssertEqual(result.items.map(\.name), ["水", "米", "塩"])
        XCTAssertEqual(result.items.map(\.currentStock), [2, 3, 4])
        XCTAssertEqual(Set(result.items.map(\.id)).count, 3)
        XCTAssertEqual(result.items.last?.id, 1)
    }

    func testInvalidAndDuplicateLegacyIDsAreRejectedWithoutIntegerTrap() {
        for id in ["1e30", "1.5"] {
            let json = "[{\"id\":\(id),\"name\":\"水\",\"currentStock\":2}]"
            XCTAssertThrowsError(try ZaikoBackup.decode(Data(json.utf8)))
        }
        let json = "[{\"id\":1,\"name\":\"水\",\"currentStock\":2},{\"id\":1,\"name\":\"米\",\"currentStock\":3}]"
        XCTAssertThrowsError(try ZaikoBackup.decode(Data(json.utf8)))
    }

    func testCurrentBackupRejectsDuplicateIDsAndInvalidThreshold() throws {
        let item = try InventoryDomain.makeItem(from: ItemDraft(
            name: "水", category: "", unit: "", stock: "2", speed: "1", displayMode: .perDayAmount
        ))
        let duplicate = BackupEnvelope(version: 3, items: [item, item], app: .makeDefault())
        let duplicateData = try ZaikoBackup.makeEncoder(prettyPrinted: false).encode(duplicate)
        XCTAssertThrowsError(try ZaikoBackup.decode(duplicateData))
        var invalid = BackupEnvelope(version: 3, items: [item], app: .makeDefault())
        invalid.app.alertThresholdDays = 1e30
        let invalidData = try ZaikoBackup.makeEncoder(prettyPrinted: false).encode(invalid)
        XCTAssertThrowsError(try ZaikoBackup.decode(invalidData))
    }
}
