#if os(iOS)
import XCTest

/// Exercises initial scene restoration with an owner that is absent before the
/// scene root is created. This must not pass through the active-scene removal
/// observer, which would clear the same value through a different path.
@MainActor
final class P2SceneRestorationAdmissionUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testUnavailableSavedOwnerIsClearedInsteadOfRevivedWhenItReturns() throws {
        let sceneAURL = try XCTUnwrap(URL(string: "jibunkit://mini-app/p2-scene-a"))
        XCUIDevice.shared.system.open(sceneAURL)
        XCTAssertTrue(owner("p2-scene-a").waitForExistence(timeout: 15), app.debugDescription)

        backgroundAndTerminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(owner("p2-scene-a").waitForExistence(timeout: 15),
                      "The precondition must use an OS-restored scene selection: \(app.debugDescription)")

        backgroundAndTerminate()
        app.launchArguments.append("--p2-scenes-omit-a-at-launch")
        app.launch()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(owner("p2-scene-a").exists)

        backgroundAndTerminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 15),
                      "A returned owner must not revive a discarded scene selection: \(app.debugDescription)")
        XCTAssertFalse(owner("p2-scene-a").exists)
    }

    private func backgroundAndTerminate() {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
    }

    private func owner(_ value: String) -> XCUIElement {
        app.staticTexts.matching(identifier: "p2.scene.owner")
            .matching(NSPredicate(format: "label == %@", value)).firstMatch
    }
}
#endif
