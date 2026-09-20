import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppRemotePushTests: XCTestCase {
    private let a = MiniAppID("push-a"), b = MiniAppID("push-b")

    func testTokenChangeUsesSeparateIdentityAndFailureAllowsSameTokenRecovery() async throws {
        let coordinator = MiniAppRemotePushCoordinator(), log = PushLog()
        let sa = try service(a, "server-a", coordinator, log), sb = try service(b, "server-b", coordinator, log)
        let ra = MiniAppRuntime(), rb = MiniAppRuntime()
        try sa.connect(to: ra); try sb.connect(to: rb)
        coordinator.didRegisterForRemoteNotifications(deviceToken: Data([1]))
        await coordinator.waitForRegistrationCallbacks()
        coordinator.didFailToRegisterForRemoteNotifications(PushTestError.rejected)
        await coordinator.waitForRegistrationCallbacks()
        coordinator.didRegisterForRemoteNotifications(deviceToken: Data([1]))
        await coordinator.waitForRegistrationCallbacks()
        XCTAssertEqual(log.tokens[a], [Data([1]), Data([1])])
        XCTAssertEqual(log.tokens[b], [Data([1]), Data([1])])
        XCTAssertEqual(log.servers[a], ["server-a", "server-a"])
        XCTAssertEqual(log.failures[a]?.count, 1)
        await ra.shutdown(); await rb.shutdown()
    }

    func testSlowTokenOneNeverArrivesAfterTokenTwo() async throws {
        let coordinator = MiniAppRemotePushCoordinator(), gate = PushGate(), entered = expectation(description: "token1")
        var values: [Data] = []
        let service = MiniAppRemotePushService(owner: a,
            identity: try MiniAppRemotePushIdentity(server: "a", account: "id"), coordinator: coordinator,
            onRegistration: { event in
                if case .tokenChanged(let token, _, _) = event {
                    values.append(token)
                    if token == Data([1]) { entered.fulfill(); await gate.wait() }
                }
            })
        let runtime = MiniAppRuntime(); try service.connect(to: runtime)
        coordinator.didRegisterForRemoteNotifications(deviceToken: Data([1]))
        await fulfillment(of: [entered], timeout: 2)
        coordinator.didRegisterForRemoteNotifications(deviceToken: Data([2]))
        await gate.release(); await coordinator.waitForRegistrationCallbacks()
        XCTAssertEqual(values, [Data([1]), Data([2])])
        await runtime.shutdown()
    }

    func testClosedRuntimeCannotLeakRegistration() async throws {
        let coordinator = MiniAppRemotePushCoordinator(), log = PushLog()
        let runtime = MiniAppRuntime()
        let service = try service(a, "a", coordinator, log)
        await runtime.shutdown()
        XCTAssertThrowsError(try service.connect(to: runtime))
        XCTAssertTrue(coordinator.registeredOwners.isEmpty)
    }

    func testOldServiceCannotUnregisterNewServiceForSameOwner() async throws {
        let coordinator = MiniAppRemotePushCoordinator(), oldLog = PushLog(), newLog = PushLog()
        let old = try service(a, "old", coordinator, oldLog), new = try service(a, "new", coordinator, newLog)
        let oldRuntime = MiniAppRuntime(), newRuntime = MiniAppRuntime()
        try old.connect(to: oldRuntime); try new.connect(to: newRuntime)
        await old.unregister()
        let result = await coordinator.deliver(userInfo: ownerPayload(a))
        XCTAssertEqual(result, .newData)
        XCTAssertNil(oldLog.messages[a]); XCTAssertEqual(newLog.messages[a]?.count, 1)
        await new.unregister()
        XCTAssertNil(oldLog.unregistered[a])
        XCTAssertEqual(newLog.unregistered[a], ["new"])
        await oldRuntime.shutdown(); await newRuntime.shutdown()
    }

    func testStoppedHandlerIsJoinedAndItsResultIsRejected() async throws {
        let coordinator = MiniAppRemotePushCoordinator(), gate = PushGate(), entered = expectation(description: "delivery")
        let service = MiniAppRemotePushService(owner: a,
            identity: try MiniAppRemotePushIdentity(server: "a", account: "id"), coordinator: coordinator,
            onDelivery: { _ in entered.fulfill(); await gate.wait(); return .newData })
        let runtime = MiniAppRuntime(); try service.connect(to: runtime)
        let delivery = Task { await coordinator.deliver(userInfo: self.ownerPayload(self.a)) }
        await fulfillment(of: [entered], timeout: 2)
        let stopping = Task { await runtime.shutdown() }
        await Task.yield()
        XCTAssertFalse(runtime.shutdownProgress.phase == .completed)
        await gate.release(); await stopping.value
        let stoppedResult = await delivery.value
        XCTAssertEqual(stoppedResult, .noData)
    }

    func testStoppingOwnerADoesNotDisturbOwnerBNoninitialStateOrDelivery() async throws {
        let coordinator = MiniAppRemotePushCoordinator(), gate = PushGate(), entered = expectation(description: "A delivery")
        let aService = MiniAppRemotePushService(owner: a,
            identity: try MiniAppRemotePushIdentity(server: "a", account: "same"), coordinator: coordinator,
            onDelivery: { _ in entered.fulfill(); await gate.wait(); return .newData })
        let bLog = PushLog(), bService = try service(b, "b", coordinator, bLog)
        let aRuntime = MiniAppRuntime(), bRuntime = MiniAppRuntime()
        try aService.connect(to: aRuntime); try bService.connect(to: bRuntime)
        bLog.state = "B noninitial"
        let deliveryA = Task { await coordinator.deliver(userInfo: self.ownerPayload(self.a)) }
        await fulfillment(of: [entered], timeout: 2)
        let stoppingA = Task { await aRuntime.shutdown() }
        let resultB = await coordinator.deliver(userInfo: ownerPayload(b))
        XCTAssertEqual(resultB, .newData)
        XCTAssertEqual(bLog.state, "B noninitial")
        XCTAssertEqual(bLog.messages[b]?.count, 1)
        await gate.release(); await stoppingA.value
        let resultA = await deliveryA.value
        XCTAssertEqual(resultA, .noData)
        XCTAssertFalse(bRuntime.isClosed)
        await bRuntime.shutdown()
    }

    func testColdDeliveryStartsAdmittedLifetimeAndRejectsManagedOffOwner() async throws {
        let coordinator = MiniAppRemotePushCoordinator(), log = PushLog()
        let service = try service(a, "a", coordinator, log)
        let lifetime = MiniAppFeatureLifetime(id: a) { runtime in try service.connect(to: runtime) }
        service.prepareColdStart(lifetime: lifetime)
        let admitted = await coordinator.deliver(userInfo: ownerPayload(a))
        XCTAssertEqual(admitted, .newData)
        await lifetime.stop()
        lifetime.setStartAllowed(false)
        let denied = await coordinator.deliver(userInfo: ownerPayload(a))
        XCTAssertEqual(denied, .noData)
    }

    func testOwnerOnlyDeliveryPreservesNestedArrayAndNullAndRejectsInvalidPayload() async throws {
        let coordinator = MiniAppRemotePushCoordinator(), log = PushLog()
        let runtime = MiniAppRuntime(); try service(a, "a", coordinator, log).connect(to: runtime)
        var payload = ownerPayload(a)
        payload["nested"] = ["items": [1, NSNull(), "x"]]
        payload["large"] = NSNumber(value: Int64.max)
        let valid = await coordinator.deliver(userInfo: payload)
        XCTAssertEqual(valid, .newData)
        let captured = try XCTUnwrap(log.messages[a]?.first)
        XCTAssertEqual(captured.payload["nested"], .object(["items": .array([.integer(1), .null, .string("x")])]))
        XCTAssertEqual(captured.payload["large"], .integer(Int64.max))
        let encoded = try JSONSerialization.data(withJSONObject: captured.jsonObject())
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual((decoded["large"] as? NSNumber)?.int64Value, Int64.max)
        payload["invalid"] = Date()
        let invalid = await coordinator.deliver(userInfo: payload)
        XCTAssertEqual(invalid, .failed)
        XCTAssertEqual(log.messages[a]?.count, 1)
        payload["invalid"] = Double.infinity
        let infinite = await coordinator.deliver(userInfo: payload)
        XCTAssertEqual(infinite, .failed)
        payload["invalid"] = Double.nan
        let nan = await coordinator.deliver(userInfo: payload)
        XCTAssertEqual(nan, .failed)
        let other = await coordinator.deliver(userInfo: ownerPayload(b))
        XCTAssertEqual(other, .noData)
        await runtime.shutdown()
    }

    func testAggregatorSurvivesLocalOwnerAndCompletesOnce() async {
        let completed = expectation(description: "completed")
        let values = LockedResults()
        var ticket: (@Sendable (MiniAppRemotePushFetchResult) -> Void)?
        do {
            let aggregator = MiniAppRemotePushCompletionAggregator { values.append($0); completed.fulfill() }
            ticket = aggregator.ticket(); aggregator.finishAdding()
        }
        ticket?(.newData); ticket?(.failed)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(values.values, [.newData])
    }

    private func service(_ owner: MiniAppID, _ server: String, _ coordinator: MiniAppRemotePushCoordinator,
                         _ log: PushLog) throws -> MiniAppRemotePushService {
        MiniAppRemotePushService(owner: owner,
            identity: try MiniAppRemotePushIdentity(server: server, account: "shared-local-id"), coordinator: coordinator,
            onRegistration: { log.record(owner, $0) },
            onDelivery: { log.messages[owner, default: []].append($0); return .newData },
            onUnregister: { log.unregistered[owner, default: []].append($0.server) })
    }
    private func ownerPayload(_ owner: MiniAppID) -> [AnyHashable: Any] {
        [MiniAppNotificationRoute.miniAppIDUserInfoKey: owner.rawValue]
    }
}

private enum PushTestError: Error { case rejected }
private actor PushGate {
    private var open = false, waiter: CheckedContinuation<Void, Never>?
    func wait() async { if open { return }; await withCheckedContinuation { waiter = $0 } }
    func release() { open = true; waiter?.resume(); waiter = nil }
}
@MainActor private final class PushLog {
    var state = "initial"
    var tokens: [MiniAppID: [Data]] = [:], servers: [MiniAppID: [String]] = [:]
    var failures: [MiniAppID: [String]] = [:], messages: [MiniAppID: [MiniAppRemotePushMessage]] = [:]
    var unregistered: [MiniAppID: [String]] = [:]
    func record(_ owner: MiniAppID, _ event: MiniAppRemotePushRegistrationEvent) {
        switch event {
        case .tokenChanged(let token, let identity, _):
            tokens[owner, default: []].append(token); servers[owner, default: []].append(identity.server)
        case .registrationFailed(let message, _): failures[owner, default: []].append(message)
        case .ownerUnregistered: break
        }
    }
}
private final class LockedResults: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [MiniAppRemotePushFetchResult] = []
    var values: [MiniAppRemotePushFetchResult] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ value: MiniAppRemotePushFetchResult) { lock.lock(); storage.append(value); lock.unlock() }
}
