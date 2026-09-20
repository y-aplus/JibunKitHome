import Foundation
#if os(iOS)
import CoreLocation
#endif

@MainActor
public protocol MiniAppLocationNativeClient: AnyObject {
    var authorization: MiniAppLocationAuthorization { get }
    var monitoredRegionIDs: Set<String> { get }
    func isMonitoringAvailable(for kind: MiniAppLocationMonitoringKind) -> Bool
    var maximumRegionMonitoringDistance: Double { get }
    var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)? { get set }
    #if os(iOS)
    var coreLocationHandler: (@MainActor (UUID, [CLLocation]) -> Void)? { get set }
    #endif
    func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest)
    func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID)
    func stopUpdates(generation: UUID)
    func startMonitoring(_ registration: MiniAppLocationRegistration)
    func stopMonitoring(identifier: String)
    func requestState(identifier: String)
}

public enum MiniAppLocationNativeEvent: Sendable, Equatable {
    case locations(generation: UUID, [MiniAppLocationSample])
    case authorizationChanged(MiniAppLocationAuthorization)
    case entered(identifier: String)
    case exited(identifier: String)
    case state(identifier: String, MiniAppLocationRegionState)
    case monitoringFailed(identifier: String?, message: String)
    case failed(generation: UUID?, message: String)
}

public protocol MiniAppLocationRegistrationStore: Sendable {
    func read() throws -> [MiniAppLocationRegistration]
    func write(_ registrations: [MiniAppLocationRegistration]) throws
}

public struct MiniAppUserDefaultsLocationStore: MiniAppLocationRegistrationStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "jibunkit.location.registrations") {
        self.defaults = defaults; self.key = key
    }
    public func read() throws -> [MiniAppLocationRegistration] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([MiniAppLocationRegistration].self, from: data)
    }
    public func write(_ registrations: [MiniAppLocationRegistration]) throws {
        defaults.set(try JSONEncoder().encode(registrations), forKey: key)
    }
}

public final class MiniAppLocationAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    private var suspended = false
    public init() {}
    public func setAllowed(_ allowed: Bool) { lock.lock(); value = allowed; lock.unlock() }
    public func isAllowed() -> Bool { lock.lock(); defer { lock.unlock() }; return value == true && !suspended }
    public func isClosed() -> Bool { lock.lock(); defer { lock.unlock() }; return value == false || suspended }
    public func setSuspended(_ suspended: Bool) { lock.lock(); self.suspended = suspended; lock.unlock() }
}

/// App-wide reservation and delivery boundary for Core Location's shared region pool.
/// A Feature can only remove its own identifiers; unknown/native registrations count
/// toward the system limit and are never stopped by JibunKit.
@MainActor
public final class MiniAppLocationCoordinator {
    public static let regionLimit = 20
    public static let shared = MiniAppLocationCoordinator()

    private let native: any MiniAppLocationNativeClient
    private let store: any MiniAppLocationRegistrationStore
    private var registrations: [String: MiniAppLocationRegistration] = [:]
    private struct Consumer {
        let token: UUID
        let receive: @MainActor @Sendable (MiniAppLocationEvent) -> Void
        #if os(iOS)
        var receiveCoreLocations: (@MainActor ([CLLocation], UUID) -> Void)?
        #endif
    }
    private var consumers: [MiniAppID: Consumer] = [:]
    private var coldConsumers: [MiniAppID: @MainActor @Sendable (MiniAppLocationEvent) -> Void] = [:]
    private var admissions: [MiniAppID: MiniAppLocationAdmission] = [:]
    private var updateOwners: [MiniAppID: UUID] = [:]
    public private(set) var persistenceFailure: String?

    public init(native: (any MiniAppLocationNativeClient)? = nil,
                store: any MiniAppLocationRegistrationStore = MiniAppUserDefaultsLocationStore()) {
        self.native = native ?? MiniAppCoreLocationClient()
        self.store = store
        do {
            let restored = try store.read()
            var localKeys: Set<String> = []
            for registration in restored where registration.owner.isValid && !registration.localID.isEmpty {
                let key = registration.owner.rawValue + "\u{0}" + registration.localID
                guard localKeys.insert(key).inserted else {
                    throw MiniAppLocationFailure.persistenceUnavailable("duplicate owner/localID")
                }
                registrations[registration.id] = registration
            }
        } catch {
            persistenceFailure = error.localizedDescription
        }
        self.native.eventHandler = { [weak self] event in self?.receive(event) }
        #if os(iOS)
        self.native.coreLocationHandler = { [weak self] generation, locations in
            guard let self, let owner = self.updateOwners.first(where: { $0.value == generation })?.key else { return }
            self.consumers[owner]?.receiveCoreLocations?(locations, generation)
        }
        #endif
    }

