import Foundation
import XCTest
@testable import ZaikoFeature

final class ZaikoOperationTests: XCTestCase {
    func testBothConsumptionModesProduceTheSameStockEstimate() throws {
        let byTime = try InventoryDomain.consumptionRate(from: "2", mode: .perUnitTime)
        let byAmount = try InventoryDomain.consumptionRate(from: "0.5", mode: .perDayAmount)
        XCTAssertEqual(byTime, byAmount)
        XCTAssertEqual(InventoryDomain.speedToFormValue(rate: byTime, mode: .perUnitTime), "2")
        XCTAssertEqual(InventoryDomain.speedToFormValue(rate: byTime, mode: .perDayAmount), "0.5")
    }

    func testRestockUsesMeasuredConsumptionAndPreservesIdentity() throws {
        let purchased = Date(timeIntervalSince1970: 0)
        let item = try InventoryDomain.makeItem(from: ItemDraft(
            name: "Rice", category: "Food", unit: "kg", stock: "10", speed: "2", displayMode: .perDayAmount
        ), now: purchased)
        let restocked = InventoryDomain.applyRestock(
            to: item, remaining: 4, added: 6,
            pauseState: GlobalPauseState(active: false, startedAt: nil),
            now: purchased.addingTimeInterval(6 * 86_400)
        )
        XCTAssertEqual(restocked.id, item.id)
        XCTAssertEqual(restocked.name, item.name)
        XCTAssertEqual(restocked.currentStock, 10)
        XCTAssertEqual(restocked.count, 2)
        XCTAssertEqual(try XCTUnwrap(restocked.consumptionRatePerDay), 1.7, accuracy: 0.0001)
        XCTAssertEqual(restocked.lastPurchased, purchased.addingTimeInterval(6 * 86_400))
    }

    func testZeroStockAndCategoryDefaultsAreRetained() throws {
        let item = try InventoryDomain.makeItem(from: ItemDraft(
            name: " Rice ", category: " ", unit: " kg ", stock: "0", speed: "1", displayMode: .perDayAmount
        ))
        XCTAssertEqual(item.name, "Rice")
        XCTAssertEqual(item.category, InventoryDomain.defaultCategory)
        XCTAssertEqual(item.unit, "kg")
        XCTAssertTrue(InventoryDomain.isAlert(
            item: item, pauseState: GlobalPauseState(active: false, startedAt: nil), thresholdDays: 7
        ))
    }

    func testNonFiniteAndInvalidNumericInputsAreRejected() {
        for value in ["", "abc", "nan", "inf", "-inf", "1e999", "-1"] {
            XCTAssertThrowsError(try InventoryDomain.parseNonNegativeNumber(value, fieldName: "stock"), value)
        }
        for value in ["0", "-1", "inf", "nan"] {
            XCTAssertThrowsError(try InventoryDomain.consumptionRate(from: value, mode: .perDayAmount), value)
        }
        XCTAssertThrowsError(try InventoryDomain.consumptionRate(from: "1e-320", mode: .perUnitTime))
    }
}
