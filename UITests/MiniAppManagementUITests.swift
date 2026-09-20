import XCTest

@MainActor
final class MiniAppManagementUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    override func setUpWithError() throws { continueAfterFailure = false }

    private func showMiniAppList() {
        if app.buttons["management.open"].waitForExistence(timeout: 1) { return }
        tap(app.buttons["miniapp.back-to-list"])
        XCTAssertTrue(app.buttons["management.open"].waitForExistence(timeout: 5))
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        element.tap()
    }

    private func status(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text),
            object: app.staticTexts["management.status.counter"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed,
                       app.debugDescription, file: file, line: line)
    }

    func testConsentRefusalPreservesOrdinaryReminderEditing() {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        showMiniAppList()
        tap(app.buttons["management.open"])
        tap(app.buttons["management.consent.reminder.notifications"])
        tap(app.buttons["未確認"])
        tap(app.buttons["閉じる"])
        tap(app.buttons["miniapp.reminder"])
        tap(app.buttons["10秒後に通知"])
        let consent = app.alerts["リマインダーが通知を利用します"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        XCTAssertTrue(consent.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "保存と閲覧")).firstMatch.exists)
        tap(consent.buttons["拒否"])
        tap(app.buttons["10秒後に通知"])
        XCTAssertTrue(app.staticTexts["リマインダーでの通知利用を拒否しています。ミニアプリの管理で変更できます。"].waitForExistence(timeout: 5))
        let field = app.textFields["例: 水を飲む"]
        tap(field)
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText("Allowed without notifications")
        tap(app.buttons["保存"])
        XCTAssertTrue(app.staticTexts["保存しました"].waitForExistence(timeout: 5))
        tap(app.buttons["miniapp.back-to-list"])
        tap(app.buttons["management.open"])
        tap(app.buttons["management.consent.reminder.notifications"])
        tap(app.buttons["許可"])
        tap(app.buttons["閉じる"])
    }

    func testDisableRestartCancelDeleteAndReregisterPreserveReminder() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        showMiniAppList()
        tap(app.buttons["miniapp.counter"])
        let value = app.staticTexts["counter.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        let before = value.label
        tap(app.buttons["1を追加"])
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let saved = value.label
        tap(app.buttons["miniapp.back-to-list"])
        tap(app.buttons["miniapp.reminder"])
        let field = app.textFields["例: 水を飲む"]
        tap(field)
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText("Keep other owner")
        tap(app.buttons["保存"])
        XCTAssertTrue(app.staticTexts["保存しました"].waitForExistence(timeout: 5))
        tap(app.buttons["miniapp.back-to-list"])
        tap(app.buttons["management.open"])
        tap(app.buttons["management.disable.counter"])
        status("無効（データを保持）")
        tap(app.buttons["閉じる"])
        XCTAssertFalse(app.buttons["miniapp.counter"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["miniapp.reminder"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["miniapp.counter"].exists)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/counter")))
        XCTAssertFalse(app.staticTexts["counter.value"].exists)
        tap(app.buttons["management.open"])
        status("無効（データを保持）")
        tap(app.buttons["management.enable.counter"])
        status("有効")
        tap(app.buttons["management.delete.counter"])
        tap(app.alerts.buttons["キャンセル"])
        status("有効")
        tap(app.buttons["閉じる"])
        tap(app.buttons["miniapp.counter"])
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, saved)
        tap(app.buttons["miniapp.back-to-list"])
        tap(app.buttons["management.open"])
        tap(app.buttons["management.delete.counter"])
        tap(app.alerts.buttons["削除"])
        status("削除済み")
        tap(app.buttons["management.enable.counter"])
        status("有効")
        tap(app.buttons["閉じる"])
        tap(app.buttons["miniapp.counter"])
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "0")
        tap(app.buttons["miniapp.back-to-list"])
        tap(app.buttons["miniapp.reminder"])
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Keep other owner")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "p0-b-removal-keeps-other-owner"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
