import Foundation
import XCTest
@testable import ZaikoFeature

final class ZaikoFeatureTests: XCTestCase {
    // NOTE: the namespace/uniqueness assertions for this Feature now live on the
    // host side (they assert MiniAppContext-derived storage keys and validator
    // output), so they moved out of this host-independent package.

    func testRemainingDaysDecreasesWithElapsedTime() {
        let item = InventoryItem(
            id: 1,
            name: "水",
            category: "飲料",
            unit: "本",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 10,
            consumptionRatePerDay: 1,
            count: 1,
            needsConsumptionSetup: false
        )
        let pause = GlobalPauseState(active: false, startedAt: nil)
        let now = Date(timeIntervalSince1970: 3 * 86_400)

        let remaining = InventoryDomain.remainingDays(for: item, pauseState: pause, now: now)

        XCTAssertEqual(remaining ?? -1, 7, accuracy: 0.001)
    }

    func testAlertItemsSortBeforeOthers() {
        let pause = GlobalPauseState(active: false, startedAt: nil)
        let now = Date(timeIntervalSince1970: 9 * 86_400)
        let alertItem = InventoryItem(
            id: 1,
            name: "牛乳",
            category: "食品",
            unit: "本",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 10,
            consumptionRatePerDay: 1,
            count: 1,
            needsConsumptionSetup: false
        )
        let normalItem = InventoryItem(
            id: 2,
            name: "米",
            category: "食品",
            unit: "kg",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 100,
            consumptionRatePerDay: 1,
            count: 1,
            needsConsumptionSetup: false
        )

        let sorted = InventoryDomain.sortedItems(
            [normalItem, alertItem],
            pauseState: pause,
            thresholdDays: 7,
            now: now
        )

        XCTAssertEqual(sorted.map(\.id), [1, 2])
    }

    func testItemDraftValidationRejectsEmptyName() {
        var draft = ItemDraft.empty()
        draft.stock = "1"
        draft.speed = "1"

        XCTAssertThrowsError(try draft.validate())
    }

