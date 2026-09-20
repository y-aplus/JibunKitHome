import XCTest
import JibunKitCore

final class MiniAppWindowSceneRegistryTests: XCTestCase, @unchecked Sendable {
    private let a = MiniAppID("scene-a")
    private let b = MiniAppID("scene-b")

    @MainActor
    func testTwoWindowsKeepIndependentRoutesSelectionAndFeatureState() async throws {
        let registry = MiniAppWindowSceneRegistry()
        let firstID = MiniAppWindowSessionID("persistent-one")
        let secondID = MiniAppWindowSessionID("persistent-two")
        var firstRoutes: [String?] = []
        var secondRoutes: [String?] = []
        var firstFeatureState = 11
        var secondFeatureState = 27
        let first = await registry.connect(sessionID: firstID, phase: .active, selectedID: a) {
            firstRoutes.append($0?.destination)
        }
        let second = await registry.connect(sessionID: secondID, phase: .inactive, selectedID: b) {
            secondRoutes.append($0?.destination)
        }

        XCTAssertEqual(registry.open(try route(a, "detail-a"), in: firstID), .delivered(first))
        XCTAssertEqual(registry.open(try route(b, "detail-b"), in: secondID), .delivered(second))
        XCTAssertTrue(registry.update(first, phase: .inactive, selectedID: b))
        firstFeatureState += 1

        XCTAssertEqual(firstRoutes, ["detail-a"])
        XCTAssertEqual(secondRoutes, ["detail-b"])
        XCTAssertEqual(firstFeatureState, 12)
        XCTAssertEqual(secondFeatureState, 27)
        XCTAssertEqual(registry.snapshot(for: firstID)?.selectedID, b)
        XCTAssertEqual(registry.snapshot(for: secondID)?.selectedID, b)
    }

