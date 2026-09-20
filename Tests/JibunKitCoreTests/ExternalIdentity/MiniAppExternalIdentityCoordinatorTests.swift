import XCTest
@testable import JibunKitCore

final class MiniAppExternalIdentityCoordinatorTests: XCTestCase {
    func testSameLocalIDIsSeparatedForTwoOwnersAndRemovingOneKeepsOther() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account-1")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-a"), container: scope, backend: backend)
        let b = MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-b"), container: scope, backend: backend)
        _ = try await a.activate(); _ = try await b.activate()
        let aID = try await a.identity(localID: "same")
        let bID = try await b.identity(localID: "same")
        try await a.save(aID, fields: ["value": "A"])
        try await b.save(bID, fields: ["value": "B"])
        await a.deactivate()
        try await a.removeOwnedData()
        _ = try await a.activate()
        let reopenedA = try await a.identity(localID: "same")
        let deleted = try await a.load(reopenedA)
        let preserved = try await b.load(bID)
        XCTAssertNil(deleted)
        XCTAssertEqual(preserved?.fields["value"], "B")
    }

    func testAccountChangeRejectsOldIdentityAndPreservesNewAccountValue() async throws {
        let backend = ExternalIdentityFakeBackend(account: "old")
        let sut = try coordinator(backend)
        _ = try await sut.activate()
        let old = try await sut.identity(localID: "item")
        try await sut.save(old, fields: ["value": "old"])
        await backend.setAccount("new")
        let changed = try await sut.accountDidChange()
        XCTAssertEqual(changed.accountIdentifier, "new")
        await XCTAssertThrowsExternal(.staleGeneration) { try await sut.load(old) }
        let new = try await sut.identity(localID: "item")
        try await sut.save(new, fields: ["value": "new"])
        let result = try await sut.load(new)
        XCTAssertEqual(result?.fields["value"], "new")
    }

    func testLateResultAfterAccountChangeIsRejected() async throws {
        let backend = ExternalIdentityFakeBackend(account: "old")
        let sut = try coordinator(backend)
        _ = try await sut.activate()
        let old = try await sut.identity(localID: "slow")
        try await sut.save(old, fields: ["value": "old"])
        await backend.holdNextLoad()
        let late = Task { try await sut.load(old) }
        await backend.waitUntilLoadIsHeld()
        await backend.setAccount("new")
        _ = try await sut.accountDidChange()
        await backend.releaseLoad()
        await XCTAssertThrowsExternal(.staleGeneration) { try await late.value }
    }

    func testDeactivateRejectsLateResult() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account")
        let sut = try coordinator(backend)
        _ = try await sut.activate()
        let identity = try await sut.identity(localID: "slow")
        try await sut.save(identity, fields: ["value": "kept"])
        await backend.holdNextLoad()
        let late = Task { try await sut.load(identity) }
        await backend.waitUntilLoadIsHeld()
        await sut.deactivate(); await backend.releaseLoad()
        await XCTAssertThrowsExternal(.staleGeneration) { try await late.value }
    }

    func testActivationFailureCanRecoverWithoutAffectingOtherOwner() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-a"), container: scope, backend: backend)
        let b = MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-b"), container: scope, backend: backend)
        _ = try await b.activate()
        let bID = try await b.identity(localID: "same")
        try await b.save(bID, fields: ["value": "B"])
        await backend.failNextAccountLookup()
        await XCTAssertThrowsExternal(nil) { try await a.activate() }
        _ = try await a.activate()
        let preserved = try await b.load(bID)
        XCTAssertEqual(preserved?.fields["value"], "B")
    }

    @MainActor
    func testManagementRemovalStopsADeletesItsSnapshotAndPreservesB() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = MiniAppExternalIdentityFeature(id: MiniAppID("owner-a"), container: scope, backend: backend)
        let b = MiniAppExternalIdentityFeature(id: MiniAppID("owner-b"), container: scope, backend: backend)
        let suite = "ExternalIdentityManagement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = MiniAppManagement(registrations: [
            .init(id: a.id, lifetime: a.lifetime, removal: a.removal, externalAccess: a.externalAccess),
            .init(id: b.id, lifetime: b.lifetime, removal: b.removal, externalAccess: b.externalAccess),
        ], defaults: defaults, consents: .init(defaults: defaults), coordinator: .init())
        try await a.lifetime.start(); try await b.lifetime.start()
        let bRuntime = b.lifetime.runtime
        let oldA = try await a.coordinator.identity(localID: "same")
        let bID = try await b.coordinator.identity(localID: "same")
        try await a.coordinator.save(oldA, fields: ["value": "A"])
        try await b.coordinator.save(bID, fields: ["value": "B"])
        try await manager.remove(a.id)
        XCTAssertTrue(b.lifetime.runtime === bRuntime)
        do { _ = try await a.coordinator.load(oldA); XCTFail("Expected stale generation") }
        catch let error as MiniAppExternalIdentityError { XCTAssertEqual(error, .staleGeneration) }
        let preserved = try await b.coordinator.load(bID)
        XCTAssertEqual(preserved?.fields["value"], "B")
        try await manager.enable(a.id); try await a.lifetime.start()
        let newA = try await a.coordinator.identity(localID: "same")
        XCTAssertNotEqual(oldA.account.generation, newA.account.generation)
        let removed = try await a.coordinator.load(newA)
        XCTAssertNil(removed)
        await b.lifetime.stop(); await a.lifetime.stop()
    }

    @MainActor
    func testAccountObserverBelongsToRuntimeAndDoesNotReactivateAfterStop() async throws {
        let backend = ExternalIdentityFakeBackend(account: "old")
        let feature = MiniAppExternalIdentityFeature(id: MiniAppID("owner-a"),
            container: try .init(identifier: "iCloud.test"), backend: backend)
        try await feature.lifetime.start()
        await backend.setAccount("new"); await backend.emitAccountChange()
        var changed: MiniAppExternalRecordIdentity?
        for _ in 0..<100 {
            if let value = try? await feature.coordinator.identity(localID: "same"),
               value.account.accountIdentifier == "new" { changed = value; break }
            await Task.yield()
        }
        XCTAssertEqual(changed?.account.accountIdentifier, "new")
        await feature.lifetime.stop()
        await backend.setAccount("later"); await backend.emitAccountChange(); await Task.yield()
        do { _ = try await feature.coordinator.identity(localID: "same"); XCTFail("Stopped feature reactivated") }
        catch let error as MiniAppExternalIdentityError { XCTAssertEqual(error, .inactive) }
    }

    @MainActor
    func testClosedRuntimeNeverLeavesAnActiveAccountRegistration() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account")
        let coordinator = try coordinator(backend)
        let runtime = MiniAppRuntime(); await runtime.shutdown()
        do { try await coordinator.connect(to: runtime); XCTFail("Closed runtime connected") } catch {}
        let lookups = await backend.accountLookupCount
        XCTAssertEqual(lookups, 0)
        do { _ = try await coordinator.identity(localID: "same"); XCTFail("Account remained active") }
        catch let error as MiniAppExternalIdentityError { XCTAssertEqual(error, .inactive) }
    }

    @MainActor
    func testManagementRemovalRejectsSnapshotAfterAccountSwitchAndRetriesOriginalAccount() async throws {
        let backend = ExternalIdentityFakeBackend(account: "account-a")
        let scope = try MiniAppExternalContainer(identifier: "iCloud.test")
        let a = MiniAppExternalIdentityFeature(id: MiniAppID("owner-a"), container: scope, backend: backend)
        let b = MiniAppExternalIdentityFeature(id: MiniAppID("owner-b"), container: scope, backend: backend)
        let suite = "ExternalIdentityAccountSwitch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let switcher = ExternalIdentityAccountSwitcher()
        let manager = MiniAppManagement(registrations: [
            .init(id: a.id, lifetime: a.lifetime, removal: a.removal, externalAccess: a.externalAccess,
                  unregister: {
                      if switcher.take() { await backend.setAccount("account-b") }
                  }),
            .init(id: b.id, lifetime: b.lifetime, removal: b.removal, externalAccess: b.externalAccess),
        ], defaults: defaults, consents: .init(defaults: defaults), coordinator: .init())
        try await a.lifetime.start(); try await b.lifetime.start()
        let aID = try await a.coordinator.identity(localID: "same")
        let bID = try await b.coordinator.identity(localID: "same")
        try await a.coordinator.save(aID, fields: ["value": "A"])
        try await b.coordinator.save(bID, fields: ["value": "B"])
        do { try await manager.remove(a.id); XCTFail("Wrong account zone was deleted") } catch {}
        XCTAssertEqual(manager.failures[a.id]?.stage, .deletingData)
        XCTAssertEqual(manager.status(for: a.id), .removing)
        await backend.setAccount("account-a")
        let retainedA = try await backend.load(aID)
        let retainedB = try await backend.load(bID)
        XCTAssertEqual(retainedA?.fields["value"], "A")
        XCTAssertEqual(retainedB?.fields["value"], "B")
        try await manager.remove(a.id)
        XCTAssertEqual(manager.status(for: a.id), .removed)
        let finalB = try await backend.load(bID)
        XCTAssertEqual(finalB?.fields["value"], "B")
        await b.lifetime.stop()
    }

    private func coordinator(_ backend: ExternalIdentityFakeBackend) throws -> MiniAppExternalIdentityCoordinator {
        MiniAppExternalIdentityCoordinator(owner: MiniAppID("owner-a"),
            container: try .init(identifier: "iCloud.test"), backend: backend)
    }
}

