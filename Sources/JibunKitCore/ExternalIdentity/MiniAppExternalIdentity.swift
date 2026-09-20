import Foundation

public struct MiniAppExternalContainer: Hashable, Sendable {
    public enum Database: String, Hashable, Sendable { case privateDatabase, sharedDatabase, publicDatabase }
    public let identifier: String
    public let database: Database

    public init(identifier: String, database: Database = .privateDatabase) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MiniAppExternalIdentityError.invalidIdentity
        }
        self.identifier = identifier
        self.database = database
    }
}

/// The complete ownership boundary for one external account generation.
/// `accountIdentifier` is backend supplied and must not be displayed as a user name.
public struct MiniAppExternalAccount: Hashable, Sendable {
    public let owner: MiniAppID
    public let container: MiniAppExternalContainer
    public let accountIdentifier: String
    public let generation: UUID

    public init(owner: MiniAppID, container: MiniAppExternalContainer,
                accountIdentifier: String, generation: UUID = UUID()) throws {
        guard owner.isValid, !accountIdentifier.isEmpty else { throw MiniAppExternalIdentityError.invalidIdentity }
        self.owner = owner; self.container = container
        self.accountIdentifier = accountIdentifier; self.generation = generation
    }
}

/// A Feature-local ID is never sent to a backend without the owner/account namespace.
public struct MiniAppExternalRecordIdentity: Hashable, Sendable {
    public let account: MiniAppExternalAccount
    public let localID: String

    public init(account: MiniAppExternalAccount, localID: String) throws {
        guard !localID.isEmpty else { throw MiniAppExternalIdentityError.invalidIdentity }
        self.account = account; self.localID = localID
    }

    public var zoneName: String { "jibunkit.\(account.owner.storageNamespace)" }
    public var recordName: String { Self.encode(localID) }
    public var subscriptionID: String { "jibunkit.\(account.owner.storageNamespace).changes" }

    private static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
    }
}

/// Stable backend key. Runtime/account generations are admission tokens and are
/// intentionally excluded from persisted identity.
public struct MiniAppExternalPersistentRecordKey: Hashable, Sendable {
    public let owner: MiniAppID
    public let container: MiniAppExternalContainer
    public let accountIdentifier: String
    public let localID: String

    public init(_ identity: MiniAppExternalRecordIdentity) {
        owner = identity.account.owner; container = identity.account.container
        accountIdentifier = identity.account.accountIdentifier; localID = identity.localID
    }
}

public struct MiniAppExternalRecord: Equatable, Sendable {
    public let identity: MiniAppExternalRecordIdentity
    public let fields: [String: String]
    public init(identity: MiniAppExternalRecordIdentity, fields: [String: String]) {
        self.identity = identity; self.fields = fields
    }
}

public enum MiniAppExternalIdentityError: Error, Equatable, Sendable {
    case invalidIdentity
    case inactive
    case accountUnavailable
    case staleGeneration
    case backend(String)
}

/// Narrow data boundary, deliberately not a general synchronization engine.
public protocol MiniAppExternalIdentityBackend: Sendable {
    func currentAccountIdentifier(in container: MiniAppExternalContainer) async throws -> String
    func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord?
    func save(_ record: MiniAppExternalRecord) async throws
    func delete(_ identity: MiniAppExternalRecordIdentity) async throws
    func ensureSubscription(for account: MiniAppExternalAccount) async throws
    func deleteOwnedData(for account: MiniAppExternalAccount) async throws
    func cancelOperations(owner: MiniAppID) async
    func accountChanges() async -> AsyncStream<Void>
}

