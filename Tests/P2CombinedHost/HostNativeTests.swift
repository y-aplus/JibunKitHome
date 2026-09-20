#if os(iOS)
import XCTest
import UIKit
import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2CombinedHostNativeTests: XCTestCase {
    func testCombinedRegistryAndActualColdLaunchKeepAllFamiliesAvailable() {
        // This is the app-hosted process after UIApplicationDelegate launch,
        // not a second call to native background task registration.
        let expected: Set<String> = [
            "p2-background-a", "p2-background-b",
            "p2-location-tracker", "p2-location-regions",
            "p2-identity-a", "p2-identity-b",
            "p2-push-alpha", "p2-push-beta",
            "p2-bluetooth-sensor", "p2-bluetooth-accessory",
            "p2-scene-a", "p2-scene-b", "p2-ar",
            "p2-appearance-a", "p2-appearance-b",
            "incoming-a", "incoming-b", "counter", "reminder",
        ]
        let ids = MiniAppRegistry.all.map { $0.id.rawValue }
        XCTAssertEqual(Set(ids), expected)
        XCTAssertEqual(ids.count, expected.count)
        XCTAssertTrue(MiniAppRegistry.launchState.errors.isEmpty,
                      "Cold-launch owner failures: \(MiniAppRegistry.launchState.errors)")
        XCTAssertNil(MiniAppRegistry.launchState.hostError)
        XCTAssertNil(MiniAppRegistry.incomingCatalogError)
        XCTAssertFalse(ids.contains("p2-action-alpha"), "Test-only Action destination leaked into app registry")
        XCTAssertNotNil(UIApplication.shared.delegate)
    }
}
#endif
