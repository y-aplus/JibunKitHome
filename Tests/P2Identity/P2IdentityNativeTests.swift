#if os(iOS)
import XCTest
@testable import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2IdentityNativeTests: XCTestCase {
    func testProbePublishesTwoOrdinaryDefinitionsWithoutCreatingCKContainer() {
        let definitions = P2IdentityProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-identity-a"), MiniAppID("p2-identity-b")])
        XCTAssertTrue(definitions.allSatisfy {
            $0.lifetime != nil && $0.removal != nil && $0.externalAccess != nil
        })
    }

    func testTwoOwnersKeepSameLocalIDSeparateAcrossRemoval() async throws {
        let backend = P2IdentityBackend(account: "one")
        let (a, b) = try pair(backend)
        _ = try await a.activate(); _ = try await b.activate()
        let ai = try await a.identity(localID: "same"), bi = try await b.identity(localID: "same")
        try await a.save(ai, fields: ["v": "A"]); try await b.save(bi, fields: ["v": "B"])
        await a.deactivate()
        try await a.removeOwnedData()
        _ = try await a.activate(); let reopened = try await a.identity(localID: "same")
        let deleted = try await a.load(reopened), preserved = try await b.load(bi)
        XCTAssertNil(deleted); XCTAssertEqual(preserved?.fields["v"], "B")
    }

    func testAccountReplacementAndLateCompletionCannotPublishOldResult() async throws {
        let backend = P2IdentityBackend(account: "old"), (a, _) = try pair(backend)
        _ = try await a.activate(); let old = try await a.identity(localID: "same")
        try await a.save(old, fields: ["v": "old"]); await backend.hold()
        let late = Task { try await a.load(old) }
        await backend.waitForHold(); await backend.changeAccount("new")
        _ = try await a.accountDidChange(); await backend.release()
        do { _ = try await late.value; XCTFail("Expected stale account result rejection") }
        catch let error as MiniAppExternalIdentityError { XCTAssertEqual(error, .staleGeneration) }
        let fresh = try await a.identity(localID: "same")
        try await a.save(fresh, fields: ["v": "new"])
        let value = try await a.load(fresh)
        XCTAssertEqual(value?.fields["v"], "new")
    }

    func testFailureThenRecoveryLeavesOtherOwnerRunning() async throws {
        let backend = P2IdentityBackend(account: "one"), (a, b) = try pair(backend)
        _ = try await b.activate(); let bi = try await b.identity(localID: "same")
        try await b.save(bi, fields: ["v": "B"]); await backend.failOnce()
        do { _ = try await a.activate(); XCTFail("Expected injected activation failure") }
        catch {}
        _ = try await a.activate()
        let preserved = try await b.load(bi)
        XCTAssertEqual(preserved?.fields["v"], "B")
    }

    func testRealFeatureRestoreReconnectsAWithoutChangingBOrPersistentIdentity() async throws {
        let backend = P2IdentityBackend(account: "one")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = P2IdentityFeature(id: MiniAppID("restore-a"), scope: scope, backend: backend)
        let b = P2IdentityFeature(id: MiniAppID("restore-b"), scope: scope, backend: backend)
        let aDefinition = a.definition, bDefinition = b.definition
        try await aDefinition.lifetime?.start(); try await bDefinition.lifetime?.start()
        let bRuntime = bDefinition.lifetime?.runtime
        let oldA = try await a.service.coordinator.identity(localID: "same")
        let bID = try await b.service.coordinator.identity(localID: "same")
        try await a.service.coordinator.save(oldA, fields: ["v": "A"])
        try await b.service.coordinator.save(bID, fields: ["v": "B"])
        let lifecycle = try XCTUnwrap(aDefinition.effectiveRestoreLifecycle)
        try await lifecycle.stop(); try await lifecycle.resume()
        let newA = try await a.service.coordinator.identity(localID: "same")
        let restored = try await a.service.coordinator.load(newA)
        let preserved = try await b.service.coordinator.load(bID)
        XCTAssertNotEqual(oldA.account.generation, newA.account.generation)
        XCTAssertEqual(restored?.fields["v"], "A")
        XCTAssertTrue(bDefinition.lifetime?.runtime === bRuntime)
        XCTAssertEqual(preserved?.fields["v"], "B")
        await aDefinition.lifetime?.stop(); await bDefinition.lifetime?.stop()
    }

    func testRealFeatureManagementRemoveDeletesAAfterStopAndKeepsBRunning() async throws {
        let backend = P2IdentityBackend(account: "one")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = P2IdentityFeature(id: MiniAppID("managed-a"), scope: scope, backend: backend)
        let b = P2IdentityFeature(id: MiniAppID("managed-b"), scope: scope, backend: backend)
        let aDefinition = a.definition, bDefinition = b.definition
        let suite = "P2IdentityNativeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = MiniAppManagement(registrations: [aDefinition, bDefinition].map {
            .init(id: $0.id, lifetime: $0.lifetime, removal: $0.removal,
                  externalAccess: $0.externalAccess)
        }, defaults: defaults, consents: .init(defaults: defaults), coordinator: .init())
        try await aDefinition.lifetime?.start(); try await bDefinition.lifetime?.start()
        let bRuntime = bDefinition.lifetime?.runtime
        let aID = try await a.service.coordinator.identity(localID: "same")
        let bID = try await b.service.coordinator.identity(localID: "same")
        try await a.service.coordinator.save(aID, fields: ["v": "A"])
        try await b.service.coordinator.save(bID, fields: ["v": "B"])
        try await manager.remove(a.id)
        let preserved = try await b.service.coordinator.load(bID)
        XCTAssertEqual(manager.status(for: a.id), .removed)
        XCTAssertTrue(bDefinition.lifetime?.runtime === bRuntime)
        XCTAssertEqual(preserved?.fields["v"], "B")
        await bDefinition.lifetime?.stop()
    }

    private func pair(_ backend: P2IdentityBackend) throws
        -> (MiniAppExternalIdentityCoordinator, MiniAppExternalIdentityCoordinator) {
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        return (.init(owner: MiniAppID("native-a"), container: scope, backend: backend),
                .init(owner: MiniAppID("native-b"), container: scope, backend: backend))
    }
}