/// One instance belongs to one Feature. Awaited backend results are committed only
/// while the exact activation/account generation is still current.
public actor MiniAppExternalIdentityCoordinator {
    public let owner: MiniAppID
    public let container: MiniAppExternalContainer
    private let backend: any MiniAppExternalIdentityBackend
    private var session: UUID?
    private var transition = UUID()
    private var current: MiniAppExternalAccount?
    private var deletionSnapshot: MiniAppExternalAccount?
    private var operations: [UUID: MiniAppExternalOwnedOperation] = [:]

    public init(owner: MiniAppID, container: MiniAppExternalContainer,
                backend: any MiniAppExternalIdentityBackend) {
        precondition(owner.isValid)
        self.owner = owner; self.container = container; self.backend = backend
    }

    @discardableResult
    public func activate() async throws -> MiniAppExternalAccount {
        let proposed = UUID()
        session = proposed
        return try await transitionAccount(session: proposed)
    }

    /// Re-reads the native account. A change invalidates every handle from the old account.
    @discardableResult
    public func accountDidChange() async throws -> MiniAppExternalAccount {
        guard let session else { throw MiniAppExternalIdentityError.inactive }
        return try await transitionAccount(session: session)
    }

    public func identity(localID: String) throws -> MiniAppExternalRecordIdentity {
        guard let current else { throw MiniAppExternalIdentityError.inactive }
        return try MiniAppExternalRecordIdentity(account: current, localID: localID)
    }

    public func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? {
        try validate(identity); let expected = identity.account
        return try await run(expected: expected) { [backend] in try await backend.load(identity) }
    }

    public func save(_ identity: MiniAppExternalRecordIdentity, fields: [String: String]) async throws {
        try validate(identity); let expected = identity.account
        try await run(expected: expected) { [backend] in
            try await backend.save(.init(identity: identity, fields: fields))
        }
    }

    public func delete(_ identity: MiniAppExternalRecordIdentity) async throws {
        try validate(identity); let expected = identity.account
        try await run(expected: expected) { [backend] in try await backend.delete(identity) }
    }

    /// Removes only this owner's zone/account generation. Other owners are not enumerable here.
    public func removeOwnedData() async throws {
        guard session == nil, current == nil else { throw MiniAppExternalIdentityError.inactive }
        let snapshot: MiniAppExternalAccount
        if let deletionSnapshot { snapshot = deletionSnapshot }
        else {
            do {
                let identifier = try await backend.currentAccountIdentifier(in: container)
                snapshot = try MiniAppExternalAccount(owner: owner, container: container,
                                                      accountIdentifier: identifier)
                deletionSnapshot = snapshot
            } catch { throw map(error) }
        }
        do { try await backend.deleteOwnedData(for: snapshot); deletionSnapshot = nil }
        catch { throw map(error) }
    }

    public func deactivate() async {
        await deactivate(session: session)
    }

    public func connect(to runtime: MiniAppRuntime) async throws {
        let proposed = UUID()
        try await MainActor.run {
            try runtime.onShutdownAsync { [weak self] in await self?.deactivate(session: proposed) }
        }
        session = proposed
        let runtimeClosed = await MainActor.run { runtime.isClosed }
        guard !runtimeClosed else {
            await deactivate(session: proposed)
            throw MiniAppRuntime.Failure.closed
        }
        do { _ = try await transitionAccount(session: proposed) }
        catch { await deactivate(session: proposed); throw error }
        let changes = await backend.accountChanges()
        do {
            try await MainActor.run {
                _ = try runtime.start { [weak self] in
                    for await _ in changes {
                        guard !Task.isCancelled else { return }
                        _ = try? await self?.accountDidChange()
                    }
                }
            }
        } catch {
            await deactivate(session: proposed)
            throw error
        }
    }

    private func transitionAccount(session expectedSession: UUID) async throws -> MiniAppExternalAccount {
        guard session == expectedSession else { throw MiniAppExternalIdentityError.staleGeneration }
        transition = UUID(); let reservation = transition
        current = nil
        await cancelAndJoinOperations()
        try Task.checkCancellation()
        guard session == expectedSession, transition == reservation else {
            throw MiniAppExternalIdentityError.staleGeneration
        }
        let task = Task { [backend, container, owner] in
            let identifier = try await backend.currentAccountIdentifier(in: container)
            guard !identifier.isEmpty else { throw MiniAppExternalIdentityError.accountUnavailable }
            let account = try MiniAppExternalAccount(owner: owner, container: container,
                                                     accountIdentifier: identifier)
            try await backend.ensureSubscription(for: account)
            return account
        }
        let id = UUID(); operations[id] = MiniAppExternalOwnedOperation(task)
        defer { operations[id] = nil }
        let account: MiniAppExternalAccount
        do {
            account = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch {
            guard session == expectedSession, transition == reservation else {
                throw MiniAppExternalIdentityError.staleGeneration
            }
            throw map(error)
        }
        guard session == expectedSession, transition == reservation else {
            throw MiniAppExternalIdentityError.staleGeneration
        }
        current = account; deletionSnapshot = account
        return account
    }

    private func run<Value: Sendable>(
        expected: MiniAppExternalAccount,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        guard current == expected, session != nil else { throw MiniAppExternalIdentityError.staleGeneration }
        let task = Task { try await operation() }
        let id = UUID(); operations[id] = MiniAppExternalOwnedOperation(task)
        defer { operations[id] = nil }
        do {
            let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard current == expected, session != nil else { throw MiniAppExternalIdentityError.staleGeneration }
            return value
        } catch {
            guard current == expected, session != nil else { throw MiniAppExternalIdentityError.staleGeneration }
            throw map(error)
        }
    }

    private func deactivate(session expected: UUID?) async {
        guard let expected, session == expected else { return }
        session = nil; current = nil; transition = UUID()
        await cancelAndJoinOperations()
    }

    private func cancelAndJoinOperations() async {
        let owned = Array(operations.values)
        owned.forEach { $0.cancel() }
        await backend.cancelOperations(owner: owner)
        for operation in owned { await operation.wait() }
    }

    private func map(_ error: Error) -> MiniAppExternalIdentityError {
        if let error = error as? MiniAppExternalIdentityError { return error }
        return .backend(String(describing: error))
    }

    private func validate(_ identity: MiniAppExternalRecordIdentity) throws {
        guard identity.account.owner == owner,
              identity.account.container == container else { throw MiniAppExternalIdentityError.invalidIdentity }
        guard identity.account == current else { throw MiniAppExternalIdentityError.staleGeneration }
    }
}

/// Safe diagnostic default. It performs no OS communication and must never be
/// reported as a successful CloudKit connection.
public struct UnavailableExternalIdentityBackend: MiniAppExternalIdentityBackend {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public func currentAccountIdentifier(in container: MiniAppExternalContainer) async throws -> String {
        throw MiniAppExternalIdentityError.backend(reason)
    }
    public func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? { throw failure }
    public func save(_ record: MiniAppExternalRecord) async throws { throw failure }
    public func delete(_ identity: MiniAppExternalRecordIdentity) async throws { throw failure }
    public func ensureSubscription(for account: MiniAppExternalAccount) async throws { throw failure }
    public func deleteOwnedData(for account: MiniAppExternalAccount) async throws { throw failure }
    public func cancelOperations(owner: MiniAppID) async {}
    public func accountChanges() async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    private var failure: MiniAppExternalIdentityError { .backend(reason) }
}

private final class MiniAppExternalOwnedOperation: @unchecked Sendable {
    private let cancellation: @Sendable () -> Void
    private let completion: @Sendable () async -> Void
    init<Value: Sendable>(_ task: Task<Value, Error>) {
        cancellation = { task.cancel() }
        completion = { _ = await task.result }
    }
    func cancel() { cancellation() }
    func wait() async { await completion() }
}
