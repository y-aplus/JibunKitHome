import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppCaptureOwnerTests: XCTestCase {
    func testCameraConflictRejectsWithoutStoppingFirstOwnerThenExplicitSwitchJoinsStop() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let permissions = CapturePermissions()
        let a = MiniAppCaptureOwner(id: MiniAppID("capture-a"), coordinator: coordinator, permissions: permissions, consent: allow)
        let b = MiniAppCaptureOwner(id: MiniAppID("capture-b"), coordinator: coordinator, permissions: permissions, consent: allow)
        let runtimeA = MiniAppRuntime(), runtimeB = MiniAppRuntime()
        try a.connect(to: runtimeA); try b.connect(to: runtimeB)
        a.receive(active("capture-a")); b.receive(active("capture-b"))
        let events = CaptureEvents()
        try await a.start(operation(events: events, label: "a"))

        await XCTAssertThrowsErrorAsync(try await b.start(operation(events: events, label: "b"))) {
            XCTAssertEqual($0 as? MiniAppCaptureFailure, .cameraInUse(by: MiniAppID("capture-a")))
        }
        XCTAssertEqual(a.state, .running([.camera]))
        XCTAssertEqual(events.values, ["start-a"])

        try await b.start(operation(events: events, label: "b"), switching: .stopCurrent)
        XCTAssertEqual(events.values, ["start-a", "stop-a-switched", "start-b"])
        XCTAssertEqual(coordinator.currentCameraOwner, MiniAppID("capture-b"))
        XCTAssertEqual(a.state, .suspended(.switched(to: MiniAppID("capture-b"))))
        XCTAssertEqual(b.state, .running([.camera]))
    }

    func testMicrophoneRequiresHookAndReleasesAudioAfterNative() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let permissions = CapturePermissions()
        let owner = MiniAppCaptureOwner(id: MiniAppID("video"), coordinator: coordinator, permissions: permissions, consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("video"))
        let events = CaptureEvents()
        let missing = MiniAppCaptureOperation(resources: [.camera, .microphone]) { return { _ in } }
        await XCTAssertThrowsErrorAsync(try await owner.start(missing)) {
            XCTAssertEqual($0 as? MiniAppCaptureFailure, .missingAudioHook)
        }
        XCTAssertNil(coordinator.currentCameraOwner)

        let operation = MiniAppCaptureOperation(
            resources: [.camera, .microphone],
            acquireAudio: {
                events.append("audio-acquire")
                return { events.append("audio-release") }
            },
            startNative: {
                events.append("native-start")
                return { _ in events.append("native-stop") }
            }
        )
        try await owner.start(operation)
        await owner.stop()
        XCTAssertEqual(events.values, ["audio-acquire", "native-start", "native-stop", "audio-release"])
    }

    func testDelayedExternalReleaseCannotStopNextOperation() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("generation"), coordinator: coordinator,
            permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("generation"))
        let events = CaptureEvents()
        try await owner.start(operation(events: events, label: "old"))
        let old = try XCTUnwrap(owner.operationGeneration)
        await owner.stop()
        try await owner.start(operation(events: events, label: "new"))
        await owner.suspend(.interrupted("late audio release"), ifGeneration: old)
        XCTAssertEqual(owner.state, .running([.camera]))
        XCTAssertEqual(coordinator.currentCameraOwner, owner.id)
        XCTAssertEqual(events.values, ["start-old", "stop-old-other", "start-new"])
        await owner.stop()
    }

    func testCameraOnlyNeverRequestsMicrophone() async throws {
        let permissions = CapturePermissions()
        let owner = MiniAppCaptureOwner(id: MiniAppID("still"), coordinator: .init(), permissions: permissions, consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("still"))
        try await owner.start(operation(events: CaptureEvents(), label: "still"))
        XCTAssertEqual(permissions.requestedResources, [.camera])
    }

    func testPresentationOrNativeStartFailureReleasesAudioAndCameraForOtherOwner() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let permissions = CapturePermissions()
        let a = MiniAppCaptureOwner(id: MiniAppID("failed"), coordinator: coordinator, permissions: permissions, consent: allow)
        let b = MiniAppCaptureOwner(id: MiniAppID("next"), coordinator: coordinator, permissions: permissions, consent: allow)
        let runtimeA = MiniAppRuntime(), runtimeB = MiniAppRuntime()
        try a.connect(to: runtimeA); try b.connect(to: runtimeB)
        a.receive(active("failed")); b.receive(active("next"))
        let events = CaptureEvents()
        let failing = MiniAppCaptureOperation(
            resources: [.camera, .microphone],
            acquireAudio: { events.append("audio-acquire"); return { events.append("audio-release") } },
            startNative: { throw MiniAppCaptureFailure.native("presentation") }
        )
        await XCTAssertThrowsErrorAsync(try await a.start(failing)) { _ in }
        XCTAssertEqual(events.values, ["audio-acquire", "audio-release"])
        XCTAssertNil(coordinator.currentCameraOwner)
        try await b.start(operation(events: events, label: "next"))
        XCTAssertEqual(coordinator.currentCameraOwner, MiniAppID("next"))
    }

    func testStopDuringPermissionRequestRejectsLateCallbackAndReleasesNothingElse() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let permissions = CapturePermissions(blocked: true)
        let owner = MiniAppCaptureOwner(id: MiniAppID("late"), coordinator: coordinator, permissions: permissions, consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("late"))
        let events = CaptureEvents()
        let starting = Task { @MainActor in try await owner.start(operation(events: events, label: "late")) }
        await permissions.waitUntilRequested()
        await owner.stop()
        permissions.resolve(true)
        await XCTAssertThrowsErrorAsync(try await starting.value) {
            XCTAssertTrue($0 is MiniAppCaptureFailure || $0 is CancellationError)
        }
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertNil(coordinator.currentCameraOwner)
    }

    func testCancelledStartRejectsLatePermissionAndAllowsRetry() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let permissions = CapturePermissions(blocked: true)
        let owner = MiniAppCaptureOwner(id: MiniAppID("cancel"), coordinator: coordinator, permissions: permissions, consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("cancel"))
        let first = Task { @MainActor in try await owner.start(operation(events: CaptureEvents(), label: "first")) }
        await permissions.waitUntilRequested()
        first.cancel()
        permissions.resolve(true)
        await XCTAssertThrowsErrorAsync(try await first.value) { _ in }
        let events = CaptureEvents()
        try await owner.start(operation(events: events, label: "retry"))
        XCTAssertEqual(events.values, ["start-retry"])
    }

    func testStopDuringNativeStartStopsLateProducerAndDoesNotBecomeRunning() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("slow"), coordinator: coordinator,
                                        permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("slow"))
        let gate = NativeStartGate()
        let events = CaptureEvents()
        let operation = MiniAppCaptureOperation(resources: [.camera]) {
            await gate.wait()
            events.append("start-returned")
            return { _ in events.append("late-native-stop") }
        }
        let starting = Task { @MainActor in try await owner.start(operation) }
        await gate.waitUntilEntered()
        let stopping = Task { @MainActor in await owner.stop(); events.append("stop-returned") }
        await eventually { owner.state == .stopping(.user) }
        XCTAssertEqual(coordinator.currentCameraOwner, MiniAppID("slow"))
        XCTAssertFalse(events.values.contains("stop-returned"))
        gate.open()
        await stopping.value
        await XCTAssertThrowsErrorAsync(try await starting.value) { _ in }
        XCTAssertEqual(events.values, ["start-returned", "late-native-stop", "stop-returned"])
        XCTAssertNotEqual(owner.state, .running([.camera]))
        XCTAssertNil(coordinator.currentCameraOwner)
    }

    func testSceneAggregationKeepsCaptureUntilLastActiveSelectedSceneEnds() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("scenes"), coordinator: coordinator, permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime)
        let first = UUID(), second = UUID()
        owner.receive(activity("scenes", first, .active, true))
        owner.receive(activity("scenes", second, .active, true))
        let events = CaptureEvents()
        try await owner.start(operation(events: events, label: "scene"))
        owner.receive(activity("scenes", first, .background, true))
        await Task.yield()
        XCTAssertEqual(owner.state, .running([.camera]))
        owner.receive(activity("scenes", second, .inactive, true))
        await eventually { owner.state == .suspended(.sceneInactive) }
        XCTAssertEqual(events.values, ["start-scene", "stop-scene-sceneInactive"])
    }

    func testExplicitSceneScopeIgnoresOtherWindowAndStopsWhenOriginLeaves() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("scene-bound"), coordinator: coordinator,
                                        permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime)
        let origin = UUID(), other = UUID()
        owner.receive(activity("scene-bound", origin, .active, true))
        owner.receive(activity("scene-bound", other, .active, true))
        let events = CaptureEvents()
        try await owner.start(operation(events: events, label: "ar"), sceneScope: .scene(origin))

        owner.receive(activity("scene-bound", other, .background, true))
        await Task.yield()
        XCTAssertEqual(owner.state, .running([.camera]))
        owner.receive(activity("scene-bound", origin, .inactive, true))
        await eventually { owner.state == .suspended(.sceneInactive) }
        XCTAssertEqual(events.values, ["start-ar", "stop-ar-sceneInactive"])
        XCTAssertNil(coordinator.currentCameraOwner)
    }

    func testExplicitSceneLeavingDuringPermissionRequestRejectsLateGrant() async throws {
        let permissions = CapturePermissions(blocked: true)
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("scene-permission"), coordinator: coordinator,
                                        permissions: permissions, consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime)
        let origin = UUID(), other = UUID()
        owner.receive(activity("scene-permission", origin, .active, true))
        owner.receive(activity("scene-permission", other, .active, true))
        let events = CaptureEvents()
        let starting = Task { @MainActor in
            try await owner.start(operation(events: events, label: "ar"), sceneScope: .scene(origin))
        }
        await permissions.waitUntilRequested()
        owner.receive(activity("scene-permission", origin, .background, true))
        await eventually { owner.state == .stopping(.background) || owner.state == .suspended(.background) }
        permissions.resolve(true)
        await XCTAssertThrowsErrorAsync(try await starting.value) { _ in }
        await eventually { owner.state == .suspended(.background) }
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertNil(coordinator.currentCameraOwner)
    }

    func testExplicitSceneMustBeActiveSelectedButOtherWindowMayShowSameFeature() async throws {
        let owner = MiniAppCaptureOwner(id: MiniAppID("scene-selection"), coordinator: .init(),
                                        permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime)
        let origin = UUID(), other = UUID()
        owner.receive(activity("scene-selection", origin, .inactive, true))
        owner.receive(activity("scene-selection", other, .active, true))
        await XCTAssertThrowsErrorAsync(try await owner.start(
            operation(events: .init(), label: "ar"), sceneScope: .scene(origin)
        )) {
            XCTAssertEqual(
                $0 as? MiniAppCaptureFailure,
                .unavailable("capture scene is not active and selected")
            )
        }
        try await owner.start(operation(events: .init(), label: "ar"), sceneScope: .scene(other))
        XCTAssertEqual(owner.state, .running([.camera]))
        await owner.stop()
    }

    func testRuntimeShutdownOnlyStopsItsOwnerAndPreservesOtherGeneration() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let permissions = CapturePermissions()
        let a = MiniAppCaptureOwner(id: MiniAppID("a"), coordinator: coordinator, permissions: permissions, consent: allow)
        let b = MiniAppCaptureOwner(id: MiniAppID("b"), coordinator: coordinator, permissions: permissions, consent: allow)
        let runtimeA = MiniAppRuntime(), runtimeB = MiniAppRuntime()
        try a.connect(to: runtimeA); try b.connect(to: runtimeB)
        a.receive(active("a")); b.receive(active("b"))
        let bState = CaptureEvents(); bState.append("non-initial")
        try await a.start(operation(events: CaptureEvents(), label: "a"))
        await runtimeA.shutdown()
        XCTAssertEqual(a.state, .stopped)
        XCTAssertFalse(runtimeB.isClosed)
        XCTAssertEqual(bState.values, ["non-initial"])
        try await b.start(operation(events: bState, label: "b"))
        XCTAssertEqual(b.state, .running([.camera]))
    }

    func testUserStopIsNotUndoneByInterruptionEnd() async throws {
        let owner = MiniAppCaptureOwner(id: MiniAppID("intent"), coordinator: .init(), permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("intent"))
        try await owner.start(operation(events: CaptureEvents(), label: "intent"))
        await owner.stop()
        let restarted = CaptureEvents()
        try await owner.handleInterruptionEnded { restarted.append("restart") }
        XCTAssertTrue(restarted.values.isEmpty)
    }

    func testNativeInterruptionResumesSameGenerationButNeverAfterUserStop() async throws {
        let owner = MiniAppCaptureOwner(id: MiniAppID("events"), coordinator: .init(),
                                        permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("events"))
        let pair = AsyncStream<MiniAppCaptureNativeEvent>.makeStream()
        let generation = UUID()
        let events = CaptureEvents()
        let operation = MiniAppCaptureOperation(
            resources: [.camera], nativeEvents: {
                MiniAppCaptureNativeEvents(generation: generation, stream: pair.stream)
            },
            restartNative: { events.append("restart") },
            startNative: { { _ in events.append("stop") } }
        )
        try await owner.start(operation)
        pair.continuation.yield(.interrupted(generation: generation, reason: "phone"))
        await eventually { owner.state == .suspended(.interrupted("phone")) }
        pair.continuation.yield(.interruptionEnded(generation: generation))
        await eventually { owner.state == .running([.camera]) }
        XCTAssertEqual(events.values, ["restart"])
        await owner.stop()
        pair.continuation.yield(.interruptionEnded(generation: generation))
        await Task.yield()
        XCTAssertEqual(events.values, ["restart", "stop"])
        XCTAssertEqual(owner.state, .idle)
    }

    func testSceneBoundInterruptionRestartFailureReleasesCameraAndPreservesOtherOwner() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let a = MiniAppCaptureOwner(id: MiniAppID("ar-restart"), coordinator: coordinator,
                                    permissions: CapturePermissions(), consent: allow)
        let b = MiniAppCaptureOwner(id: MiniAppID("ar-other"), coordinator: coordinator,
                                    permissions: CapturePermissions(), consent: allow)
        let runtimeA = MiniAppRuntime(), runtimeB = MiniAppRuntime()
        try a.connect(to: runtimeA); try b.connect(to: runtimeB)
        let sceneID = UUID()
        a.receive(activity("ar-restart", sceneID, .active, true))
        b.receive(active("ar-other"))
        let pair = AsyncStream<MiniAppCaptureNativeEvent>.makeStream()
        let generation = UUID()
        let otherState = CaptureEvents(); otherState.append("kept")
        try await a.start(.init(
            resources: [.camera],
            nativeEvents: { .init(generation: generation, stream: pair.stream) },
            restartNative: { throw MiniAppCaptureFailure.native("AR restart failed") },
            startNative: { { _ in } }
        ), sceneScope: .scene(sceneID))
        pair.continuation.yield(.interrupted(generation: generation, reason: "camera"))
        await eventually { a.state == .suspended(.interrupted("camera")) }
        pair.continuation.yield(.interruptionEnded(generation: generation))
        await eventually {
            if case .failed(.runtime(let reason)) = a.state { return reason.contains("AR restart failed") }
            return false
        }
        XCTAssertFalse(runtimeB.isClosed)
        XCTAssertEqual(otherState.values, ["kept"])
        XCTAssertNil(coordinator.currentCameraOwner)
        try await b.start(operation(events: otherState, label: "b"))
        XCTAssertEqual(coordinator.currentCameraOwner, b.id)
    }

    func testMovieStyleInterruptionStopsInsteadOfRestarting() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("movie-interruption"), coordinator: coordinator,
                                        permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("movie-interruption"))
        let pair = AsyncStream<MiniAppCaptureNativeEvent>.makeStream()
        let generation = UUID()
        let events = CaptureEvents()
        try await owner.start(.init(
            resources: [.camera, .microphone],
            acquireAudio: { { events.append("audio-release") } },
            nativeEvents: { .init(generation: generation, stream: pair.stream) },
            restartNative: { events.append("unexpected-restart") },
            stopsOnInterruption: true,
            startNative: { { _ in events.append("movie-stop") } }
        ))
        pair.continuation.yield(.interrupted(generation: generation, reason: "audio-lost"))
        await eventually { coordinator.currentCameraOwner == nil }
        XCTAssertEqual(events.values, ["movie-stop", "audio-release"])
        XCTAssertEqual(owner.state, .suspended(.interrupted("audio-lost")))
        pair.continuation.yield(.interruptionEnded(generation: generation))
        await Task.yield()
        XCTAssertEqual(events.values, ["movie-stop", "audio-release"])
    }

    func testRuntimeFailureStopsOnlyCurrentOwnerAndRejectsOldGenerationEvent() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("runtime"), coordinator: coordinator,
                                        permissions: CapturePermissions(), consent: allow)
        let other = MiniAppCaptureOwner(id: MiniAppID("other"), coordinator: coordinator,
                                        permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(), otherRuntime = MiniAppRuntime()
        try owner.connect(to: runtime); try other.connect(to: otherRuntime)
        owner.receive(active("runtime")); other.receive(active("other"))
        let pair = AsyncStream<MiniAppCaptureNativeEvent>.makeStream()
        let generation = UUID()
        try await owner.start(.init(resources: [.camera], nativeEvents: {
            MiniAppCaptureNativeEvents(generation: generation, stream: pair.stream)
        },
                                    startNative: { { _ in } }))
        pair.continuation.yield(.interrupted(generation: UUID(), reason: "old-first"))
        await Task.yield()
        XCTAssertEqual(owner.state, .running([.camera]))
        pair.continuation.yield(.interrupted(generation: generation, reason: "pressure"))
        await eventually { owner.state == .suspended(.interrupted("pressure")) }
        pair.continuation.yield(.runtimeFailed(generation: UUID(), reason: "old", canRestart: false))
        await Task.yield()
        XCTAssertEqual(owner.state, .suspended(.interrupted("pressure")))
        pair.continuation.yield(.runtimeFailed(generation: generation, reason: "reset", canRestart: false))
        await eventually { owner.state == .failed(.runtime("reset")) }
        XCTAssertFalse(otherRuntime.isClosed)
        XCTAssertNil(coordinator.currentCameraOwner)
    }

    func testStopJoinsInFlightRestartBeforeCameraSwitch() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let permissions = CapturePermissions()
        let a = MiniAppCaptureOwner(id: MiniAppID("restart-a"), coordinator: coordinator,
                                    permissions: permissions, consent: allow)
        let b = MiniAppCaptureOwner(id: MiniAppID("restart-b"), coordinator: coordinator,
                                    permissions: permissions, consent: allow)
        let runtimeA = MiniAppRuntime(), runtimeB = MiniAppRuntime()
        try a.connect(to: runtimeA); try b.connect(to: runtimeB)
        a.receive(active("restart-a")); b.receive(active("restart-b"))
        let pair = AsyncStream<MiniAppCaptureNativeEvent>.makeStream()
        let generation = UUID()
        let restartGate = NativeStartGate()
        try await a.start(.init(
            resources: [.camera],
            nativeEvents: { .init(generation: generation, stream: pair.stream) },
            restartNative: { await restartGate.wait() },
            startNative: { { _ in } }
        ))
        pair.continuation.yield(.interrupted(generation: generation, reason: "test"))
        await eventually { a.state == .suspended(.interrupted("test")) }
        pair.continuation.yield(.interruptionEnded(generation: generation))
        await restartGate.waitUntilEntered()

        let aStop = Task { @MainActor in await a.stop() }
        await eventually { a.state == .stopping(.user) }
        let switched = CaptureFlag()
        let bStart = Task { @MainActor in
            try await b.start(operation(events: .init(), label: "b"), switching: .stopCurrent)
            switched.value = true
        }
        await Task.yield()
        XCTAssertEqual(coordinator.currentCameraOwner, MiniAppID("restart-a"))
        XCTAssertFalse(switched.value)
        restartGate.open()
        await aStop.value
        try await bStart.value
        XCTAssertTrue(switched.value)
        XCTAssertEqual(coordinator.currentCameraOwner, MiniAppID("restart-b"))
    }

    func testStopWhileAwaitingNativeEventStreamDoesNotRegisterLateObserver() async throws {
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("events-late"), coordinator: coordinator,
                                        permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("events-late"))
        let gate = NativeEventsGate()
        let events = CaptureEvents()
        let starting = Task { @MainActor in
            try await owner.start(.init(
                resources: [.camera], nativeEvents: { await gate.wait() },
                startNative: { { _ in events.append("native-stop") } }
            ))
        }
        await gate.waitUntilEntered()
        await owner.stop()
        gate.open()
        await XCTAssertThrowsErrorAsync(try await starting.value) { _ in }
        XCTAssertEqual(events.values, ["native-stop"])
        XCTAssertNil(coordinator.currentCameraOwner)
        XCTAssertEqual(owner.state, .idle)
    }

    func testConsentDenialPrecedesOSPermissionAndNativeAcquisition() async throws {
        let permissions = CapturePermissions()
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("denied"), coordinator: coordinator,
                                        permissions: permissions)
        let runtime = MiniAppRuntime()
        try owner.connect(to: runtime)
        owner.receive(active("denied"))
        await XCTAssertThrowsErrorAsync(try await owner.start(operation(events: .init(), label: "denied"))) {
            XCTAssertEqual($0 as? MiniAppCaptureFailure, .featureConsentDenied(.camera))
        }
        XCTAssertTrue(permissions.requestedResources.isEmpty)
        XCTAssertNil(coordinator.currentCameraOwner)
    }

    func testConsentRevokedDuringOSPromptIsRecheckedBeforeCameraReservation() async throws {
        let permissions = CapturePermissions(blocked: true)
        let consent = ConsentFlag()
        let coordinator = MiniAppCaptureCoordinator()
        let owner = MiniAppCaptureOwner(id: MiniAppID("revoked"), coordinator: coordinator,
                                        permissions: permissions, consent: { _ in consent.allowed })
        let runtime = MiniAppRuntime(); try owner.connect(to: runtime); owner.receive(active("revoked"))
        let events = CaptureEvents()
        let starting = Task { @MainActor in
            try await owner.start(operation(events: events, label: "revoked"))
        }
        await permissions.waitUntilRequested()
        consent.allowed = false
        permissions.resolve(true)
        await XCTAssertThrowsErrorAsync(try await starting.value) {
            XCTAssertEqual($0 as? MiniAppCaptureFailure, .featureConsentDenied(.camera))
        }
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertNil(coordinator.currentCameraOwner)
    }

    func testShutdownJoiningSuspensionEndsRuntimeAndAllowsReconnect() async throws {
        let owner = MiniAppCaptureOwner(id: MiniAppID("restart"), coordinator: .init(), permissions: CapturePermissions(), consent: allow)
        let runtime = MiniAppRuntime()
        try owner.connect(to: runtime)
        owner.receive(active("restart"))
        let gate = NativeStartGate()
        try await owner.start(.init(resources: [.camera]) { { _ in await gate.wait() } })
        let suspension = Task { @MainActor in await owner.suspend(.background) }
        await gate.waitUntilEntered()
        let shutdown = Task { @MainActor in await runtime.shutdown() }
        await eventually { runtime.isClosed }
        gate.open()
        await suspension.value
        await shutdown.value
        XCTAssertEqual(owner.state, .stopped)
        let next = MiniAppRuntime()
        try owner.connect(to: next)
        try await owner.start(operation(events: .init(), label: "restart"))
        XCTAssertEqual(owner.state, .running([.camera]))
        await next.shutdown()
    }
}

