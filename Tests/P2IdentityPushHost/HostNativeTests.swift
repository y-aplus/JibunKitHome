#if os(iOS)
import XCTest
import UIKit
import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2IdentityPushHostNativeTests: XCTestCase {
    func testActualDelegateForwardsTokenAndRejectsUnownedPayloadOnce() async throws {
        let delegate = NotificationAppDelegate()
        let token = Data(UUID().uuidString.utf8)
        delegate.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: token)
        await eventually { MiniAppRemotePushCoordinator.shared.appToken == token }
        var completions: [UIBackgroundFetchResult] = []
        delegate.application(UIApplication.shared, didReceiveRemoteNotification: ["aps": ["content-available": 1]]) {
            completions.append($0)
        }
        await eventually { completions.count == 1 }
        XCTAssertEqual(completions, [.noData])
    }

    func testActualDelegateRoutesToEnabledFeatureAndRejectsDisabledOwner() async throws {
        // Real management unregister waits for native Spotlight acknowledgement.
        // Run35251510227 completed that path in139s; do not skip/prewarm it.
        executionTimeAllowance = 240
        let delegate = NotificationAppDelegate()
        let a = P2PushProbe.alpha, b = P2PushProbe.beta
        try await MiniAppRegistry.management.enable(a.id)
        try await MiniAppRegistry.management.enable(b.id)
        try await a.lifetime.start(); try await b.lifetime.start()
        let aBefore = a.deliveries, bBefore = b.deliveries
        let payload: [AnyHashable: Any] = [MiniAppNotificationRoute.miniAppIDUserInfoKey: a.id.rawValue,
                                         "aps": ["content-available": 1]]
        var completions: [UIBackgroundFetchResult] = []
        delegate.application(UIApplication.shared, didReceiveRemoteNotification: payload) { completions.append($0) }
        await eventually { completions.count == 1 }
        XCTAssertEqual(completions, [.newData])
        XCTAssertEqual(a.deliveries, aBefore + 1)
        XCTAssertEqual(b.deliveries, bBefore)
        try await MiniAppRegistry.management.disable(a.id)
        delegate.application(UIApplication.shared, didReceiveRemoteNotification: payload) { completions.append($0) }
        await eventually { completions.count == 2 }
        XCTAssertEqual(completions, [.newData, .noData])
        XCTAssertEqual(a.deliveries, aBefore + 1)
        XCTAssertEqual(b.deliveries, bBefore)
        XCTAssertEqual(b.lifetime.state, .running)
        try await MiniAppRegistry.management.enable(a.id)
        await a.lifetime.stop(); await b.lifetime.stop()
    }

    func testActualDelegateStartsDormantOwnerWithoutOpeningItsScreen() async throws {
        let delegate = NotificationAppDelegate()
        let a = P2PushProbe.alpha, b = P2PushProbe.beta
        try await MiniAppRegistry.management.enable(a.id)
        try await MiniAppRegistry.management.enable(b.id)
        await a.lifetime.stop()
        try await b.lifetime.start()
        // Host launch publishes the owner synchronously, before any Feature UI exists.
        try a.definition.onHostLaunch?()
        let aBefore = a.deliveries, bBefore = b.deliveries
        var completions: [UIBackgroundFetchResult] = []
        delegate.application(UIApplication.shared, didReceiveRemoteNotification: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: a.id.rawValue,
            "aps": ["content-available": 1]
        ]) { completions.append($0) }
        await eventually { completions.count == 1 }
        XCTAssertEqual(completions, [.newData])
        XCTAssertEqual(a.lifetime.state, .running)
        XCTAssertEqual(a.deliveries, aBefore + 1)
        XCTAssertEqual(b.deliveries, bBefore)
        XCTAssertEqual(b.lifetime.state, .running)
        await a.lifetime.stop(); await b.lifetime.stop()
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Host delegate result was not delivered")
    }
}
#endif