    func testBlankUnitPreservesSelectedFormatThroughSave() throws {
        let draft = ItemDraft(
            name: "洗剤",
            category: "",
            unit: "",
            stock: "10",
            speed: "2",
            displayMode: .perDayAmount
        )
        let now = Date(timeIntervalSince1970: 4 * 86_400)
        let pause = GlobalPauseState(active: false, startedAt: nil)
        let created = try InventoryDomain.makeItem(from: draft, now: now)
        XCTAssertEqual(created.consumptionRatePerDay ?? -1, 2, accuracy: 0.001)

        let base = InventoryItem(
            id: 1,
            name: "洗剤",
            category: "未分類",
            unit: "",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 10,
            consumptionRatePerDay: 2,
            count: 1,
            needsConsumptionSetup: false
        )
        let updated = try InventoryDomain.updateItem(base, with: draft, now: now)
        XCTAssertEqual(updated.consumptionRatePerDay ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(
            InventoryDomain.remainingDays(for: updated, pauseState: pause, now: now) ?? -1,
            5,
            accuracy: 0.001
        )
    }

    func testNameOnlyEditPreservesRemainingStock() throws {
        let pause = GlobalPauseState(active: false, startedAt: nil)
        let purchased = Date(timeIntervalSince1970: 0)
        let editAt = Date(timeIntervalSince1970: 3 * 86_400)
        let item = InventoryItem(
            id: 1,
            name: "水",
            category: "飲料",
            unit: "本",
            lastPurchased: purchased,
            currentStock: 10,
            consumptionRatePerDay: 1,
            count: 1,
            needsConsumptionSetup: false
        )
        let before = InventoryDomain.remainingStock(for: item, pauseState: pause, now: editAt)

        var draft = ItemDraft(item: item, mode: .perUnitTime, pauseState: pause, now: editAt)
        XCTAssertEqual(draft.stock, "7")
        draft.name = "水2"

        let updated = try InventoryDomain.updateItem(item, with: draft, now: editAt)
        XCTAssertEqual(updated.lastPurchased, editAt)
        XCTAssertEqual(
            InventoryDomain.remainingStock(for: updated, pauseState: pause, now: editAt) ?? -1,
            before ?? -1,
            accuracy: 0.001
        )
    }

    func testFormValuesHaveNoGroupingSeparators() {
        let pause = GlobalPauseState(active: false, startedAt: nil)
        let item = InventoryItem(
            id: 1,
            name: "米",
            category: "食品",
            unit: "kg",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 1000,
            consumptionRatePerDay: 2,
            count: 1,
            needsConsumptionSetup: false
        )
        let draft = ItemDraft(
            item: item,
            mode: .perDayAmount,
            pauseState: pause,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(draft.stock, "1000")
        XCTAssertEqual(draft.speed, "2")
        XCTAssertNoThrow(try draft.validate())
    }

    func testResumePreservesStockForPausePeriodChanges() throws {
        let startedAt = Date(timeIntervalSince1970: 3 * 86_400)
        let updatedAt = Date(timeIntervalSince1970: 4 * 86_400)
        let resumedAt = Date(timeIntervalSince1970: 8 * 86_400)
        let pause = GlobalPauseState(active: true, startedAt: startedAt)
        let base = InventoryItem(
            id: 1,
            name: "洗剤",
            category: "日用品",
            unit: "本",
            lastPurchased: Date(timeIntervalSince1970: 0),
            currentStock: 10,
            consumptionRatePerDay: 1,
            count: 1,
            needsConsumptionSetup: false
        )
        let form = ItemDraft(
            name: "洗剤",
            category: "日用品",
            unit: "本",
            stock: "10",
            speed: "1",
            displayMode: .perUnitTime
        )
        let items = [
            base,
            try InventoryDomain.makeItem(from: form, now: updatedAt),
            try InventoryDomain.updateItem(base, with: form, now: updatedAt),
            InventoryDomain.applyRestock(
                to: base,
                remaining: 8,
                added: 2,
                pauseState: pause,
                now: updatedAt
            ),
        ]
        let shifted = InventoryDomain.shiftItemsForPause(items, pauseStartedAt: startedAt, resumedAt: resumedAt)
        let inactive = GlobalPauseState(active: false, startedAt: nil)
        for (index, item) in items.enumerated() {
            let expected = InventoryDomain.remainingStock(for: item, pauseState: pause, now: resumedAt)
            XCTAssertEqual(
                InventoryDomain.remainingStock(for: shifted[index], pauseState: inactive, now: resumedAt) ?? -999,
                expected ?? -999,
                accuracy: 0.001
            )
            XCTAssertEqual(
                InventoryDomain.remainingStock(
                    for: shifted[index],
                    pauseState: inactive,
                    now: resumedAt.addingTimeInterval(86_400)
                ) ?? -999,
                (expected ?? 0) - item.consumptionRatePerDay!,
                accuracy: 0.001
            )
        }
    }

    func testLegacyNormalizationKeepsNameAndStock() {
        let legacy = LegacyInventoryItem(
            id: nil,
            name: "醤油",
            category: nil,
            unit: nil,
            lastPurchased: nil,
            currentStock: 2,
            lastStock: nil,
            consumptionRatePerDay: 0.5,
            consumptionPace: nil,
            cycle: nil,
            count: nil,
            needsConsumptionSetup: nil
        )

        let item = InventoryDomain.normalize(legacy)

        XCTAssertEqual(item?.name, "醤油")
        XCTAssertEqual(item?.currentStock ?? -1, 2, accuracy: 0.001)
    }

    func testDeliveredCycleStaysHandledAndCancelledCycleCanBeScheduledAgain() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let imminent = now.addingTimeInterval(5)
        let distant = now.addingTimeInterval(3_600)

        // Delivery does not invalidate a cycle's record.
        XCTAssertTrue(InventoryDomain.shouldSkipReschedule(
            hasRecord: true, fireDate: imminent, now: now
        ))
        // Explicit cancellation removes the record; re-enable can reserve again.
        XCTAssertFalse(InventoryDomain.shouldSkipReschedule(
            hasRecord: false, fireDate: imminent, now: now
        ))
        XCTAssertFalse(InventoryDomain.shouldSkipReschedule(
            hasRecord: true, fireDate: distant, now: now
        ))
    }

    func testDisableOrPauseOnlyInvalidatesPendingCycles() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let prefix = "jibunkit.zaiko.notification."
        let records = ["1": "delivered-cycle", "2": "pending-cycle"]
        let afterCancellation = InventoryDomain.recordsAfterCancellingPending(
            records,
            pendingIDs: [prefix + "2", "jibunkit.reminder.notification"],
            requestIdentifier: { prefix + $0 }
        )
        XCTAssertEqual(afterCancellation, ["1": "delivered-cycle"])
        // On re-enable/resume, the delivered cycle stays silent while the
        // explicitly cancelled cycle gets a replacement reservation.
        XCTAssertTrue(InventoryDomain.shouldSkipReschedule(
            hasRecord: afterCancellation["1"] == records["1"],
            fireDate: now.addingTimeInterval(5), now: now
        ))
        XCTAssertFalse(InventoryDomain.shouldSkipReschedule(
            hasRecord: afterCancellation["2"] == records["2"],
            fireDate: now.addingTimeInterval(5), now: now
        ))
        XCTAssertEqual(InventoryDomain.recordsAfterCancellingPending(
            records, pendingIDs: [], requestIdentifier: { prefix + $0 }
        ), records)
    }

    func testResumingPauseDoesNotNotifyAnAlreadyDeliveredStockCycle() throws {
        let item = try InventoryDomain.makeItem(from: ItemDraft(
            name: "水", category: "", unit: "本", stock: "2", speed: "1", displayMode: .perDayAmount
        ), now: Date(timeIntervalSince1970: 0))
        let shifted = InventoryDomain.shiftItemsForPause(
            [item], pauseStartedAt: Date(timeIntervalSince1970: 86_400),
            resumedAt: Date(timeIntervalSince1970: 3 * 86_400)
        )
        let records = InventoryDomain.recordsAfterPauseShift(
            [String(item.id): item.notificationCycleKey], before: [item], after: shifted
        )
        XCTAssertEqual(records[String(item.id)], shifted[0].notificationCycleKey)
        XCTAssertTrue(InventoryDomain.recordsAfterPauseShift(
            [:], before: [item], after: shifted
        ).isEmpty)
    }
}