@MainActor
private final class ExternalIdentityAccountSwitcher {
    private var pending = true
    func take() -> Bool { defer { pending = false }; return pending }
}

private actor ExternalIdentityFakeBackend: MiniAppExternalIdentityBackend {
    enum Failure: Error { case injected, wrongAccount }
    private var account: String
    private var rows: [MiniAppExternalPersistentRecordKey: [String: String]] = [:]
    private var failAccount = false
    private var shouldHoldLoad = false
    private var heldLoad: CheckedContinuation<Void, Never>?
    private var holdObserved: CheckedContinuation<Void, Never>?
    private var accountChangeContinuations: [AsyncStream<Void>.Continuation] = []
    private(set) var accountLookupCount = 0

    init(account: String) { self.account = account }
    func setAccount(_ value: String) { account = value }
    func failNextAccountLookup() { failAccount = true }
    func holdNextLoad() { shouldHoldLoad = true }
    func waitUntilLoadIsHeld() async {
        if heldLoad == nil { await withCheckedContinuation { holdObserved = $0 } }
    }
    func releaseLoad() { heldLoad?.resume(); heldLoad = nil }

    func currentAccountIdentifier(in container: MiniAppExternalContainer) async throws -> String {
        accountLookupCount += 1
        if failAccount { failAccount = false; throw Failure.injected }
        return account
    }
    func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? {
        try validate(identity.account)
        if shouldHoldLoad {
            shouldHoldLoad = false
            await withCheckedContinuation { continuation in
                heldLoad = continuation; holdObserved?.resume(); holdObserved = nil
            }
        }
        return rows[MiniAppExternalPersistentRecordKey(identity)].map {
            MiniAppExternalRecord(identity: identity, fields: $0)
        }
    }
    func save(_ record: MiniAppExternalRecord) async throws {
        try validate(record.identity.account)
        let key = MiniAppExternalPersistentRecordKey(record.identity)
        rows[key, default: [:]].merge(record.fields) { _, new in new }
    }
    func delete(_ identity: MiniAppExternalRecordIdentity) async throws {
        try validate(identity.account)
        rows[MiniAppExternalPersistentRecordKey(identity)] = nil
    }
    func ensureSubscription(for account: MiniAppExternalAccount) async throws { try validate(account) }
    func deleteOwnedData(for account: MiniAppExternalAccount) async throws {
        try validate(account)
        rows = rows.filter { key, _ in
            key.owner != account.owner || key.container != account.container
                || key.accountIdentifier != account.accountIdentifier
        }
    }
    func cancelOperations(owner: MiniAppID) async { releaseLoad() }
    func accountChanges() async -> AsyncStream<Void> {
        let pair = AsyncStream<Void>.makeStream()
        accountChangeContinuations.append(pair.continuation)
        return pair.stream
    }
    func emitAccountChange() { accountChangeContinuations.forEach { $0.yield(()) } }
    private func validate(_ expected: MiniAppExternalAccount) throws {
        guard expected.accountIdentifier == account else { throw Failure.wrongAccount }
    }
}

private func XCTAssertThrowsExternal<T>(_ expected: MiniAppExternalIdentityError?,
    _ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await operation(); XCTFail("Expected error", file: file, line: line) }
    catch let error as MiniAppExternalIdentityError {
        if let expected { XCTAssertEqual(error, expected, file: file, line: line) }
    } catch { if expected != nil { XCTFail("Unexpected error: \(error)", file: file, line: line) } }
}