private actor P2IdentityBackend: MiniAppExternalIdentityBackend {
    enum Failure: Error { case injected, wrongAccount }
    var account: String; var records: [MiniAppExternalPersistentRecordKey: [String: String]] = [:]
    var failing = false, holding = false
    var held: CheckedContinuation<Void, Never>?, observed: CheckedContinuation<Void, Never>?
    init(account: String) { self.account = account }
    func changeAccount(_ value: String) { account = value }
    func failOnce() { failing = true }
    func hold() { holding = true }
    func waitForHold() async { if held == nil { await withCheckedContinuation { observed = $0 } } }
    func release() { held?.resume(); held = nil }
    func currentAccountIdentifier(in container: MiniAppExternalContainer) async throws -> String {
        if failing { failing = false; throw Failure.injected }; return account
    }
    func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? {
        try validate(identity.account)
        if holding { holding = false; await withCheckedContinuation { held = $0; observed?.resume(); observed = nil } }
        return records[MiniAppExternalPersistentRecordKey(identity)].map {
            MiniAppExternalRecord(identity: identity, fields: $0)
        }
    }
    func save(_ record: MiniAppExternalRecord) async throws {
        try validate(record.identity.account)
        let key = MiniAppExternalPersistentRecordKey(record.identity)
        records[key, default: [:]].merge(record.fields) { _, new in new }
    }
    func delete(_ identity: MiniAppExternalRecordIdentity) async throws {
        try validate(identity.account)
        records[MiniAppExternalPersistentRecordKey(identity)] = nil
    }
    func ensureSubscription(for account: MiniAppExternalAccount) async throws { try validate(account) }
    func deleteOwnedData(for account: MiniAppExternalAccount) async throws {
        try validate(account)
        records = records.filter { key, _ in
            key.owner != account.owner || key.container != account.container
                || key.accountIdentifier != account.accountIdentifier
        }
    }
    func cancelOperations(owner: MiniAppID) async { release() }
    func accountChanges() async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    private func validate(_ expected: MiniAppExternalAccount) throws {
        guard expected.accountIdentifier == account else { throw Failure.wrongAccount }
    }
}

#endif
