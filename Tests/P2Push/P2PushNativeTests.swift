#if os(iOS)
import XCTest
import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2PushNativeTests: XCTestCase {
    func testProbePublishesTwoOrdinaryDefinitionsWithIndependentLifetimeAndUnregister() {
        let definitions = P2PushProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-push-alpha"), MiniAppID("p2-push-beta")])
        XCTAssertTrue(definitions.allSatisfy { $0.lifetime != nil && $0.onUnregister != nil && $0.onHostLaunch != nil })
    }

    func testTwoFeaturesUseSameLocalAccountButSeparateServerIdentityAndOwnerDelivery() async throws {
        let definitions = P2PushProbe.definitions
        try await definitions[0].lifetime?.start()
        try await definitions[1].lifetime?.start()
        P2PushProbe.coordinator.didRegisterForRemoteNotifications(deviceToken: Data([0x12, 0x34]))
        let alphaBefore = P2PushProbe.alpha.deliveries
        let betaBefore = P2PushProbe.beta.deliveries
        let result = await P2PushProbe.coordinator.deliver(userInfo: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: P2PushProbe.alpha.id.rawValue,
            MiniAppNotificationRoute.destinationUserInfoKey: "message-1"
        ])
        XCTAssertEqual(result, .newData)
        XCTAssertEqual(P2PushProbe.alpha.deliveries, alphaBefore + 1)
        XCTAssertEqual(P2PushProbe.beta.deliveries, betaBefore)
        await definitions[0].lifetime?.stop()
        XCTAssertEqual(definitions[1].lifetime?.state, .running)
        await definitions[1].lifetime?.stop()
    }

    func testOwnerUnregisterLeavesOtherFeatureRegistered() async throws {
        let definitions = P2PushProbe.definitions
        try await definitions[0].lifetime?.start(); try await definitions[1].lifetime?.start()
        try await definitions[0].onUnregister?()
        let a = await P2PushProbe.coordinator.deliver(userInfo: [MiniAppNotificationRoute.miniAppIDUserInfoKey: P2PushProbe.alpha.id.rawValue])
        let b = await P2PushProbe.coordinator.deliver(userInfo: [MiniAppNotificationRoute.miniAppIDUserInfoKey: P2PushProbe.beta.id.rawValue])
        XCTAssertEqual(a, .noData); XCTAssertEqual(b, .newData)
        await definitions[0].lifetime?.stop(); await definitions[1].lifetime?.stop()
    }
}
#endif