    public var authorization: MiniAppLocationAuthorization { native.authorization }
    public var allRegistrations: [MiniAppLocationRegistration] { Array(registrations.values) }

    public func prepare(owner: MiniAppID, admission: MiniAppLocationAdmission,
                        receiveCold: @escaping @MainActor @Sendable (MiniAppLocationEvent) -> Void) {
        admissions[owner] = admission
        coldConsumers[owner] = receiveCold
    }

    public func connect(owner: MiniAppID, token: UUID,
                        receive: @escaping @MainActor @Sendable (MiniAppLocationEvent) -> Void) {
        if consumers[owner]?.token != token,
           let generation = updateOwners.removeValue(forKey: owner) {
            native.stopUpdates(generation: generation)
        }
        consumers[owner] = Consumer(token: token, receive: receive)
        if let persistenceFailure { receive(.failed(generation: nil, persistenceFailure)) }
    }

    public func isConnected(owner: MiniAppID, token: UUID) -> Bool { consumers[owner]?.token == token }

    #if os(iOS)
    public func setCoreLocationReceiver(owner: MiniAppID, token: UUID,
                                       receive: @escaping @MainActor ([CLLocation], UUID) -> Void) {
        guard isConnected(owner: owner, token: token) else { return }
        consumers[owner]?.receiveCoreLocations = receive
    }
    #endif

    @discardableResult
    public func connect(owner: MiniAppID,
                        receive: @escaping @MainActor @Sendable (MiniAppLocationEvent) -> Void) -> UUID {
        let token = UUID(); connect(owner: owner, token: token, receive: receive); return token
    }

    public func disconnect(owner: MiniAppID, token: UUID) {
        guard consumers[owner]?.token == token else { return }
        consumers.removeValue(forKey: owner)
        if let generation = updateOwners.removeValue(forKey: owner) { native.stopUpdates(generation: generation) }
    }

    /// Apply a Feature-consent revocation without changing app-wide OS permission.
    /// Durable registrations are owned work, so revocation removes this owner only.
    public func revoke(owner: MiniAppID) throws {
        if let generation = updateOwners.removeValue(forKey: owner) { native.stopUpdates(generation: generation) }
        try unregisterAll(owner: owner)
    }

    public func requestAuthorization(owner: MiniAppID, featureConsent: Bool,
                                     request: MiniAppLocationAuthorizationRequest) throws {
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        native.requestAuthorization(request)
    }

    @discardableResult
    public func startUpdates(owner: MiniAppID, featureConsent: Bool,
                             configuration: MiniAppLocationUpdateConfiguration) throws -> UUID {
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        let authorization = native.authorization
        guard authorization == .whenInUse || authorization == .always else {
            throw MiniAppLocationFailure.osAuthorizationDenied(authorization)
        }
        if let previous = updateOwners[owner] { native.stopUpdates(generation: previous) }
        let generation = UUID()
        updateOwners[owner] = generation
        native.startUpdates(configuration: configuration, generation: generation)
        return generation
    }

    public func stopUpdates(owner: MiniAppID, generation: UUID) throws {
        guard updateOwners[owner] == generation else { throw MiniAppLocationFailure.staleGeneration }
        updateOwners.removeValue(forKey: owner)
        native.stopUpdates(generation: generation)
    }

    @discardableResult
    public func register(owner: MiniAppID, localID: String, region: MiniAppLocationRegion,
                         featureConsent: Bool) throws -> MiniAppLocationRegistration {
        try requireWritableStore()
        guard featureConsent else { throw MiniAppLocationFailure.featureConsentDenied }
        let authorization = native.authorization
        guard authorization == .whenInUse || authorization == .always else {
            throw MiniAppLocationFailure.osAuthorizationDenied(authorization)
        }
        let kind: MiniAppLocationMonitoringKind
        switch region { case .geofence: kind = .geofence; case .beacon: kind = .beacon }
        guard native.isMonitoringAvailable(for: kind) else { throw MiniAppLocationFailure.monitoringUnavailable }
        if case .geofence(_, _, let radius, _, _) = region,
           native.maximumRegionMonitoringDistance > 0, radius > native.maximumRegionMonitoringDistance {
            throw MiniAppLocationFailure.radiusExceedsMaximum(
                requested: radius, maximum: native.maximumRegionMonitoringDistance)
        }
        guard !registrations.values.contains(where: { $0.owner == owner && $0.localID == localID }) else {
            throw MiniAppLocationFailure.duplicateLocalID
        }
        let occupied = native.monitoredRegionIDs.union(registrations.keys).count
        guard occupied < Self.regionLimit else {
            throw MiniAppLocationFailure.capacityExceeded(limit: Self.regionLimit, occupied: occupied)
        }
        let registration = try MiniAppLocationRegistration(owner: owner, localID: localID, region: region)
        registrations[registration.id] = registration
        do {
            try persist()
            native.startMonitoring(registration)
            return registration
        } catch {
            registrations.removeValue(forKey: registration.id)
            try? persist()
            throw error
        }
    }

