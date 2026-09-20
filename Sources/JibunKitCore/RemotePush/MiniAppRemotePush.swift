import CoreFoundation
import Foundation

public struct MiniAppRemotePushIdentity: Sendable, Equatable, Hashable {
    public let server: String
    public let account: String
    public init(server: String, account: String) throws {
        guard !server.isEmpty, !account.isEmpty else { throw MiniAppRemotePushFailure.invalidIdentity }
        self.server = server; self.account = account
    }
}

public enum MiniAppRemotePushFailure: Error, Sendable, Equatable {
    case invalidIdentity, closedRuntime, invalidPayload
}

public enum MiniAppRemotePushRegistrationEvent: Sendable, Equatable {
    case tokenChanged(token: Data, identity: MiniAppRemotePushIdentity, generation: UUID)
    case registrationFailed(message: String, generation: UUID)
    case ownerUnregistered(identity: MiniAppRemotePushIdentity)
}

public enum MiniAppRemotePushFetchResult: Int, Sendable, Equatable {
    case noData = 0, newData = 1, failed = 2
}

/// A lossless, Sendable snapshot of the JSON value types accepted by APNs.
public indirect enum MiniAppRemotePushValue: Sendable, Equatable {
    case string(String), integer(Int64), unsignedInteger(UInt64), number(Double), bool(Bool)
    case array([MiniAppRemotePushValue])
    case object([String: MiniAppRemotePushValue])
    case null

    fileprivate init(any value: Any) throws {
        switch value {
        case let value as String: self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                let type = String(cString: value.objCType)
                if type == "f" || type == "d" {
                    let number = value.doubleValue
                    guard number.isFinite else { throw MiniAppRemotePushFailure.invalidPayload }
                    self = .number(number)
                } else if type.first == "Q" || type.first == "L" || type.first == "I" || type.first == "S" || type.first == "C" {
                    self = .unsignedInteger(value.uint64Value)
                } else {
                    self = .integer(value.int64Value)
                }
            }
        case let value as [Any]: self = .array(try value.map { try Self(any: $0) })
        case let value as [String: Any]: self = .object(try value.mapValues { try Self(any: $0) })
        case _ as NSNull: self = .null
        default: throw MiniAppRemotePushFailure.invalidPayload
        }
    }

    fileprivate var objectValue: Any {
        switch self {
        case .string(let value): value
        case .integer(let value): value
        case .unsignedInteger(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .array(let value): value.map { $0.objectValue }
        case .object(let value): value.mapValues { $0.objectValue }
        case .null: NSNull()
        }
    }
}

public struct MiniAppRemotePushMessage: Sendable, Equatable {
    public let owner: MiniAppID
    public let destination: String?
    public let payload: [String: MiniAppRemotePushValue]
    public init(owner: MiniAppID, destination: String?, payload: [String: MiniAppRemotePushValue]) {
        self.owner = owner; self.destination = destination; self.payload = payload
    }
    public func jsonObject() -> [String: Any] { payload.mapValues { $0.objectValue } }
}

@MainActor
public final class MiniAppRemotePushCoordinator {
    public static let shared = MiniAppRemotePushCoordinator()
    public typealias RegistrationHandler = @MainActor @Sendable (MiniAppRemotePushRegistrationEvent) async -> Void
    public typealias DeliveryHandler = @MainActor @Sendable (MiniAppRemotePushMessage) async -> MiniAppRemotePushFetchResult

    @MainActor private final class Registration {
        let lease: UUID
        var identity: MiniAppRemotePushIdentity
        var generation: UUID?
        var runtime: MiniAppRuntime?
        var coldStart: (@MainActor @Sendable () async -> Bool)?
        var registration: RegistrationHandler
        var delivery: DeliveryHandler
        var registrationTail: Task<Void, Never>?
        init(lease: UUID, identity: MiniAppRemotePushIdentity,
             registration: @escaping RegistrationHandler, delivery: @escaping DeliveryHandler) {
            self.lease = lease; self.identity = identity
            self.registration = registration; self.delivery = delivery
        }
    }

