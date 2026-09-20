import XCTest

@MainActor
final class MigrationUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), element.debugDescription, file: file, line: line)
        element.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func returnToList() {
        tap(app.navigationBars.buttons["ミニアプリ"])
        XCTAssertTrue(app.buttons["miniapp.counter"].waitForExistence(timeout: 5))
    }

    private func showMiniAppList() {
        let counter = app.buttons["miniapp.counter"]
        if counter.waitForExistence(timeout: 1) { return }
        returnToList()
    }

    func testBackupRoundTripRestoresOnlySelectedCounter() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        showMiniAppList()
        tap(app.buttons["miniapp.counter"])
        tap(app.buttons["1を追加"])
        let original = app.staticTexts["counter.value"].label
        returnToList()
        tap(app.buttons["miniapp.reminder"])
        let message = app.textFields["例: 水を飲む"]
        tap(message)
        let previous = message.value as? String ?? ""
        if !previous.isEmpty && previous != message.placeholderValue {
            message.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        message.typeText("Keep during restore")
        tap(app.buttons["保存"])
        XCTAssertTrue(app.staticTexts["保存しました"].waitForExistence(timeout: 5))
        returnToList()
        tap(app.buttons["backup.open"])
        let export = app.buttons["backup.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertFalse(export.isEnabled)
        let counter = app.switches["backup.export.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        counter.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(export.isEnabled)
        tap(export)
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 20))
        capture("backup-file-exporter")
        tap(app.buttons["保存"])
        XCTAssertTrue(app.staticTexts["バックアップを書き出しました。"].waitForExistence(timeout: 20))
        tap(app.buttons["閉じる"])
        tap(app.buttons["miniapp.counter"])
        tap(app.buttons["1を追加"])
        let changed = app.staticTexts["counter.value"].label
        XCTAssertNotEqual(changed, original)
        returnToList()
        tap(app.buttons["backup.open"])
        tap(app.buttons["backup.import"])
        tap(app.buttons["ブラウズ"])
        tap(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "このiPhone内")).firstMatch)
        // This test runs once on a fresh CI simulator, after the ZIP round trip.
        // Require exactly one dated JSON; never select an arbitrary earlier ZIP or JSON.
        let jsonFiles = app.cells.matching(NSPredicate(format: "label MATCHES %@",
            #"JibunKit-backup-[0-9]{8}-[0-9]{6}\.json(,.*)?"#))
        XCTAssertTrue(jsonFiles.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(jsonFiles.count, 1, "Expected only this test's JSON export: \(app.debugDescription)")
        let filename = try XCTUnwrap(jsonFiles.firstMatch.label.split(separator: ",").first).description
        // Reuse the exact name for both imports, independently of Files view mode.
        let file = app.cells.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@",
                                                 filename, filename + ",")).firstMatch
        func selectBackupFile() {
            tap(app.buttons["OverflowBarButtonItem"])
            capture("backup-files-view-menu")
            let list = app.buttons["リスト"]
            XCTAssertTrue(list.waitForExistence(timeout: 5), app.debugDescription)
            tap(list)
            XCTAssertTrue(file.waitForExistence(timeout: 15), app.debugDescription)
            capture("backup-files-list")
            // Diagnostic hypothesis: the cell/filename hit points used in the
            // previous runs may not invoke the document picker's primary action.
            // Record selectability separately, then try the visible icon region.
            print("Backup file candidate enabled=\(file.isEnabled) hittable=\(file.isHittable) frame=\(file.frame)")
            XCTAssertTrue(file.isEnabled, "Backup JSON is present but disabled: \(app.debugDescription)")
            XCTAssertTrue(file.isHittable, "Backup JSON is present but not hittable: \(app.debugDescription)")
            file.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.5)).tap()
            capture("backup-after-file-selection")
            XCTAssertTrue(app.buttons["backup.restore"].waitForExistence(timeout: 20), app.debugDescription)
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        capture("backup-file-importer")
        selectBackupFile()
        let restore = app.buttons["backup.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 20))
        XCTAssertFalse(restore.isEnabled)
        XCTAssertFalse(app.switches["backup.restore.reminder"].exists)
        let selection = app.switches["backup.restore.counter"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        selection.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tap(restore)
        tap(app.alerts.buttons["キャンセル"])
        tap(app.buttons["閉じる"])
        tap(app.buttons["miniapp.counter"])
        XCTAssertEqual(app.staticTexts["counter.value"].label, changed)
        returnToList()
        // Read again because closing the screen intentionally discards the imported file.
        tap(app.buttons["backup.open"])
        tap(app.buttons["backup.import"])
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        selectBackupFile()
        XCTAssertTrue(selection.waitForExistence(timeout: 20))
        selection.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tap(restore)
        tap(app.alerts.buttons["置き換えて復元"])
        XCTAssertTrue(app.staticTexts["カウンターを復元しました。"].waitForExistence(timeout: 10))
        capture("backup-restored-counter")
        tap(app.buttons["閉じる"])
        app.terminate()
        app.launch()
        showMiniAppList()
        tap(app.buttons["miniapp.counter"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["counter.value"].label, original)
        returnToList()
        tap(app.buttons["miniapp.reminder"])
        XCTAssertEqual(message.value as? String, "Keep during restore")
    }

    func testMiniAppSearchFiltersAndOpensResults() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        showMiniAppList()
        // Reveal the standard navigation search field.
        app.swipeDown()
        let search = app.searchFields.firstMatch
        tap(search)
        search.typeText("COUNTER")
        XCTAssertTrue(app.buttons["miniapp.counter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["miniapp.reminder"].exists)
        tap(app.buttons["miniapp.counter"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        returnToList()
        tap(search)
        let query = search.value as? String ?? ""
        if !query.isEmpty && query != search.placeholderValue {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: query.count))
        }
        search.typeText("zz-no-matching-app")
        XCTAssertFalse(app.buttons["miniapp.counter"].exists)
        XCTAssertFalse(app.buttons["miniapp.reminder"].exists)
        capture("mini-app-search-no-results")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zz-no-matching-app".count))
        XCTAssertTrue(app.buttons["miniapp.counter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["miniapp.reminder"].waitForExistence(timeout: 5))
    }

    func testMiniAppLinksOpenColdAndSwitchWarm() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        showMiniAppList()
        tap(app.buttons["miniapp.reminder"])
        XCTAssertTrue(app.textFields["例: 水を飲む"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        app.launch()
        // Establish that a different owner really is restored, rather than
        // claiming URL precedence from an unsaved in-memory selection.
        XCTAssertTrue(app.textFields["例: 水を飲む"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/counter")))
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 10))
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/reminder")))
        XCTAssertTrue(app.textFields["例: 水を飲む"].waitForExistence(timeout: 10))
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/missing")))
        XCTAssertTrue(app.textFields["例: 水を飲む"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/counter?delete=true")))
        XCTAssertTrue(app.textFields["例: 水を飲む"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/counter")))
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 10))
        capture("mini-app-link-counter")
        returnToList()
    }

    func testPersistenceAndHostIntegration() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        showMiniAppList()
        capture("01-mini-app-list")

        tap(app.buttons["miniapp.counter"])
        tap(app.buttons["1を追加"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        let counterValue = app.staticTexts["counter.value"].label
        XCTAssertNotEqual(counterValue, "0")
        returnToList()

        tap(app.buttons["miniapp.reminder"])
        XCTAssertEqual(app.navigationBars.count, 1, "Only the host owns root navigation")
        let message = app.textFields["例: 水を飲む"]
        tap(message)
        let previous = message.value as? String ?? ""
        if !previous.isEmpty && previous != message.placeholderValue {
            message.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        message.typeText("Independent reminder")
        tap(app.buttons["保存"])
        XCTAssertTrue(app.staticTexts["保存しました"].waitForExistence(timeout: 5))
        returnToList()
        tap(app.buttons["miniapp.counter"])
        XCTAssertEqual(app.staticTexts["counter.value"].label, counterValue)
        returnToList()
        app.terminate()
        app.launch()
        showMiniAppList()
        tap(app.buttons["miniapp.counter"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["counter.value"].label, counterValue)
        returnToList()
        tap(app.buttons["miniapp.reminder"])
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.value as? String, "Independent reminder")
        capture("02-restored-independent-stores")
    }

    func testNotificationDeliveryAndRouting() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        showMiniAppList()
        tap(app.buttons["miniapp.reminder"])
        let message = app.textFields["例: 水を飲む"]
        tap(message)
        let previous = message.value as? String ?? ""
        if !previous.isEmpty && previous != message.placeholderValue {
            message.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        message.typeText("Migration reminder")
        tap(app.buttons["10秒後に通知"])
        let featureConsent = app.alerts["リマインダーが通知を利用します"]
        if featureConsent.waitForExistence(timeout: 2) { tap(featureConsent.buttons["許可"]) }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["許可", "Allow"])
        ).firstMatch
        let scheduled = app.staticTexts["10秒後の通知を予約しました"]
        if !scheduled.waitForExistence(timeout: 1), allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/counter")))
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        let notification = springboard.staticTexts["Migration reminder"].firstMatch
        // Always use Notification Center: even a visible banner can disappear
        // between the existence check, screenshot, and tap.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7)))
        XCTAssertTrue(notification.waitForExistence(timeout: 20), springboard.debugDescription)
        let delivered = XCTAttachment(screenshot: springboard.screenshot())
        delivered.name = "08-delivered-notification"
        delivered.lifetime = .keepAlways
        add(delivered)
        print("Notification Center before tap:\n\(springboard.debugDescription)")
        print("Notification body frame: \(notification.frame), hittable: \(notification.isHittable)")
        // SpringBoard exposes the notification's action on the platter button;
        // the nested TextContent.Primary can consume a tap without opening it.
        let card = springboard.buttons.matching(identifier: "ShortLook.Platter.Content.Seamless")
            .containing(.staticText, identifier: "Migration reminder").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), springboard.debugDescription)
        // SpringBoard logs "Hinting side swipe instead of executing action"
        // for a tap on this notification list. Use its explicit open gesture.
        card.swipeRight()
        var foreground = app.wait(for: .runningForeground, timeout: 5)
        if !foreground {
            let open = springboard.buttons.matching(
                NSPredicate(format: "label IN %@", ["開く", "Open"])
            ).firstMatch
            if open.waitForExistence(timeout: 3) {
                open.tap()
                foreground = app.wait(for: .runningForeground, timeout: 10)
            }
        }
        print("Notification Center after tap:\n\(springboard.debugDescription)")
        XCTAssertTrue(foreground, "Notification tap did not bring JibunKit to the foreground")
        XCTAssertTrue(app.textFields["例: 水を飲む"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["例: 水を飲む"].value as? String, "Migration reminder")
        capture("09-notification-routed-to-reminder")
    }

    func testStandaloneCounterUsesIndependentStorage() throws {
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        showMiniAppList()
        tap(app.buttons["miniapp.counter"])
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        let original = app.staticTexts["counter.value"].label
        let standalone = XCUIApplication(bundleIdentifier: "com.jibunkit.counterexample")
        standalone.launchArguments = app.launchArguments
        standalone.launch()
        XCTAssertTrue(standalone.staticTexts["counter.value"].waitForExistence(timeout: 10))
        let before = standalone.staticTexts["counter.value"].label
        tap(standalone.buttons["1を追加"])
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", before),
            object: standalone.staticTexts["counter.value"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let after = standalone.staticTexts["counter.value"].label
        standalone.terminate()
        standalone.launch()
        XCTAssertTrue(standalone.staticTexts["counter.value"].waitForExistence(timeout: 10))
        XCTAssertEqual(standalone.staticTexts["counter.value"].label, after)
        app.activate()
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["counter.value"].label, original)
    }
}
