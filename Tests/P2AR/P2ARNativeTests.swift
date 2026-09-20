#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import XCTest
import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2ARNativeTests: XCTestCase, @unchecked Sendable {
    func testProbeUsesNormalDefinitionLifetimePermissionAndPerRunFeatureDelegate() {
        let definition = P2ARProbe.definitions[0]
        XCTAssertEqual(definition.id, MiniAppID("p2-ar"))
        XCTAssertNotNil(definition.lifetime)
        XCTAssertNotNil(definition.onSceneActivityChange)
        XCTAssertEqual(definition.permissions.map(\.id), ["camera"])
        let run = P2ARRun(state: P2ARState())
        XCTAssertTrue(run.session.delegate === run.delegate)
    }

    func testSimulatorReportsUnsupportedAndDoesNotClaimTracking() async throws {
        XCTAssertFalse(ARWorldTrackingConfiguration.isSupported)
        let feature = P2ARFeature(
            id: MiniAppID("p2-ar-simulator"), coordinator: .init(),
            permissions: P2ARAllowedPermission()
        )
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: feature.id) { feature.owner.receive($0) }
        ])
        dispatcher.connect(phase: .active, selectedID: feature.id)
        let sceneID = try XCTUnwrap(dispatcher.connectionID)
        await feature.start(in: sceneID)
        XCTAssertTrue(feature.state.status.contains("unsupported"))
        XCTAssertEqual(feature.state.frameCount, 0)
        await feature.lifetime.stop()
    }

    func testConsentRevocationStopsOwnedOperationAndUpdatesStatus() async throws {
        let feature = P2ARFeature(
            id: MiniAppID("p2-ar-consent"), coordinator: .init(),
            permissions: P2ARAllowedPermission()
        )
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: feature.id) { feature.owner.receive($0) }
        ])
        dispatcher.connect(phase: .active, selectedID: feature.id)
        let sceneID = try XCTUnwrap(dispatcher.connectionID)
        try await feature.owner.start(
            .init(resources: [.camera]) { { _ in } }, sceneScope: .scene(sceneID)
        )
        XCTAssertEqual(feature.state.status, "AR実行中")

        try feature.definition.setConsent(.denied, permissionID: "camera", in: store)
        await eventually { feature.owner.state == .suspended(.featureStopped) }
        XCTAssertTrue(feature.state.status.contains("AR中断/停止"))
        await feature.lifetime.stop()
    }

    func testSameSceneCameraContenderRejectsThenSwitchesWithoutImplicitARRestart() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let calls = P2ARContenderCalls()
        let feature = P2ARFeature(
            id: MiniAppID("p2-ar-contender-test"), coordinator: coordinator,
            permissions: P2ARAllowedPermission(),
            contenderOperation: {
                MiniAppCaptureOperation(resources: [.camera]) {
                    calls.contenderStarts += 1
                    return { _ in calls.contenderStops += 1 }
                }
            }
        )
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: feature.id) { feature.definition.onSceneActivityChange?($0) }
        ])
        dispatcher.connect(phase: .active, selectedID: feature.id)
        let sceneID = try XCTUnwrap(dispatcher.connectionID)
        let arOperation = MiniAppCaptureOperation(resources: [.camera]) {
            calls.arStarts += 1
            return { _ in calls.arStops += 1 }
        }
        try await feature.owner.start(arOperation, sceneScope: .scene(sceneID))

        await feature.startContender(switching: .reject, in: sceneID)
        XCTAssertEqual(feature.owner.state, .running([.camera]))
        XCTAssertEqual(calls.contenderStarts, 0)

        await feature.startContender(switching: .stopCurrent, in: sceneID)
        XCTAssertEqual(feature.owner.state, .suspended(.switched(to: feature.contenderOwner.id)))
        XCTAssertEqual(feature.contenderOwner.state, .running([.camera]))
        XCTAssertEqual(calls.arStops, 1)
        XCTAssertEqual(calls.contenderStarts, 1)

        await feature.stopContender()
        XCTAssertEqual(feature.owner.state, .suspended(.switched(to: feature.contenderOwner.id)))
        XCTAssertEqual(calls.arStarts, 1, "Stopping B must not implicitly restart AR")
        XCTAssertEqual(calls.contenderStops, 1)
        try await feature.owner.start(arOperation, sceneScope: .scene(sceneID))
        XCTAssertEqual(feature.owner.state, .running([.camera]))
        XCTAssertEqual(calls.arStarts, 2)

        await feature.startContender(switching: .stopCurrent, in: sceneID)
        dispatcher.update(phase: .background, selectedID: feature.id)
        await eventually { feature.contenderOwner.state == .suspended(.background) }
        dispatcher.update(phase: .active, selectedID: feature.id)
        await feature.startContender(switching: .reject, in: sceneID)
        XCTAssertEqual(feature.contenderOwner.state, .running([.camera]))
        dispatcher.disconnect()
        await eventually { feature.contenderOwner.state == .suspended(.disconnected) }
        await feature.lifetime.stop()
    }

    func testArtificialObservationEventsCorrelateRunSequenceRestartAndFrame() {
        let state = P2ARState()
        for index in 0..<85 { state.append("artificial test event \(index)") }
        XCTAssertEqual(state.observationLines.count, 80)
        XCTAssertTrue(state.observationLines.first?.contains("artificial test event 5") == true)

        let run = UUID()
        state.activate(run: run)
        state.interruptionBegan(run: run, source: "artificial")
        state.interruptionEnded(run: run, source: "artificial")
        state.observeARState(.running([.camera]), run: run)
        state.receivedFrame(run: run, source: "artificial")

        let correlated = state.observationLines.filter { $0.contains("run=\(run.uuidString.suffix(8))") }
        XCTAssertTrue(correlated.contains { $0.contains("artificial interruption began") && $0.contains("seq=1") })
        XCTAssertTrue(correlated.contains { $0.contains("artificial interruption ended") && $0.contains("seq=1") })
        XCTAssertTrue(correlated.contains { $0.contains("AR restart completed") && $0.contains("seq=1") })
        XCTAssertTrue(correlated.contains { $0.contains("first frame after interruption") && $0.contains("seq=1") })

        state.interruptionBegan(run: run, source: "artificial-second")
        state.interruptionEnded(run: run, source: "artificial-second")
        state.observeARState(.running([.camera]), run: run)
        state.receivedFrame(run: run, source: "artificial-second")
        XCTAssertTrue(state.observationLines.contains {
            $0.contains("artificial-second interruption began") && $0.contains("seq=2")
        })
        XCTAssertTrue(state.observationLines.contains {
            $0.contains("first frame after interruption") && $0.contains("seq=2")
        })
    }

    func testRepeatedStartWhileStartingKeepsOriginalRunAndDelegate() async throws {
        let gate = P2ARStartGate()
        let feature = P2ARFeature(
            id: MiniAppID("p2-ar-repeat-start"), coordinator: .init(),
            permissions: P2ARAllowedPermission(),
            runFactory: { state in
                P2ARRun(state: state, operation: MiniAppCaptureOperation(resources: [.camera]) {
                    await gate.wait()
                    return { _ in }
                })
            }
        )
        let store = try allowedStore(owner: feature.id)
        feature.attachConsent(store)
        try await feature.lifetime.start()
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: feature.id) { feature.definition.onSceneActivityChange?($0) }
        ])
        dispatcher.connect(phase: .active, selectedID: feature.id)
        let sceneID = try XCTUnwrap(dispatcher.connectionID)

        let first = Task { await feature.start(in: sceneID) }
        await eventually { feature.owner.state == .starting && feature.activeRun != nil }
        let originalRun = try XCTUnwrap(feature.activeRun)
        weak var originalDelegate: P2ARFeatureDelegate? = originalRun.delegate
        await feature.start(in: sceneID)

        XCTAssertTrue(feature.activeRun === originalRun)
        XCTAssertTrue(feature.activeRun?.delegate === originalDelegate)
        XCTAssertTrue(feature.state.observationLines.contains { $0.contains("duplicate AR start ignored") })
        await gate.release()
        await first.value
        XCTAssertEqual(feature.owner.state, .running([.camera]))
        XCTAssertTrue(feature.activeRun === originalRun)
        XCTAssertNotNil(originalDelegate)
        await feature.start(in: sceneID)
        XCTAssertTrue(feature.activeRun === originalRun)
        XCTAssertTrue(feature.activeRun?.delegate === originalDelegate)
        await feature.stop()
        await feature.lifetime.stop()
    }

    func testUnmatchedAndOldRunArtificialCallbacksCannotReportRecovery() async {
        let state = P2ARState()
        let oldRun = UUID(), currentRun = UUID()
        let oldDelegate = P2ARFeatureDelegate(run: oldRun, state: state)
        state.activate(run: currentRun)

        oldDelegate.recordInterruptionBegan(source: "artificial-old")
        oldDelegate.recordInterruptionEnded(source: "artificial-old")
        oldDelegate.recordFrame(source: "artificial-old")
        await eventually { state.observationLines.count >= 4 }
        state.interruptionEnded(run: currentRun, source: "artificial-no-begin")
        state.observeARState(.running([.camera]), run: currentRun)
        state.receivedFrame(run: oldRun, source: "artificial-stale")

        XCTAssertFalse(state.observationLines.contains { $0.contains("AR restart completed") })
        XCTAssertFalse(state.observationLines.contains { $0.contains("first frame after interruption") })
        XCTAssertTrue(state.observationLines.contains { $0.contains("unmatched artificial-no-begin interruption ended ignored") })
        XCTAssertTrue(state.observationLines.contains { $0.contains("unattributed artificial-old interruption began ignored") })
        XCTAssertTrue(state.observationLines.contains { $0.contains("unattributed artificial-stale frame ignored") })
    }

    func testStoppedRunLateFrameCannotCompleteInterruption() {
        let state = P2ARState(), run = UUID()
        state.activate(run: run)
        state.interruptionBegan(run: run, source: "artificial")
        state.interruptionEnded(run: run, source: "artificial")
        state.deactivate(run: run, reason: "test stop")
        state.observeARState(.running([.camera]), run: run)
        state.receivedFrame(run: run, source: "artificial-late")

        XCTAssertFalse(state.observationLines.contains { $0.contains("AR restart completed") })
        XCTAssertFalse(state.observationLines.contains { $0.contains("first frame after interruption") })
        XCTAssertTrue(state.observationLines.contains { $0.contains("unattributed artificial-late frame ignored") })
    }

    private func allowedStore(owner: MiniAppID) throws -> MiniAppConsentStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "P2AR.\(UUID().uuidString)"))
        let store = MiniAppConsentStore(defaults: defaults)
        store.setConsent(.allowed, for: owner, permissionID: "camera")
        return store
    }
}

@MainActor
private final class P2ARAllowedPermission: MiniAppCapturePermissionClient {
    func request(_ resource: MiniAppCaptureResource) async -> Bool { true }
}

@MainActor
private final class P2ARContenderCalls {
    var arStarts = 0
    var arStops = 0
    var contenderStarts = 0
    var contenderStops = 0
}

private actor P2ARStartGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<100 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("condition was not reached")
}
#endif
