#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppARSessionAdapterTests: XCTestCase {
    func testAdapterKeepsFeatureDelegateAndRejectsUnsupportedBeforeRunning() async throws {
        let session = ARSession()
        let delegate = FeatureARDelegate()
        session.delegate = delegate
        let bridge = MiniAppARSessionEventBridge()
        let adapter = MiniAppARSessionAdapter(
            session: session,
            configuration: ARWorldTrackingConfiguration(),
            runOptions: [.resetTracking],
            restartOptions: [],
            eventBridge: bridge,
            isSupported: { false }
        )
        XCTAssertTrue(session.delegate === delegate)

        let permissions = ARPermissions()
        let owner = MiniAppCaptureOwner(
            id: MiniAppID("ar-unsupported"), coordinator: .init(),
            permissions: permissions, consent: { _ in true }
        )
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime)
        let sceneID = UUID()
        owner.receive(.init(featureID: owner.id, sceneID: sceneID, phase: .active, isSelected: true))
        await XCTAssertThrowsErrorAsync(try await owner.start(
            try adapter.operation(), sceneScope: .scene(sceneID)
        )) {
            XCTAssertEqual($0 as? MiniAppCaptureFailure, .unsupported)
        }
        XCTAssertTrue(permissions.requested.isEmpty)
        XCTAssertNil(session.currentFrame)
    }

    func testFeatureForwardedEventsUseOneGenerationAndFinishOnEnd() async throws {
        let bridge = MiniAppARSessionEventBridge()
        let (events, forwarder) = try bridge.begin()
        var iterator = events.stream.makeAsyncIterator()
        forwarder.interruptionBegan(reason: "camera unavailable")
        let interrupted = await iterator.next()
        forwarder.interruptionEnded()
        let resumed = await iterator.next()
        forwarder.runtimeFailed(reason: "reset", canRestart: true)
        let failed = await iterator.next()
        bridge.end(generation: events.generation)
        let ended = await iterator.next()

        XCTAssertEqual(interrupted, .interrupted(generation: events.generation, reason: "camera unavailable"))
        XCTAssertEqual(resumed, .interruptionEnded(generation: events.generation))
        XCTAssertEqual(failed, .runtimeFailed(generation: events.generation, reason: "reset", canRestart: true))
        XCTAssertNil(ended)
    }

    func testDelayedCallbackAndRetainedOldForwarderCannotRelabelIntoNewRun() async throws {
        let bridge = MiniAppARSessionEventBridge()
        let (oldEvents, oldForwarder) = try bridge.begin()
        bridge.interruptionBegan(reason: "queued-old-callback")
        bridge.end(generation: oldEvents.generation)
        let (newEvents, newForwarder) = try bridge.begin()
        var iterator = newEvents.stream.makeAsyncIterator()
        oldForwarder.interruptionBegan(reason: "retained-old-token")
        newForwarder.interruptionBegan(reason: "current")

        let delivered = await iterator.next()
        XCTAssertEqual(delivered, .interrupted(generation: newEvents.generation, reason: "current"))
        XCTAssertNotEqual(oldForwarder.generation, newForwarder.generation)
        bridge.end(generation: newEvents.generation)
    }

    func testStartedOperationStronglyKeepsCleanupAfterAdapterRelease() async throws {
        let session = ARSession()
        let bridge = MiniAppARSessionEventBridge()
        let calls = ARCallCounts()
        var adapter: MiniAppARSessionAdapter? = MiniAppARSessionAdapter(
            session: session,
            configuration: ARWorldTrackingConfiguration(),
            eventBridge: bridge,
            isSupported: { true },
            runSession: { _, _, _ in calls.runs += 1 },
            pauseSession: { _ in calls.pauses += 1 }
        )
        let operation = try XCTUnwrap(adapter).operation()
        let owner = MiniAppCaptureOwner(
            id: MiniAppID("ar-cleanup"), coordinator: .init(),
            permissions: ARPermissions(), consent: { _ in true }
        )
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime)
        let sceneID = UUID()
        owner.receive(.init(featureID: owner.id, sceneID: sceneID, phase: .active, isSelected: true))
        try await owner.start(operation, sceneScope: .scene(sceneID))
        adapter = nil
        await owner.stop()

        XCTAssertEqual(calls.runs, 1)
        XCTAssertEqual(calls.pauses, 1)
        let (next, _) = try bridge.begin()
        bridge.end(generation: next.generation)
    }
}

private final class FeatureARDelegate: NSObject, ARSessionDelegate {}

@MainActor
private final class ARPermissions: MiniAppCapturePermissionClient {
    private(set) var requested: [MiniAppCaptureResource] = []
    func request(_ resource: MiniAppCaptureResource) async -> Bool {
        requested.append(resource)
        return true
    }
}

@MainActor
private final class ARCallCounts {
    var runs = 0
    var pauses = 0
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do { _ = try await expression(); XCTFail("expected error") }
    catch { handler(error) }
}
#endif
