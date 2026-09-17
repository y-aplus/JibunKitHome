import Foundation
import XCTest
@testable import ZaikoFeature

/// Verification against a real export supplied locally by the operator.
///
/// The export is personal data and is never committed. Set `ZAIKO_REAL_BACKUP`
/// to a local file to run these tests. The strict comparison with an
/// independent calculation is recorded in the derived host's verification notes
/// (`docs-local/verification.md`) instead of hard-coding delivered numbers here.
final class ZaikoRealBackupTests: XCTestCase {
    /// The delivered export is personal data and is not committed. Point
    /// `ZAIKO_REAL_BACKUP` at a local export to run this verification; without it
    /// these tests are skipped and the rest of the suite still runs.
    private func fixtureData() throws -> Data {
        guard let path = ProcessInfo.processInfo.environment["ZAIKO_REAL_BACKUP"] else {
            throw XCTSkip("set ZAIKO_REAL_BACKUP to a delivered export to verify real data")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Matches the date the independent calculation used.
    private func referenceNow() throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T18:00:00Z"))
    }

    func testDeliveredExportIsAcceptedByTheFeatureFormat() throws {
        let data = try fixtureData()
        XCTAssertNoThrow(try ZaikoBackupDocument.validate(data))

        let envelope = try ZaikoBackup.decode(data)
        XCTAssertFalse(envelope.items.isEmpty, "the export should contain items")
        XCTAssertGreaterThan(envelope.app.alertThresholdDays, 0)
        XCTAssertEqual(Set(envelope.items.map(\.id)).count, envelope.items.count, "item IDs must be unique")
        for item in envelope.items {
            XCTAssertFalse(item.name.trimmed.isEmpty)
        }
    }

    /// Prints computed values so they can be compared with an independent
    /// calculation (docs-local/calc_expected.py) instead of committing the
    /// delivered numbers.
    func testRealDataProducesFiniteRemainingValues() throws {
        let envelope = try ZaikoBackup.decode(try fixtureData())
        let now = try referenceNow()
        let pause = envelope.app.globalPause

        for item in envelope.items {
            guard !item.needsConsumptionSetup, (item.consumptionRatePerDay ?? 0) > 0 else {
                XCTAssertNil(InventoryDomain.remainingDays(for: item, pauseState: pause, now: now), item.name)
                continue
            }
            let stock = try XCTUnwrap(
                InventoryDomain.remainingStock(for: item, pauseState: pause, now: now), item.name)
            let days = try XCTUnwrap(
                InventoryDomain.remainingDays(for: item, pauseState: pause, now: now), item.name)
            XCTAssertTrue(stock.isFinite, item.name)
            XCTAssertTrue(days.isFinite, item.name)
            print(String(format: "%-24@ stock=%12.6f days=%12.6f", item.name as NSString, stock, days))
        }
    }

    func testAlertSetIsConsistentWithTheReportedOrder() throws {
        let envelope = try ZaikoBackup.decode(try fixtureData())
        let now = try referenceNow()
        let pause = envelope.app.globalPause
        let threshold = envelope.app.alertThresholdDays

        let alerts = envelope.items.filter {
            InventoryDomain.isAlert(item: $0, pauseState: pause, thresholdDays: threshold, now: now)
        }
        let sorted = InventoryDomain.sortedItems(
            envelope.items, pauseState: pause, thresholdDays: threshold, now: now)
        XCTAssertEqual(sorted.count, envelope.items.count)
        // Every alerting item is reported before every non-alerting item.
        let firstNonAlert = sorted.firstIndex { !alerts.contains($0) } ?? sorted.count
        XCTAssertTrue(
            sorted[..<firstNonAlert].allSatisfy { alerts.contains($0) },
            "an alerting item appears after a non-alerting one")
        // Items without a usable rate sort after items with one.
        let firstWithoutRate = sorted.firstIndex { InventoryDomain.remainingDays(for: $0, pauseState: pause, now: now) == nil } ?? sorted.count
        XCTAssertTrue(sorted[..<firstWithoutRate].allSatisfy {
            InventoryDomain.remainingDays(for: $0, pauseState: pause, now: now) != nil
        })
    }

    func testUnitPreferencesFromTheExportWinOverBuiltInDefaults() throws {
        let envelope = try ZaikoBackup.decode(try fixtureData())
        for item in envelope.items {
            let expected = envelope.app.unitPreferences[item.unit.trimmed]
                ?? InventoryDomain.inferDisplayMode(for: item.unit)
            XCTAssertEqual(InventoryDomain.displayMode(for: item, appState: envelope.app), expected, item.unit)
        }
    }
}
