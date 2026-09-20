import XCTest
import CoreLocation

/// Simulator-only OS-surface checks. A physical-device run remains necessary
/// for hardware camera behavior; these tests prove rendered OS copy and actual
/// iPadOS window-session restoration without claiming physical-device coverage.
@MainActor
final class P2OSSurfaceUITests: WidgetGalleryTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testNormalCounterWidgetRendersEnglishInGalleryAndHome() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        guard openGallery(on: springboard) else { return }
        guard select(appName: "JibunKit", widgetName: "Counter", on: springboard) else { return }

        XCTAssertTrue(springboard.staticTexts["Shows the value updated by the app and shortcuts."]
            .waitForExistence(timeout: 10), springboard.debugDescription)
        let preview = springboard.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "JibunKit", "Counter")).firstMatch
        guard require(preview, timeout: 10, on: springboard), isVisible(preview, in: springboard) else {
            recordFailure(on: springboard, message: "Normal Counter Widget preview is not visible")
            return
        }
        guard assertText(expected: ["Counter"], in: springboard.screenshot(), region: preview.frame,
                         screenFrame: springboard.frame, evidenceName: "p2-normal-widget-gallery-en") else { return }
        let add = addWidgetControl(in: springboard)
        guard require(add, timeout: 5, on: springboard), isVisible(add, in: springboard) else { return }
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard waitUntilAbsent(add, timeout: 10, on: springboard) else { return }
        _ = waitForText(expected: ["Counter"], absent: [], timeout: 20, on: springboard,
                        evidenceName: "p2-normal-widget-home-en")
    }

    func testCameraPromptRendersRepresentativeEnglishUsageDescription() throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p2-ar")))
        let permissionCopy = app.buttons["p2.ar.camera-permission-copy"]
        XCTAssertTrue(permissionCopy.waitForExistence(timeout: 15), app.debugDescription)
        permissionCopy.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let purpose = springboard.staticTexts["Use the camera for the foreground AR feature."]
        XCTAssertTrue(purpose.waitForExistence(timeout: 10), springboard.debugDescription)
        let deny = springboard.buttons.matching(
            NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 5), springboard.debugDescription)
        deny.tap()
    }

    func testTwoWindowsRestoreDistinctOwnersAndStateThenCloseOne() throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/p2-scene-a")))
        var windows = waitForWindows(count: 1)
        var aWindow = try window(owner: "p2-scene-a", in: windows)
        let initialA = try XCTUnwrap(Int(value("p2.scene.count", in: aWindow)))
        tap(aWindow.buttons["p2.scene.increment"], in: aWindow)
        let retainedA = String(initialA + 1)
        let aSession = value("p2.scene.session", in: aWindow)
        tap(aWindow.buttons["p2.scene.new-window"], in: aWindow)

        windows = waitForWindows(count: 2)
        let newWindow = try XCTUnwrap(windows.first { !$0.staticTexts["p2.scene.owner"].exists })
        let search = newWindow.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), newWindow.debugDescription)
        search.tap()
        search.typeText("Scene B")
        tap(newWindow.buttons["miniapp.p2-scene-b"], in: newWindow)
        var bWindow = try window(owner: "p2-scene-b", in: waitForWindows(count: 2))
        let initialB = try XCTUnwrap(Int(value("p2.scene.count", in: bWindow)))
        tap(bWindow.buttons["p2.scene.increment"], in: bWindow)
        tap(bWindow.buttons["p2.scene.increment"], in: bWindow)
        var retainedB = String(initialB + 2)
        if retainedB == retainedA {
            tap(bWindow.buttons["p2.scene.increment"], in: bWindow)
            retainedB = String(initialB + 3)
        }
        let bSession = value("p2.scene.session", in: bWindow)
        XCTAssertNotEqual(aSession, bSession)
        XCTAssertNotEqual(retainedA, retainedB, "The two restored windows need distinguishable state")

        // Give SwiftUI the normal background lifecycle before process death;
        // killing an active app does not establish a scene save opportunity.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["p2.scene.owner"].firstMatch.waitForExistence(timeout: 15),
                      app.debugDescription)
        let reopened = try XCTUnwrap(contentWindows().first)
        let savedSessions = Set(value("p2.scene.open-sessions", in: reopened)
            .split(separator: "\n").map(String.init))
        XCTAssertEqual(savedSessions, Set([aSession, bSession]),
                       "Both original OS sessions must survive process termination")
        // An archived UISceneSession need not have a connected UIWindowScene.
        // Reactivate the retained session, never create a replacement window.
        if contentWindows().count == 1 {
            tap(reopened.buttons["p2.scene.activate-other"], in: reopened)
        }
        windows = waitForWindows(count: 2)
        aWindow = try window(owner: "p2-scene-a", in: windows)
        bWindow = try window(owner: "p2-scene-b", in: windows)
        XCTAssertEqual(value("p2.scene.session", in: aWindow), aSession)
        XCTAssertEqual(value("p2.scene.session", in: bWindow), bSession)
        XCTAssertEqual(value("p2.scene.count", in: aWindow), retainedA)
        XCTAssertEqual(value("p2.scene.count", in: bWindow), retainedB)

        if !aWindow.buttons["p2.scene.close-window"].isHittable {
            tap(bWindow.buttons["p2.scene.activate-other"], in: bWindow)
        }
        tap(aWindow.buttons["p2.scene.close-window"], in: aWindow)
        windows = waitForWindows(count: 1)
        bWindow = try window(owner: "p2-scene-b", in: windows)
        XCTAssertEqual(value("p2.scene.session", in: bWindow), bSession)
        XCTAssertEqual(value("p2.scene.count", in: bWindow), retainedB)
    }

    func testStandardLocationCallbackArrivesWhileAppIsBackgrounded() throws {
        let back = app.buttons["miniapp.back-to-list"]
        if back.waitForExistence(timeout: 2) { back.tap() }
        let management = app.buttons["management.open"]
        tap(management, in: app)
        let consent = app.buttons["management.consent.p2-location-tracker.location"]
        for _ in 0..<20 where !consent.isHittable { app.swipeUp() }
        tap(consent, in: app)
        let allow = app.buttons["許可"]
        tap(allow, in: app)
        let close = app.buttons["閉じる"]
        tap(close, in: app)

        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: 37.3349, longitude: -122.0090))
        defer { XCUIDevice.shared.location = nil }
        XCUIDevice.shared.system.open(try XCTUnwrap(
            URL(string: "jibunkit://mini-app/p2-location-tracker")))
        let disclosure = app.buttons["受信記録（座標なし・最新64件）"]
        let observations = app.staticTexts["p2.location.p2-location-tracker.observations"]
        let events = app.staticTexts["p2.location.p2-location-tracker.events"]
        let beforeEvents = events.label
        let start = app.buttons["p2.location.tracker.background"]
        tap(start, in: app)
        let status = app.staticTexts["p2.location.p2-location-tracker.status"]
        let sample = app.staticTexts["p2.location.p2-location-tracker.sample"]
        let baselineDeadline = Date().addingTimeInterval(15)
        while (events.label == beforeEvents
                || !status.label.hasPrefix("位置更新 ")
                || !sample.label.contains("37.3349")
                || !sample.label.contains("-122.009"))
                && Date() < baselineDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertNotEqual(events.label, beforeEvents, app.debugDescription)
        XCTAssertTrue(status.label.hasPrefix("位置更新 "), app.debugDescription)
        XCTAssertTrue(sample.label.contains("37.3349") && sample.label.contains("-122.009"),
                      app.debugDescription)
        tap(disclosure, in: app)
        XCTAssertTrue(observations.waitForExistence(timeout: 10), app.debugDescription)
        let baselineLines = observations.label.split(separator: "\n").map(String.init)
        let baselineLocation = try XCTUnwrap(baselineLines.last { $0.contains("位置callback") })
        let process = try XCTUnwrap(baselineLocation.split(separator: " ").first {
            $0.hasPrefix("起動")
        })
        tap(disclosure, in: app)

        let delivered = XCTDarwinNotificationExpectation(
            notificationName: "com.jibunkit.tests.p2-location-tracker.background-callback")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10),
                      "App did not reach runningBackground before location injection")
        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: 37.3360, longitude: -122.0090))
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 30), .completed,
                       "No Core Location callback completed while UIApplication was background")

        app.activate()
        tap(disclosure, in: app)
        XCTAssertTrue(observations.waitForExistence(timeout: 10), app.debugDescription)
        let lines = observations.label.split(separator: "\n").map(String.init)
        let old = Set(baselineLines)
        let backgroundEntry = lines.first {
            !old.contains($0) && $0.contains("[background]")
                && $0.contains(String(process)) && $0.contains("位置callback")
        }
        XCTAssertNotNil(backgroundEntry, observations.label)
        XCTAssertFalse(app.staticTexts[
            "p2.location.p2-location-tracker.observation-error"].exists, app.debugDescription)
        tap(disclosure, in: app)
        tap(app.buttons["p2.location.tracker.stop"], in: app)
    }

    func testGeofenceEnterAndExitCallbacksUseRegionsOwner() throws {
        let back = app.buttons["miniapp.back-to-list"]
        if back.waitForExistence(timeout: 2) { back.tap() }
        tap(app.buttons["management.open"], in: app)
        let consent = app.buttons["management.consent.p2-location-regions.location"]
        for _ in 0..<20 where !consent.isHittable { app.swipeUp() }
        tap(consent, in: app)
        tap(app.buttons["許可"], in: app)
        tap(app.buttons["閉じる"], in: app)

        // Both points are well beyond the boundary's uncertainty cushion.
        let outside = CLLocation(latitude: 37.3280, longitude: -122.0090)
        let inside = CLLocation(latitude: 37.3349, longitude: -122.0090)
        XCUIDevice.shared.location = XCUILocation(location: outside)
        defer { XCUIDevice.shared.location = nil }
        XCUIDevice.shared.system.open(try XCTUnwrap(
            URL(string: "jibunkit://mini-app/p2-location-regions")))
        let events = app.staticTexts["p2.location.p2-location-regions.events"]
        let beforeEvents = events.label
        tap(app.buttons["p2.location.regions.current-location"], in: app)
        let sample = app.staticTexts["p2.location.p2-location-regions.sample"]
        let outsideDeadline = Date().addingTimeInterval(15)
        while (events.label == beforeEvents
                || !sample.label.contains("37.328")
                || !sample.label.contains("-122.009"))
                && Date() < outsideDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertNotEqual(events.label, beforeEvents, app.debugDescription)
        XCTAssertTrue(sample.label.contains("37.328") && sample.label.contains("-122.009"),
                      "The initial outside location was not delivered: \(app.debugDescription)")
        tap(app.buttons["p2.location.regions.stop"], in: app)

        let register = app.buttons["p2.location.regions.diagnostic-geofence"]
        for _ in 0..<10 where !register.isHittable { app.swipeUp() }
        tap(register, in: app)
        let status = app.staticTexts["p2.location.p2-location-regions.status"]
        XCTAssertEqual(status.label, "geofence登録 diagnostic-geofence", app.debugDescription)
        let state = app.buttons["p2.location.regions.diagnostic-geofence-state"]
        let monitoringDeadline = Date().addingTimeInterval(10)
        while status.label != "状態 diagnostic-geofence: outside"
                && Date() < monitoringDeadline {
            tap(state, in: app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertEqual(status.label, "状態 diagnostic-geofence: outside",
                       "Core Location did not confirm the registered region's outside state")
        let disclosure = app.buttons["受信記録（座標なし・最新64件）"]
        for _ in 0..<10 where !disclosure.isHittable { app.swipeUp() }
        tap(disclosure, in: app)
        let observations = app.staticTexts["p2.location.p2-location-regions.observations"]
        XCTAssertTrue(observations.waitForExistence(timeout: 10), app.debugDescription)
        let baselineLines = observations.label.split(separator: "\n").map(String.init)
        let registrationLine = try XCTUnwrap(baselineLines.last {
            $0.contains("geofence登録 diagnostic-geofence")
        })
        let process = try XCTUnwrap(registrationLine.split(separator: " ").first {
            $0.hasPrefix("起動")
        })
        tap(disclosure, in: app)

        let entered = XCTDarwinNotificationExpectation(
            notificationName: "com.jibunkit.tests.p2-location-regions.geofence-enter")
        XCUIDevice.shared.location = XCUILocation(location: inside)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 35), .completed,
                       "No geofence enter callback after crossing and dwelling inside")

        let exited = XCTDarwinNotificationExpectation(
            notificationName: "com.jibunkit.tests.p2-location-regions.geofence-exit")
        XCUIDevice.shared.location = XCUILocation(location: outside)
        XCTAssertEqual(XCTWaiter.wait(for: [exited], timeout: 35), .completed,
                       "No geofence exit callback after crossing and dwelling outside")

        tap(disclosure, in: app)
        XCTAssertTrue(observations.waitForExistence(timeout: 10), app.debugDescription)
        let lines = observations.label.split(separator: "\n").map(String.init)
        let baseline = Set(baselineLines)
        let added = lines.filter { !baseline.contains($0) && $0.contains(String(process)) }
        XCTAssertTrue(added.contains { $0.contains("進入callback: diagnostic-geofence") },
                      observations.label)
        XCTAssertTrue(added.contains { $0.contains("退出callback: diagnostic-geofence") },
                      observations.label)
        XCTAssertFalse(app.staticTexts[
            "p2.location.p2-location-regions.observation-error"].exists, app.debugDescription)
        tap(disclosure, in: app)
        let remove = app.buttons["p2.location.regions.diagnostic-geofence-remove"]
        for _ in 0..<10 where !remove.isHittable { app.swipeDown() }
        tap(remove, in: app)
    }

    private func waitForWindows(count: Int) -> [XCUIElement] {
        let deadline = Date().addingTimeInterval(20)
        while contentWindows().count != count && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        let windows = contentWindows()
        XCTAssertEqual(windows.count, count, app.debugDescription)
        return windows
    }

    private func contentWindows() -> [XCUIElement] {
        // XCTest also exposes an empty auxiliary UIWindow after search. Only
        // windows containing the host NavigationStack represent our scenes.
        app.windows.allElementsBoundByIndex.filter { $0.navigationBars.count > 0 }
    }

    private func window(owner: String, in windows: [XCUIElement]) throws -> XCUIElement {
        try XCTUnwrap(windows.first { window in
            let value = window.staticTexts["p2.scene.owner"]
            return value.exists && value.label == owner
        }, "No OS window displays owner \(owner): \(app.debugDescription)")
    }

    private func tap(_ element: XCUIElement, in window: XCUIElement) {
        let deadline = Date().addingTimeInterval(10)
        while (!element.exists || !element.isHittable) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(element.exists && element.isHittable, window.debugDescription)
        element.tap()
    }

    private func value(_ identifier: String, in window: XCUIElement) -> String {
        let element = window.staticTexts[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 10), window.debugDescription)
        return element.label
    }
}