    private var token: Data?
    private var tokenRevision: UInt64 = 0
    private var registrationFailure: String?
    private var registrations: [MiniAppID: Registration] = [:]
    public init() {}
    public var appToken: Data? { token }
    public var registeredOwners: Set<MiniAppID> { Set(registrations.keys) }

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        guard token != deviceToken || registrationFailure != nil else { return }
        token = deviceToken; registrationFailure = nil; tokenRevision &+= 1
        for (owner, value) in registrations {
            guard let generation = value.generation else { continue }
            enqueue(.tokenChanged(token: deviceToken, identity: value.identity, generation: generation),
                    owner: owner, entry: value, revision: tokenRevision)
        }
    }

    public func didFailToRegisterForRemoteNotifications(_ error: Error) {
        token = nil
        registrationFailure = String(describing: error)
        tokenRevision &+= 1
        for (owner, value) in registrations {
            guard let generation = value.generation else { continue }
            enqueue(.registrationFailed(message: registrationFailure!, generation: generation),
                    owner: owner, entry: value, revision: tokenRevision)
        }
    }

    fileprivate func prepare(owner: MiniAppID, lease: UUID, identity: MiniAppRemotePushIdentity,
                             registration: @escaping RegistrationHandler,
                             delivery: @escaping DeliveryHandler,
                             coldStart: @escaping @MainActor @Sendable () async -> Bool) {
        reservation(owner: owner, lease: lease, identity: identity,
                    registration: registration, delivery: delivery).coldStart = coldStart
    }

    fileprivate func activate(owner: MiniAppID, lease: UUID, generation: UUID,
                              identity: MiniAppRemotePushIdentity, runtime: MiniAppRuntime,
                              registration: @escaping RegistrationHandler,
                              delivery: @escaping DeliveryHandler) {
        precondition(!runtime.isClosed)
        let entry = reservation(owner: owner, lease: lease, identity: identity,
                                registration: registration, delivery: delivery)
        entry.generation = generation; entry.runtime = runtime
        if let token {
            enqueue(.tokenChanged(token: token, identity: identity, generation: generation),
                    owner: owner, entry: entry, revision: tokenRevision)
        } else if let registrationFailure {
            enqueue(.registrationFailed(message: registrationFailure, generation: generation),
                    owner: owner, entry: entry, revision: tokenRevision)
        }
    }

    private func reservation(owner: MiniAppID, lease: UUID, identity: MiniAppRemotePushIdentity,
                             registration: @escaping RegistrationHandler,
                             delivery: @escaping DeliveryHandler) -> Registration {
        if let current = registrations[owner], current.lease == lease {
            current.identity = identity; current.registration = registration; current.delivery = delivery
            return current
        }
        let created = Registration(lease: lease, identity: identity,
                                   registration: registration, delivery: delivery)
        registrations[owner] = created
        return created
    }

    fileprivate func disconnect(owner: MiniAppID, lease: UUID, generation: UUID) {
        guard let value = registrations[owner], value.lease == lease, value.generation == generation else { return }
        value.generation = nil; value.runtime = nil; value.registrationTail = nil
        if value.coldStart == nil { registrations.removeValue(forKey: owner) }
    }

    fileprivate func unregister(owner: MiniAppID, lease: UUID) -> Bool {
        guard registrations[owner]?.lease == lease else { return false }
        registrations.removeValue(forKey: owner)
        return true
    }

    private func enqueue(_ event: MiniAppRemotePushRegistrationEvent, owner: MiniAppID,
                         entry: Registration, revision: UInt64) {
        guard let runtime = entry.runtime, !runtime.isClosed, let generation = entry.generation else { return }
        let previous = entry.registrationTail, lease = entry.lease, handler = entry.registration
        entry.registrationTail = try? runtime.start { [weak self] in
            await previous?.value
            guard !Task.isCancelled,
                  await self?.accepts(owner: owner, lease: lease, generation: generation, revision: revision) == true
            else { return }
            await handler(event)
        }
    }

    private func accepts(owner: MiniAppID, lease: UUID, generation: UUID, revision: UInt64) -> Bool {
        guard let value = registrations[owner], value.lease == lease,
              value.generation == generation, value.runtime?.isClosed == false else { return false }
        return revision == tokenRevision
    }

    func waitForRegistrationCallbacks() async {
        let tasks = registrations.values.compactMap(\.registrationTail)
        for task in tasks { await task.value }
    }

    public func deliver(userInfo: [AnyHashable: Any]) async -> MiniAppRemotePushFetchResult {
        guard let route = MiniAppNotificationRoute.candidateRoute(userInfo: userInfo),
              var entry = registrations[route.id] else { return .noData }
        let payload: [String: MiniAppRemotePushValue]
        do { payload = try Self.snapshot(userInfo) } catch { return .failed }
        if entry.runtime == nil {
            guard let coldStart = entry.coldStart, await coldStart(),
                  let started = registrations[route.id], started.lease == entry.lease else { return .noData }
            entry = started
        }
        guard let runtime = entry.runtime, !runtime.isClosed, let generation = entry.generation else { return .noData }
        let lease = entry.lease, handler = entry.delivery
        let message = MiniAppRemotePushMessage(owner: route.id, destination: route.destination, payload: payload)
        let result: MiniAppRemotePushFetchResult = await withCheckedContinuation { continuation in
            do {
                try runtime.start { [weak self] in
                    guard !Task.isCancelled,
                          await self?.isCurrent(owner: route.id, lease: lease, generation: generation) == true
                    else { continuation.resume(returning: .noData); return }
                    let output = await handler(message)
                    continuation.resume(returning: Task.isCancelled ? .noData : output)
                }
            } catch { continuation.resume(returning: .noData) }
        }
        return isCurrent(owner: route.id, lease: lease, generation: generation) ? result : .noData
    }

    private func isCurrent(owner: MiniAppID, lease: UUID, generation: UUID) -> Bool {
        guard let value = registrations[owner] else { return false }
        return value.lease == lease && value.generation == generation && value.runtime?.isClosed == false
    }

    private static func snapshot(_ userInfo: [AnyHashable: Any]) throws -> [String: MiniAppRemotePushValue] {
        var result: [String: MiniAppRemotePushValue] = [:]
        for (rawKey, value) in userInfo {
            guard let key = rawKey as? String else { throw MiniAppRemotePushFailure.invalidPayload }
            result[key] = try MiniAppRemotePushValue(any: value)
        }
        return result
    }
}