    public func unregister(owner: MiniAppID, localID: String, generation: UUID? = nil) throws {
        try requireWritableStore()
        guard let registration = registrations.values.first(where: { $0.owner == owner && $0.localID == localID }) else {
            throw MiniAppLocationFailure.wrongOwner
        }
        if let generation, registration.generation != generation { throw MiniAppLocationFailure.staleGeneration }
        registrations.removeValue(forKey: registration.id)
        do { try persist() }
        catch { registrations[registration.id] = registration; throw error }
        native.stopMonitoring(identifier: registration.id)
    }

    public func unregisterAll(owner: MiniAppID) throws {
        try requireWritableStore()
        let owned = registrations.values.filter { $0.owner == owner }
        for registration in owned { registrations.removeValue(forKey: registration.id) }
        do { try persist() }
        catch {
            for registration in owned { registrations[registration.id] = registration }
            throw error
        }
        for registration in owned { native.stopMonitoring(identifier: registration.id) }
    }

    public func requestState(owner: MiniAppID, localID: String) throws {
        guard let registration = registrations.values.first(where: { $0.owner == owner && $0.localID == localID }) else {
            throw MiniAppLocationFailure.wrongOwner
        }
        native.requestState(identifier: registration.id)
    }

    /// Reconnects persisted ownership to the manager during app launch. This does
    /// not invent registrations or restart continuous updates.
    public func registrations(owner: MiniAppID) -> [MiniAppLocationRegistration] {
        registrations.values.filter { $0.owner == owner }.sorted { $0.localID < $1.localID }
    }

    public func reconnectPersistedMonitoring(owner: MiniAppID) throws {
        try requireWritableStore()
        guard admissions[owner]?.isAllowed() == true else { return }
        guard native.authorization == .whenInUse || native.authorization == .always else { return }
        var occupied = native.monitoredRegionIDs
        for registration in registrations.values where registration.owner == owner && !occupied.contains(registration.id) {
            guard occupied.count < Self.regionLimit else {
                deliver(to: owner, .monitoringFailed(registration, "Core Location region limit \(Self.regionLimit) reached"))
                continue
            }
            native.startMonitoring(registration)
            occupied.insert(registration.id)
        }
    }

    private func requireWritableStore() throws {
        if let persistenceFailure { throw MiniAppLocationFailure.persistenceUnavailable(persistenceFailure) }
    }
    private func persist() throws { try requireWritableStore(); try store.write(Array(registrations.values)) }

    private func deliver(to owner: MiniAppID, _ event: MiniAppLocationEvent) {
        if let consumer = consumers[owner] { consumer.receive(event) }
        else if admissions[owner]?.isAllowed() == true { coldConsumers[owner]?(event) }
    }

    private func receive(_ event: MiniAppLocationNativeEvent) {
        switch event {
        case .locations(let generation, let samples):
            guard let owner = updateOwners.first(where: { $0.value == generation })?.key else { return }
            deliver(to: owner, .locations(generation: generation, samples: samples))
        case .authorizationChanged(let status):
            if status != .whenInUse && status != .always {
                for generation in updateOwners.values { native.stopUpdates(generation: generation) }
                updateOwners.removeAll()
            }
            for owner in Set(consumers.keys).union(coldConsumers.keys) { deliver(to: owner, .authorizationChanged(status)) }
        case .entered(let id): deliver(id) { .entered($0) }
        case .exited(let id): deliver(id) { .exited($0) }
        case .state(let id, let state): deliver(id) { .state($0, state) }
        case .monitoringFailed(let id, let message):
            if let id, let registration = registrations[id] {
                registrations.removeValue(forKey: id)
                do {
                    try persist()
                    deliver(to: registration.owner, .monitoringFailed(registration, message))
                } catch {
                    registrations[id] = registration
                    deliver(to: registration.owner, .monitoringFailed(
                        registration, "\(message); registration metadata cleanup failed: \(error.localizedDescription)"))
                }
            } else if id == nil {
                for owner in Set(consumers.keys).union(coldConsumers.keys) {
                    deliver(to: owner, .monitoringFailed(nil, message))
                }
            }
        case .failed(let generation, let message):
            if let generation, let owner = updateOwners.first(where: { $0.value == generation })?.key {
                deliver(to: owner, .failed(generation: generation, message))
            }
        }
    }

