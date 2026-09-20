#if os(iOS)
import XCTest
import UIKit
import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2BluetoothScenesHostNativeTests: XCTestCase {
    func testActualWindowRootsReceiveOnlyTheirAddressedRouteAndDisconnect() async throws {
        XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad)
        let registry = AppSceneRouting.windows
        await eventually { !registry.connectedScenes.isEmpty }
        let first = try XCTUnwrap(registry.connectedScenes.first?.connection)
        let existing = Set(registry.connectedScenes.map { $0.connection.sessionID })
        let requester = MiniAppUIKitWindowSceneRequester()
        var failure: Error?
        requester.requestWindow(userActivity: nil) { failure = $0 }
        await eventually {
            failure != nil || registry.connectedScenes.contains { !existing.contains($0.connection.sessionID) }
        }
        XCTAssertNil(failure)
        let second = try XCTUnwrap(registry.connectedScenes.first {
            !existing.contains($0.connection.sessionID)
        }?.connection)
        let a = MiniAppID("p2-scene-a"), b = MiniAppID("p2-scene-b")
        XCTAssertEqual(registry.open(try route(a), in: first.sessionID, expected: first), .delivered(first))
        XCTAssertEqual(registry.open(try route(b), in: second.sessionID, expected: second), .delivered(second))
        await eventually {
            registry.snapshot(for: first.sessionID)?.selectedID == a &&
            registry.snapshot(for: second.sessionID)?.selectedID == b
        }
        XCTAssertTrue(requester.destroyWindow(sessionID: second.sessionID) { failure = $0 })
        await eventually { registry.snapshot(for: second.sessionID) == nil || failure != nil }
        XCTAssertNil(failure)
        XCTAssertNil(registry.snapshot(for: second.sessionID))
        XCTAssertEqual(registry.snapshot(for: first.sessionID)?.connection, first)
        XCTAssertEqual(registry.snapshot(for: first.sessionID)?.selectedID, a)
        XCTAssertEqual(registry.open(nil, in: second.sessionID, expected: second), .staleConnection(current: nil))
        _ = registry.open(nil, in: first.sessionID, expected: first)
    }

    func testDetachedBridgeDoesNotPublishItsDelayedConnection() async throws {
        let registry = MiniAppWindowSceneRegistry()
        let bridge = MiniAppWindowConnectionBridge(registry: registry)
        let session = MiniAppWindowSessionID("bridge-cancelled")
        bridge.connect(sessionID: session, phase: .active, selectedID: nil) { _ in XCTFail("Detached root received a route") }
        bridge.disconnect()
        // Let the queued connection operation observe its invalidated revision.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(bridge.connection)
        XCTAssertNil(registry.snapshot(for: session))
    }

    func testRestoreReleasesOnlyOwnedSceneResourcesBeforeFeatureStop() async throws {
        let registry = MiniAppWindowSceneRegistry(), log = WindowRestoreLog()
        let a = MiniAppID("window-restore-a"), b = MiniAppID("window-restore-b")
        let connection = await registry.connect(sessionID: .init("restore-window"),
            phase: .active, selectedID: b) { _ in }
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: connection) { await log.append("A scene") })
        XCTAssertTrue(registry.onDisconnect(owner: b, connection: connection) { await log.append("B scene") })
        let session = WindowRestoreSession(owner: a, registry: registry,
            inner: .init(stop: { await log.append("A stop") }, resume: { await log.append("A resume") }),
            canResume: { true })
        try await session.stop()
        XCTAssertTrue(registry.isSuspended(owner: a))
        XCTAssertFalse(registry.isSuspended(owner: b))
        XCTAssertEqual(registry.snapshot(for: connection.sessionID)?.selectedID, b)
        try await session.resume()
        XCTAssertFalse(registry.isSuspended(owner: a))
        let events = await log.events
        XCTAssertEqual(events, ["A scene", "A stop", "A resume"])

        await registry.suspendAndRelease(owner: a)
        let disabled = WindowRestoreSession(owner: a, registry: registry, inner: nil, canResume: { false })
        try await disabled.stop(); try await disabled.resume()
        XCTAssertTrue(registry.isSuspended(owner: a))
        _ = await registry.disconnect(connection)
    }

    private func route(_ id: MiniAppID) throws -> MiniAppRoute {
        try XCTUnwrap(MiniAppLink.resolveRoute(try XCTUnwrap(MiniAppLink.url(for: id)), registeredIDs: [id]))
    }

    func testFailedRestoreStopRecoversOnlyAnEnabledOwner() async throws {
        let registry = MiniAppWindowSceneRegistry(), log = WindowRestoreLog()
        let owner = MiniAppID("window-failed-restore")
        let session = WindowRestoreSession(owner: owner, registry: registry,
            inner: .init(stop: { throw WindowRestoreFailure.expected }, resume: {},
                recoverAfterFailedStop: { await log.append("recovered") }),
            canResume: { true })
        do {
            try await session.stop()
            XCTFail("Expected stop failure")
        } catch WindowRestoreFailure.expected {}
        XCTAssertTrue(registry.isSuspended(owner: owner))
        try await session.recover()
        XCTAssertFalse(registry.isSuspended(owner: owner))
        let events = await log.events
        XCTAssertEqual(events, ["recovered"])

        let failedRecovery = WindowRestoreSession(owner: owner, registry: registry,
            inner: .init(stop: {}, resume: {},
                recoverAfterFailedStop: { throw WindowRestoreFailure.expected }),
            canResume: { true })
        try await failedRecovery.stop()
        do {
            try await failedRecovery.recover()
            XCTFail("Expected recovery failure")
        } catch WindowRestoreFailure.expected {}
        XCTAssertTrue(registry.isSuspended(owner: owner))
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("OS window/root transition did not complete")
    }
}

private actor WindowRestoreLog {
    private(set) var events: [String] = []
    func append(_ value: String) { events.append(value) }
}
private enum WindowRestoreFailure: Error { case expected }
#endif