@MainActor
private final class CapturePermissions: MiniAppCapturePermissionClient {
    private var blocked: Bool
    private var continuation: CheckedContinuation<Bool, Never>?
    private var requested = false
    private(set) var requestedResources: [MiniAppCaptureResource] = []
    init(blocked: Bool = false) { self.blocked = blocked }
    func request(_ resource: MiniAppCaptureResource) async -> Bool {
        requested = true
        requestedResources.append(resource)
        guard blocked else { return true }
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilRequested() async {
        while !requested { await Task.yield() }
    }
    func resolve(_ value: Bool) {
        blocked = false
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor private func allow(_ resource: MiniAppCaptureResource) -> Bool { true }

@MainActor
private final class CaptureEvents {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

@MainActor private final class CaptureFlag { var value = false }
@MainActor private final class ConsentFlag { var allowed = true }

@MainActor
private final class NativeStartGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }
    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class NativeEventsGate {
    private let generation = UUID()
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async -> MiniAppCaptureNativeEvents {
        entered = true
        await withCheckedContinuation { continuation = $0 }
        return .init(generation: generation, stream: AsyncStream { $0.finish() })
    }
    func waitUntilEntered() async { while !entered { await Task.yield() } }
    func open() { continuation?.resume(); continuation = nil }
}

@MainActor
private func operation(events: CaptureEvents, label: String) -> MiniAppCaptureOperation {
    MiniAppCaptureOperation(resources: [.camera]) {
        events.append("start-\(label)")
        return { reason in
            let text: String = switch reason {
            case .switched: "switched"
            case .sceneInactive: "sceneInactive"
            default: "other"
            }
            events.append("stop-\(label)-\(text)")
        }
    }
}

private func active(_ owner: String) -> MiniAppSceneActivity {
    activity(owner, UUID(), .active, true)
}

private func activity(_ owner: String, _ scene: UUID, _ phase: MiniAppSceneActivity.Phase?, _ selected: Bool) -> MiniAppSceneActivity {
    .init(featureID: MiniAppID(owner), sceneID: scene, phase: phase, isSelected: selected)
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<100 where !condition() { await Task.yield() }
    XCTAssertTrue(condition())
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do { _ = try await expression(); XCTFail("expected error", file: file, line: line) }
    catch { handler(error) }
}