@MainActor
public final class MiniAppRemotePushService {
    public let owner: MiniAppID
    public var identity: MiniAppRemotePushIdentity
    public var onRegistration: MiniAppRemotePushCoordinator.RegistrationHandler
    public var onDelivery: MiniAppRemotePushCoordinator.DeliveryHandler
    public var onUnregister: @MainActor @Sendable (MiniAppRemotePushIdentity) async -> Void
    private let coordinator: MiniAppRemotePushCoordinator
    private let lease = UUID()
    private var generation: UUID?
    private weak var connectedRuntime: MiniAppRuntime?

    public init(owner: MiniAppID, identity: MiniAppRemotePushIdentity,
                coordinator: MiniAppRemotePushCoordinator = .shared,
                onRegistration: @escaping MiniAppRemotePushCoordinator.RegistrationHandler = { _ in },
                onDelivery: @escaping MiniAppRemotePushCoordinator.DeliveryHandler = { _ in .noData },
                onUnregister: @escaping @MainActor @Sendable (MiniAppRemotePushIdentity) async -> Void = { _ in }) {
        self.owner = owner; self.identity = identity; self.coordinator = coordinator
        self.onRegistration = onRegistration; self.onDelivery = onDelivery; self.onUnregister = onUnregister
    }

    public func prepareColdStart(lifetime: MiniAppFeatureLifetime) {
        precondition(lifetime.id == owner)
        coordinator.prepare(owner: owner, lease: lease, identity: identity,
                            registration: onRegistration, delivery: onDelivery,
                            coldStart: { [weak lifetime] in
                                guard let lifetime else { return false }
                                do { try await lifetime.start() } catch { return false }
                                return lifetime.runtime?.isClosed == false
                            })
    }

    public func connect(to runtime: MiniAppRuntime) throws {
        guard !runtime.isClosed else { throw MiniAppRemotePushFailure.closedRuntime }
        if connectedRuntime === runtime, generation != nil { return }
        let created = UUID()
        try runtime.onShutdownAsync { [weak self, coordinator, owner, lease] in
            coordinator.disconnect(owner: owner, lease: lease, generation: created)
            if self?.generation == created { self?.generation = nil; self?.connectedRuntime = nil }
        }
        generation = created; connectedRuntime = runtime
        coordinator.activate(owner: owner, lease: lease, generation: created, identity: identity,
                             runtime: runtime, registration: onRegistration, delivery: onDelivery)
    }

    /// Management-owned server cleanup. Active registration/delivery callbacks
    /// remain Runtime-owned; this distinct closure is awaited after Runtime stop.
    public func unregister() async {
        generation = nil; connectedRuntime = nil
        guard coordinator.unregister(owner: owner, lease: lease) else { return }
        await onUnregister(identity)
    }
}

public final class MiniAppRemotePushCompletionAggregator: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0, addingFinished = false, completed = false
    private var result: MiniAppRemotePushFetchResult = .noData
    private let completion: @Sendable (MiniAppRemotePushFetchResult) -> Void
    public init(completion: @escaping @Sendable (MiniAppRemotePushFetchResult) -> Void) { self.completion = completion }
    public func ticket() -> @Sendable (MiniAppRemotePushFetchResult) -> Void {
        lock.lock(); precondition(!addingFinished); pending += 1; lock.unlock()
        let once = MiniAppRemotePushOnce()
        return { [self] value in guard once.claim() else { return }; leave(value) }
    }
    public func finishAdding() {
        lock.lock(); addingFinished = true; let output = completionIfReadyLocked(); lock.unlock()
        if let output { completion(output) }
    }
    private func leave(_ value: MiniAppRemotePushFetchResult) {
        lock.lock(); if value.rawValue > result.rawValue { result = value }; pending -= 1
        let output = completionIfReadyLocked(); lock.unlock()
        if let output { completion(output) }
    }
    private func completionIfReadyLocked() -> MiniAppRemotePushFetchResult? {
        guard addingFinished, pending == 0, !completed else { return nil }
        completed = true; return result
    }
}

private final class MiniAppRemotePushOnce: @unchecked Sendable {
    private let lock = NSLock(); private var used = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; guard !used else { return false }; used = true; return true }
}
