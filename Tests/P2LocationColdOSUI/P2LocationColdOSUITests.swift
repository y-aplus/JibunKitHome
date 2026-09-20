import CoreLocation
import XCTest

/// Optional Simulator diagnostic. A timeout means this Simulator runtime did
/// not expose terminated-app region wakeup; it is not a normal CI failure.
@MainActor
final class P2LocationColdOSUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
    private let outside = CLLocation(latitude: 37.3280, longitude: -122.0090)
    private let inside = CLLocation(latitude: 37.3349, longitude: -122.0090)

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.location = nil
        if app.state != .notRunning { app.terminate() }
    }

    func testTerminatedGeofenceEnterAndExitPersistFromNewProcesses() throws {
        let back = app.buttons["miniapp.back-to-list"]
        if back.waitForExistence(timeout: 2) { back.tap() }
        tap(app.buttons["management.open"])
        let consent = app.buttons["management.consent.p2-location-regions.location"]
        for _ in 0..<20 where !consent.isHittable { app.swipeUp() }
        tap(consent); tap(app.buttons["許可"]); tap(app.buttons["閉じる"])

        XCUIDevice.shared.location = XCUILocation(location: outside)
        XCUIDevice.shared.system.open(try XCTUnwrap(
            URL(string: "jibunkit://mini-app/p2-location-regions")))
        let events = app.staticTexts["p2.location.p2-location-regions.events"]
        let beforeEvents = events.label
        tap(app.buttons["p2.location.regions.current-location"])
        let sample = app.staticTexts["p2.location.p2-location-regions.sample"]
        let locationDeadline = Date().addingTimeInterval(15)
        while (events.label == beforeEvents
                || !sample.label.contains("37.328")
                || !sample.label.contains("-122.009"))
                && Date() < locationDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertNotEqual(events.label, beforeEvents, app.debugDescription)
        XCTAssertTrue(sample.label.contains("37.328") && sample.label.contains("-122.009"),
                      "The outside location was not delivered")
        tap(app.buttons["p2.location.regions.stop"])

        let register = app.buttons["p2.location.regions.diagnostic-geofence"]
        reveal(register, direction: .up); tap(register)
        let status = app.staticTexts["p2.location.p2-location-regions.status"]
        let state = app.buttons["p2.location.regions.diagnostic-geofence-state"]
        let monitoringDeadline = Date().addingTimeInterval(10)
        while status.label != "状態 diagnostic-geofence: outside"
                && Date() < monitoringDeadline {
            tap(state)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertEqual(status.label, "状態 diagnostic-geofence: outside",
                       "Core Location did not confirm monitoring readiness")

        let disclosure = app.buttons["受信記録（座標なし・最新64件）"]
        reveal(disclosure, direction: .up); tap(disclosure)
        let observations = app.staticTexts["p2.location.p2-location-regions.observations"]
        XCTAssertTrue(observations.waitForExistence(timeout: 10), app.debugDescription)
        let baseline = observations.label.split(separator: "\n").map(String.init)
        let registration = try XCTUnwrap(baseline.last {
            $0.contains("geofence登録 diagnostic-geofence")
        })
        let originalProcess = try processToken(in: registration)
        tap(disclosure)

        let enterProcess = try observeColdBoundary(
            event: "enter", location: inside, previousLines: baseline,
            previousProcess: originalProcess)
        let afterEnter = observationLines()
        tap(disclosure)

        _ = try observeColdBoundary(
            event: "exit", location: outside, previousLines: afterEnter,
            previousProcess: enterProcess)
        let remove = app.buttons["p2.location.regions.diagnostic-geofence-remove"]
        reveal(remove, direction: .down); tap(remove)
    }

    private func observeColdBoundary(
        event: String,
        location: CLLocation,
        previousLines: [String],
        previousProcess: String
    ) throws -> String {
        let expectedText = event == "enter"
            ? "進入callback: diagnostic-geofence" : "退出callback: diagnostic-geofence"
        let notification = XCTDarwinNotificationExpectation(
            notificationName: "com.jibunkit.tests.p2-location-regions.geofence-\(event)")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        XCUIDevice.shared.location = XCUILocation(location: location)
        let result = XCTWaiter.wait(for: [notification], timeout: 45)
        guard result == .completed else {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let attachment = XCTAttachment(screenshot: springboard.screenshot())
            attachment.name = "geofence-cold-\(event)-timeout"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("Cold geofence \(event) timed out; app state=\(app.state.rawValue)")
            throw XCTSkip("Simulator did not expose terminated-app geofence \(event) within 45 seconds")
        }
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5),
                      "A foreground relaunch is not cold background delivery")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let lines = observationLines()
        let old = Set(previousLines)
        let line = try XCTUnwrap(lines.first {
            !old.contains($0) && $0.contains("[background]") && $0.contains(expectedText)
        })
        let process = try processToken(in: line)
        XCTAssertNotEqual(process, previousProcess,
                          "The boundary callback must be persisted by a newly launched process")
        XCTAssertFalse(app.staticTexts[
            "p2.location.p2-location-regions.observation-error"].exists, app.debugDescription)
        return process
    }

    private func observationLines() -> [String] {
        let disclosure = app.buttons["受信記録（座標なし・最新64件）"]
        reveal(disclosure, direction: .up)
        if !app.staticTexts["p2.location.p2-location-regions.observations"].exists { tap(disclosure) }
        let observations = app.staticTexts["p2.location.p2-location-regions.observations"]
        XCTAssertTrue(observations.waitForExistence(timeout: 10), app.debugDescription)
        return observations.label.split(separator: "\n").map(String.init)
    }

    private func processToken(in line: String) throws -> String {
        String(try XCTUnwrap(line.split(separator: " ").first { $0.hasPrefix("起動") }))
    }

    private enum ScrollDirection { case up, down }
    private func reveal(_ element: XCUIElement, direction: ScrollDirection) {
        for _ in 0..<10 where !element.isHittable {
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            }
        }
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
        element.tap()
    }
}