    private func deliver(_ identifier: String,
                         event: (MiniAppLocationRegistration) -> MiniAppLocationEvent) {
        guard let registration = registrations[identifier] else { return }
        deliver(to: registration.owner, event(registration))
    }
}

@MainActor
public final class MiniAppLocationService {
    public let owner: MiniAppID
    private let coordinator: MiniAppLocationCoordinator
    private let featureConsent: @MainActor @Sendable () -> Bool
    private let admission = MiniAppLocationAdmission()
    private var activeToken: UUID?
    private weak var connectedRuntime: MiniAppRuntime?
    public var receive: (@MainActor @Sendable (MiniAppLocationEvent) -> Void)?
    #if os(iOS)
    public var receiveCoreLocations: (@MainActor ([CLLocation], UUID) -> Void)?
    #endif

    public init(owner: MiniAppID, coordinator: MiniAppLocationCoordinator = .shared,
                featureConsent: @escaping @MainActor @Sendable () -> Bool) {
        precondition(owner.isValid)
        self.owner = owner; self.coordinator = coordinator; self.featureConsent = featureConsent
        coordinator.prepare(owner: owner, admission: admission) { [weak self] event in
            guard let self, self.featureConsent(), !self.admission.isClosed() else { return }
            self.receive?(event)
        }
    }

    public func connect(to runtime: MiniAppRuntime) throws {
        let token = UUID()
        let coordinator = coordinator, owner = owner
        try runtime.onShutdownAsync { [weak self] in
            coordinator.disconnect(owner: owner, token: token)
            if self?.activeToken == token {
                self?.activeToken = nil
                self?.connectedRuntime = nil
            }
        }
        coordinator.connect(owner: owner, token: token) { [weak self] event in
            guard let self, self.featureConsent(), !self.admission.isClosed() else { return }
            self.receive?(event)
        }
        #if os(iOS)
        coordinator.setCoreLocationReceiver(owner: owner, token: token) { [weak self] locations, generation in
            guard let self, self.featureConsent(), !self.admission.isClosed() else { return }
            self.receiveCoreLocations?(locations, generation)
        }
        #endif
        activeToken = token
        connectedRuntime = runtime
    }

    private func requireConnection() throws {
        guard let activeToken, connectedRuntime?.isClosed == false, !admission.isClosed(),
              coordinator.isConnected(owner: owner, token: activeToken) else {
            throw MiniAppLocationFailure.stopped
        }
    }

    public func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) throws {
        try requireConnection()
        try coordinator.requestAuthorization(owner: owner, featureConsent: featureConsent(), request: request)
    }
    public func startUpdates(_ configuration: MiniAppLocationUpdateConfiguration) throws -> UUID {
        try requireConnection()
        return try coordinator.startUpdates(owner: owner, featureConsent: featureConsent(), configuration: configuration)
    }
    public func stopUpdates(generation: UUID) throws { try requireConnection(); try coordinator.stopUpdates(owner: owner, generation: generation) }
    public func register(localID: String, region: MiniAppLocationRegion) throws -> MiniAppLocationRegistration {
        try requireConnection()
        return try coordinator.register(owner: owner, localID: localID, region: region, featureConsent: featureConsent())
    }
    public func unregister(localID: String, generation: UUID? = nil) throws {
        try requireConnection()
        try coordinator.unregister(owner: owner, localID: localID, generation: generation)
    }
    public func unregisterAll() throws { try requireConnection(); try coordinator.unregisterAll(owner: owner) }
    public func unregisterAllOwned() throws { try coordinator.unregisterAll(owner: owner) }
    public func requestState(localID: String) throws { try requireConnection(); try coordinator.requestState(owner: owner, localID: localID) }
    public var registrations: [MiniAppLocationRegistration] { coordinator.registrations(owner: owner) }
    public func reconnectPersistedMonitoring() throws {
        guard featureConsent() else { try coordinator.revoke(owner: owner); return }
        try coordinator.reconnectPersistedMonitoring(owner: owner)
    }
    public func featureConsentDidChange() throws {
        if !featureConsent() { try coordinator.revoke(owner: owner) }
    }

    public var externalAccess: MiniAppExternalAccess {
        let owner = owner, admission = admission, coordinator = coordinator
        return MiniAppExternalAccess(id: owner, prepare: { admission.setAllowed($0) }, close: {
            admission.setAllowed(false)
            try await MainActor.run { try coordinator.revoke(owner: owner) }
        }, open: {
            admission.setAllowed(true)
        }, restoreLifecycle: { inner in
            MiniAppRestoreLifecycle(stop: {
                admission.setSuspended(true)
                try await inner?.stop()
            }, resume: {
                try await inner?.resume()
                admission.setSuspended(false)
            })
        })
    }
}
