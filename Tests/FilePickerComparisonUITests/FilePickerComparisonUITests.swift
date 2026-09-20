import XCTest

@MainActor
final class FilePickerComparisonUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.file-picker-comparison")
    private let filename = "JibunKit-picker-comparison.json"

    override func setUpWithError() throws {
        continueAfterFailure = true
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
    }

    func testNativeOpenThenRelaunchedSwiftUIOpenReadIdenticalFixture() {
        tap(app.buttons["picker.export-native"])
        guard openOnMyIPhoneIfNeeded() else {
            capture("export-location-failure")
            XCTFail("保存先の「このiPhone内」へ到達できません")
            return
        }
        let save = app.buttons["保存"]
        XCTAssertTrue(save.waitForExistence(timeout: 15), "native exportの保存ボタンがありません")
        if save.exists { save.tap() }
        guard waitForStatus(prefix: "uikit-export.callback", timeout: 15) else {
            capture("export-callback-failure")
            XCTFail("native export callbackがありません。import比較は未実施")
            return
        }

        tap(app.buttons["picker.import-native"])
        let nativeSelected = selectExportedFile()
        let nativeRead = nativeSelected && waitForStatus(prefix: "uikit-open.content-match", timeout: 15)
        if !nativeRead { capture("native-open-failure") }

        // A provider failure may leave its remote picker visible. Termination is
        // the bounded cleanup; the SwiftUI comparison still runs independently.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["picker.import-swiftui"].waitForExistence(timeout: 15))
        tap(app.buttons["picker.import-swiftui"])
        let swiftUISelected = selectExportedFile()
        let swiftUIRead = swiftUISelected && waitForStatus(prefix: "swiftui.content-match", timeout: 15)
        if !swiftUIRead { capture("swiftui-open-failure") }

        XCTAssertTrue(nativeRead, "UIKit open(asCopy:false) did not return and read the fixture")
        XCTAssertTrue(swiftUIRead, "SwiftUI fileImporter did not return and read the fixture")
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        if element.exists && element.isHittable { element.tap() }
    }

    private func openOnMyIPhoneIfNeeded() -> Bool {
        // A fresh simulator may show Files onboarding. Handle each known action
        // at most once and continue only after observing the actual destination.
        for label in ["続ける", "完了"] {
            let action = app.buttons[label]
            if action.waitForExistence(timeout: 3), action.isHittable { action.tap() }
        }
        if app.buttons["保存"].waitForExistence(timeout: 5), app.staticTexts["このiPhone内"].exists { return true }
        let browse = app.buttons["ブラウズ"]
        if browse.waitForExistence(timeout: 5) { browse.tap() }
        let location = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "このiPhone内")).firstMatch
        guard location.waitForExistence(timeout: 10) else { return false }
        if location.isHittable { location.tap() }
        return app.buttons["保存"].waitForExistence(timeout: 10)
    }

    private func selectExportedFile() -> Bool {
        let browse = app.buttons["ブラウズ"]
        if browse.waitForExistence(timeout: 4) { browse.tap() }
        let location = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "このiPhone内")).firstMatch
        if location.waitForExistence(timeout: 8), location.isHittable { location.tap() }
        let exact = app.cells.matching(NSPredicate(format: "label == %@", filename)).firstMatch
        let prefixed = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "JibunKit-picker-comparison")).firstMatch
        let file = exact.waitForExistence(timeout: 10) ? exact : prefixed
        guard file.exists, file.isHittable else { return false }
        file.tap()
        return true
    }

    private func waitForStatus(prefix: String, timeout: TimeInterval) -> Bool {
        let status = app.staticTexts["picker.status"]
        guard status.waitForExistence(timeout: 5) else { return false }
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