    @MainActor
    func testDisconnectReleasesOnlyThatWindowAndDoesNotStopGlobalOwner() async throws {
        let registry = MiniAppWindowSceneRegistry()
        let runtime = MiniAppRuntime()
        var globalStopped = false
        try runtime.onShutdown { globalStopped = true }
        var releases: [String] = []
        let firstID = MiniAppWindowSessionID("one")
        let secondID = MiniAppWindowSessionID("two")
        let first = await registry.connect(sessionID: firstID, phase: .active, selectedID: a) { _ in }
        let second = await registry.connect(sessionID: secondID, phase: .active, selectedID: a) { _ in }
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: first) { releases.append("one-a") })
        XCTAssertTrue(registry.onDisconnect(owner: b, connection: first) { releases.append("one-b") })
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: second) { releases.append("two-a") })

        let disconnected = await registry.disconnect(first)
        XCTAssertTrue(disconnected)
        XCTAssertEqual(Set(releases), ["one-a", "one-b"])
        XCTAssertNotNil(registry.snapshot(for: secondID))
        XCTAssertFalse(globalStopped)
        XCTAssertFalse(runtime.isClosed)
        XCTAssertEqual(registry.open(nil, in: secondID), .delivered(second))
        await runtime.shutdown()
        XCTAssertTrue(globalStopped)
    }

    @MainActor
    func testRestoreKeepsSessionIdentityButRejectsOldGenerationAndLateDisconnect() async {
        let registry = MiniAppWindowSceneRegistry()
        let sessionID = MiniAppWindowSessionID("restored")
        var oldDeliveries = 0
        var newDeliveries = 0
        var oldReleased = false
        let old = await registry.connect(sessionID: sessionID, phase: .background, selectedID: a) { _ in
            oldDeliveries += 1
        }
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: old) { oldReleased = true })
        let restored = await registry.connect(sessionID: sessionID, phase: .inactive, selectedID: b) { _ in
            newDeliveries += 1
        }

        XCTAssertTrue(oldReleased)
        XCTAssertEqual(restored.sessionID, old.sessionID)
        XCTAssertNotEqual(restored.generation, old.generation)
        XCTAssertEqual(
            registry.open(nil, in: sessionID, expected: old),
            .staleConnection(current: restored)
        )
        let staleDisconnected = await registry.disconnect(old)
        XCTAssertFalse(staleDisconnected)
        XCTAssertEqual(registry.open(nil, in: sessionID, expected: restored), .delivered(restored))
        XCTAssertEqual(oldDeliveries, 0)
        XCTAssertEqual(newDeliveries, 1)
    }

    @MainActor
    func testCleanupIsReverseRegistrationOrderWithinOwner() async {
        let registry = MiniAppWindowSceneRegistry()
        let id = MiniAppWindowSessionID("cleanup")
        let connection = await registry.connect(sessionID: id, phase: .active, selectedID: a) { _ in }
        var releases: [Int] = []
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: connection) { releases.append(1) })
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: connection) { releases.append(2) })
        let disconnected = await registry.disconnect(connection)
        XCTAssertTrue(disconnected)
        XCTAssertEqual(releases, [2, 1])
    }

    @MainActor
    func testReconnectWhileOldCleanupIsHeldCannotOverwriteNewerGenerationOrLoseCleanup() async throws {
        let registry = MiniAppWindowSceneRegistry()
        let sessionID = MiniAppWindowSessionID("reentrant-connect")
        let gate = CleanupGate()
        let cleanupStarted = expectation(description: "old cleanup started")
        let old = await registry.connect(sessionID: sessionID, phase: .active, selectedID: a) { _ in }
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: old) {
            cleanupStarted.fulfill()
            await gate.wait()
        })

        let reconnecting = Task { @MainActor in
            await registry.connect(sessionID: sessionID, phase: .inactive, selectedID: a) { _ in }
        }
        await fulfillment(of: [cleanupStarted], timeout: 1)
        let middle = try XCTUnwrap(registry.snapshot(for: sessionID)?.connection)
        var middleReleased = false
        XCTAssertTrue(registry.onDisconnect(owner: b, connection: middle) { middleReleased = true })
        let middleCleanup = expectation(description: "middle cleanup finished")
        XCTAssertTrue(registry.onDisconnect(owner: b, connection: middle) { middleCleanup.fulfill() })
        var newestCompleted = false
        let connectingNewest = Task { @MainActor in
            let value = await registry.connect(sessionID: sessionID, phase: .active, selectedID: b) { _ in }
            newestCompleted = true
            return value
        }
        await fulfillment(of: [middleCleanup], timeout: 1)
        XCTAssertFalse(newestCompleted, "New connection must join the old session cleanup")

        await gate.release()
        let newest = await connectingNewest.value
        XCTAssertTrue(middleReleased)
        let returnedMiddle = await reconnecting.value
        XCTAssertEqual(returnedMiddle, middle)
        XCTAssertEqual(registry.snapshot(for: sessionID)?.connection, newest)
        XCTAssertEqual(registry.open(nil, in: sessionID, expected: middle), .staleConnection(current: newest))
    }

    @MainActor
    func testConnectDuringHeldDisconnectCleanupSurvivesLateDisconnectCompletion() async {
        let registry = MiniAppWindowSceneRegistry()
        let sessionID = MiniAppWindowSessionID("reentrant-disconnect")
        let gate = CleanupGate()
        let cleanupStarted = expectation(description: "disconnect cleanup started")
        let old = await registry.connect(sessionID: sessionID, phase: .active, selectedID: a) { _ in }
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: old) {
            cleanupStarted.fulfill()
            await gate.wait()
        })
        let disconnecting = Task { @MainActor in await registry.disconnect(old) }
        await fulfillment(of: [cleanupStarted], timeout: 1)
        var connectCompleted = false
        let connecting = Task { @MainActor in
            let value = await registry.connect(sessionID: sessionID, phase: .active, selectedID: b) { _ in }
            connectCompleted = true
            return value
        }
        for _ in 0..<20 {
            if registry.snapshot(for: sessionID) != nil { break }
            await Task.yield()
        }
        let published = registry.snapshot(for: sessionID)?.connection
        XCTAssertNotNil(published, "The new generation is visible while inherited cleanup is joined")
        XCTAssertFalse(connectCompleted, "connect must join cleanup already pending for this session")
        await gate.release()

        let disconnected = await disconnecting.value
        let newest = await connecting.value
        XCTAssertTrue(disconnected)
        XCTAssertEqual(newest, published)
        XCTAssertTrue(connectCompleted)
        XCTAssertEqual(registry.snapshot(for: sessionID)?.connection, newest)
    }

    @MainActor
    func testOwnerSuspensionReleasesEverySceneAndRejectsNewAdmissionWithoutStoppingOthers() async throws {
        let registry = MiniAppWindowSceneRegistry()
        let first = await registry.connect(sessionID: .init("owner-one"), phase: .active, selectedID: a) { _ in }
        let second = await registry.connect(sessionID: .init("owner-two"), phase: .active, selectedID: b) { _ in }
        let aRuntime = MiniAppRuntime()
        let bRuntime = MiniAppRuntime()
        var released: [String] = []
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: first) { released.append("a-one") })
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: second) { released.append("a-two") })
        XCTAssertTrue(registry.onDisconnect(owner: b, connection: second) { released.append("b-two") })

        await registry.suspendAndRelease(owner: a)
        XCTAssertEqual(Set(released), ["a-one", "a-two"])
        XCTAssertTrue(registry.isSuspended(owner: a))
        XCTAssertFalse(registry.onDisconnect(owner: a, connection: second) { released.append("late-a") })
        XCTAssertFalse(aRuntime.isClosed)
        XCTAssertFalse(bRuntime.isClosed)
        let disconnected = await registry.disconnect(second)
        XCTAssertTrue(disconnected)
        XCTAssertEqual(Set(released), ["a-one", "a-two", "b-two"])

        registry.resume(owner: a)
        XCTAssertFalse(registry.isSuspended(owner: a))
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: first) { released.append("new-a") })
        await aRuntime.shutdown()
        await bRuntime.shutdown()
    }

    @MainActor
    func testConcurrentOwnerSuspensionJoinsCleanupAlreadyInProgress() async {
        let registry = MiniAppWindowSceneRegistry()
        let connection = await registry.connect(
            sessionID: .init("owner-join"), phase: .active, selectedID: a
        ) { _ in }
        let gate = CleanupGate()
        let started = expectation(description: "owner cleanup started")
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: connection) {
            started.fulfill()
            await gate.wait()
        })
        let first = Task { @MainActor in await registry.suspendAndRelease(owner: a) }
        await fulfillment(of: [started], timeout: 1)
        var secondCompleted = false
        let second = Task { @MainActor in
            await registry.suspendAndRelease(owner: a)
            secondCompleted = true
        }
        for _ in 0..<20 {
            if registry.isSuspended(owner: a) { break }
            await Task.yield()
        }
        XCTAssertFalse(secondCompleted)
        await gate.release()
        await first.value
        await second.value
        XCTAssertTrue(secondCompleted)
    }

    @MainActor
    func testOwnerSuspensionJoinsCleanupAlreadyDetachedByDisconnectAndResumeIsRejected() async {
        let registry = MiniAppWindowSceneRegistry()
        let disconnectingSession = MiniAppWindowSessionID("owner-detached")
        let survivingSession = MiniAppWindowSessionID("owner-surviving")
        let disconnectingConnection = await registry.connect(
            sessionID: disconnectingSession, phase: .active, selectedID: a
        ) { _ in }
        let survivingConnection = await registry.connect(
            sessionID: survivingSession, phase: .active, selectedID: b
        ) { _ in }
        let gate = CleanupGate()
        let started = expectation(description: "detached cleanup started")
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: disconnectingConnection) {
            started.fulfill()
            await gate.wait()
        })
        let disconnecting = Task { @MainActor in
            await registry.disconnect(disconnectingConnection)
        }
        await fulfillment(of: [started], timeout: 1)

        var suspensionCompleted = false
        let suspending = Task { @MainActor in
            await registry.suspendAndRelease(owner: a)
            suspensionCompleted = true
        }
        await Task.yield()
        XCTAssertFalse(suspensionCompleted, "management must join cleanup detached by disconnect")
        XCTAssertFalse(registry.resume(owner: a), "resume cannot reopen admission during owner cleanup")
        XCTAssertFalse(registry.onDisconnect(owner: a, connection: survivingConnection) {})

        await gate.release()
        let disconnected = await disconnecting.value
        XCTAssertTrue(disconnected)
        await suspending.value
        XCTAssertTrue(suspensionCompleted)
        XCTAssertTrue(registry.resume(owner: a))
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: survivingConnection) {})
    }

    @MainActor
    func testBootstrapClosesPersistedDisabledOwnerAdmissionBeforeFirstScene() async {
        let registry = MiniAppWindowSceneRegistry()
        registry.bootstrapSuspendedOwners([a])
        let connection = await registry.connect(
            sessionID: .init("bootstrap"), phase: .active, selectedID: a
        ) { _ in }
        XCTAssertTrue(registry.isSuspended(owner: a))
        XCTAssertFalse(registry.onDisconnect(owner: a, connection: connection) {})
        XCTAssertTrue(registry.onDisconnect(owner: b, connection: connection) {})
        XCTAssertTrue(registry.resume(owner: a))
        XCTAssertTrue(registry.onDisconnect(owner: a, connection: connection) {})
    }

    private func route(_ id: MiniAppID, _ destination: String) throws -> MiniAppRoute {
        let url = try XCTUnwrap(MiniAppLink.url(for: id, destination: destination))
        return try XCTUnwrap(MiniAppLink.resolveRoute(url, registeredIDs: [id]))
    }
}

private actor CleanupGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

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
