#if canImport(CloudKit)
import CloudKit
import Foundation

/// Native adapter for a container explicitly created by an entitled host.
/// Merely constructing a Feature or diagnostic host never calls CKContainer().
public actor CloudKitExternalIdentityBackend: MiniAppExternalIdentityBackend {
    private let container: CKContainer
    private let recordType: String
    private var operations: [MiniAppID: [UUID: CloudKitOwnedOperation]] = [:]

    public init(container: CKContainer, recordType: String = "JibunKitExternalData") {
        self.container = container; self.recordType = recordType
    }

    public func currentAccountIdentifier(in scope: MiniAppExternalContainer) async throws -> String {
        try validate(scope)
        let status = try await container.accountStatus()
        guard status == .available else { throw MiniAppExternalIdentityError.accountUnavailable }
        return try await container.userRecordID().recordName
    }

    public func load(_ identity: MiniAppExternalRecordIdentity) async throws -> MiniAppExternalRecord? {
        try validate(identity.account.container)
        let database = database(identity.account.container)
        let id = CloudKitExternalIdentityNames.recordID(for: identity)
        let container = container
        return try await run(owner: identity.account.owner) {
            try await Self.verify(account: identity.account, container: container)
            try Task.checkCancellation()
            do {
                let record = try await database.record(for: id)
                try await Self.verify(account: identity.account, container: container)
                try Task.checkCancellation()
                var fields: [String: String] = [:]
                for key in record.allKeys() { if let value = record[key] as? String { fields[key] = value } }
                return .init(identity: identity, fields: fields)
            } catch let error as CKError where error.code == .unknownItem {
                try await Self.verify(account: identity.account, container: container)
                try Task.checkCancellation()
                return nil
            }
        }
    }

    public func save(_ value: MiniAppExternalRecord) async throws {
        try validate(value.identity.account.container)
        let database = database(value.identity.account.container)
        let id = CloudKitExternalIdentityNames.recordID(for: value.identity)
        let recordType = recordType
        let container = container
        try await run(owner: value.identity.account.owner) {
            try await Self.verify(account: value.identity.account, container: container)
            try Task.checkCancellation()
            try await Self.ensureZone(value.identity.account, database: database)
            try await Self.verify(account: value.identity.account, container: container)
            try Task.checkCancellation()
            let record: CKRecord
            do { record = try await database.record(for: id) }
            catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: recordType, recordID: id)
            }
            try await Self.verify(account: value.identity.account, container: container)
            try Task.checkCancellation()
            // Preserve the fetched change tag and all fields not owned by this update.
            for (key, field) in value.fields { record[key] = field as CKRecordValue }
            _ = try await database.save(record)
            try await Self.verify(account: value.identity.account, container: container)
            try Task.checkCancellation()
        }
    }

    public func delete(_ identity: MiniAppExternalRecordIdentity) async throws {
        try validate(identity.account.container)
        let database = database(identity.account.container)
        let id = CloudKitExternalIdentityNames.recordID(for: identity)
        let container = container
        try await run(owner: identity.account.owner) {
            try await Self.verify(account: identity.account, container: container)
            try Task.checkCancellation()
            do { _ = try await database.deleteRecord(withID: id) }
            catch let error as CKError where error.code == .unknownItem {}
            try await Self.verify(account: identity.account, container: container)
            try Task.checkCancellation()
        }
    }

    public func ensureSubscription(for account: MiniAppExternalAccount) async throws {
        try validate(account.container)
        let database = database(account.container)
        let container = container
        try await run(owner: account.owner) {
            try await Self.verify(account: account, container: container)
            try Task.checkCancellation()
            try await Self.ensureZone(account, database: database)
            try await Self.verify(account: account, container: container)
            try Task.checkCancellation()
            let identifier = CloudKitExternalIdentityNames.subscriptionID(for: account)
            do {
                _ = try await database.subscription(for: identifier)
                try await Self.verify(account: account, container: container)
                try Task.checkCancellation()
                return
            }
            catch let error as CKError where error.code == .unknownItem {}
            try await Self.verify(account: account, container: container)
            try Task.checkCancellation()
            let subscription = CKRecordZoneSubscription(
                zoneID: CloudKitExternalIdentityNames.zoneID(for: account), subscriptionID: identifier)
            _ = try await database.save(subscription)
            try await Self.verify(account: account, container: container)
            try Task.checkCancellation()
        }
    }

    public func deleteOwnedData(for account: MiniAppExternalAccount) async throws {
        try validate(account.container)
        let database = database(account.container)
        let container = container
        try await run(owner: account.owner) {
            try await Self.verify(account: account, container: container)
            try Task.checkCancellation()
            do { _ = try await database.deleteRecordZone(
                withID: CloudKitExternalIdentityNames.zoneID(for: account)) }
            catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {}
            try await Self.verify(account: account, container: container)
            try Task.checkCancellation()
        }
    }

    public func cancelOperations(owner: MiniAppID) async {
        let owned = Array(operations[owner, default: [:]].values)
        owned.forEach { $0.cancel() }
        for operation in owned { await operation.wait() }
    }

    public func accountChanges() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observation = CloudKitAccountChangeObservation(continuation: continuation)
            continuation.onTermination = { _ in observation.cancel() }
        }
    }

    private func database(_ scope: MiniAppExternalContainer) -> CKDatabase {
        switch scope.database {
        case .privateDatabase: container.privateCloudDatabase
        case .sharedDatabase: container.sharedCloudDatabase
        case .publicDatabase: container.publicCloudDatabase
        }
    }
    private func validate(_ scope: MiniAppExternalContainer) throws {
        guard scope.identifier == container.containerIdentifier else {
            throw MiniAppExternalIdentityError.invalidIdentity
        }
        guard scope.database == .privateDatabase else {
            throw MiniAppExternalIdentityError.backend(
                "CloudKit native adapter supports privateDatabase custom zones only")
        }
    }
    private static func ensureZone(_ account: MiniAppExternalAccount, database: CKDatabase) async throws {
        let zone = CKRecordZone(zoneID: CloudKitExternalIdentityNames.zoneID(for: account))
        let results = try await database.modifyRecordZones(saving: [zone], deleting: [])
        guard let result = results.saveResults[zone.zoneID] else {
            throw MiniAppExternalIdentityError.backend("CloudKit returned no result for the owned record zone")
        }
        _ = try result.get()
    }

    private static func verify(account: MiniAppExternalAccount, container: CKContainer) async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw MiniAppExternalIdentityError.accountUnavailable }
        let current = try await container.userRecordID().recordName
        guard current == account.accountIdentifier else {
            throw MiniAppExternalIdentityError.staleGeneration
        }
    }

    private func run<Value: Sendable>(owner: MiniAppID,
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let task = Task { try await operation() }, id = UUID()
        operations[owner, default: [:]][id] = CloudKitOwnedOperation(task)
        defer { operations[owner]?[id] = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

/// Namespace helper for Features that need richer CKRecord fields or operations
/// than the small String-field example adapter provides.
public enum CloudKitExternalIdentityNames {
    public static func zoneID(for account: MiniAppExternalAccount) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "jibunkit.\(account.owner.storageNamespace)",
                        ownerName: CKCurrentUserDefaultName)
    }
    public static func recordID(for identity: MiniAppExternalRecordIdentity) -> CKRecord.ID {
        CKRecord.ID(recordName: identity.recordName, zoneID: zoneID(for: identity.account))
    }
    public static func subscriptionID(for account: MiniAppExternalAccount) -> String {
        "jibunkit.\(account.owner.storageNamespace).changes"
    }
}

private final class CloudKitOwnedOperation: @unchecked Sendable {
    let cancel: @Sendable () -> Void
    let wait: @Sendable () async -> Void
    init<Value: Sendable>(_ task: Task<Value, Error>) {
        cancel = { task.cancel() }; wait = { _ = await task.result }
    }
}

private final class CloudKitAccountChangeObservation: @unchecked Sendable {
    private let center = NotificationCenter.default
    private var token: NSObjectProtocol?
    init(continuation: AsyncStream<Void>.Continuation) {
        token = center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { _ in
            continuation.yield(())
        }
    }
    func cancel() {
        if let token { center.removeObserver(token); self.token = nil }
    }
    deinit { cancel() }
}
#endif
