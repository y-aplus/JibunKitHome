import Foundation

public enum MiniAppBluetoothAuthorization: String, Sendable, Equatable { case notDetermined, restricted, denied, allowed, unsupported }
public enum MiniAppBluetoothPower: String, Sendable, Equatable { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }

public struct MiniAppBluetoothAdvertisement: Sendable, Equatable {
    public let localName: String?
    public let manufacturerData: Data?
    public let serviceData: [String: Data]
    public let serviceUUIDs: [String]
    public let overflowServiceUUIDs: [String]
    public let solicitedServiceUUIDs: [String]
    public let txPower: Int?
    public let isConnectable: Bool?
    public init(localName: String? = nil, manufacturerData: Data? = nil,
                serviceData: [String: Data] = [:], serviceUUIDs: [String] = [],
                overflowServiceUUIDs: [String] = [], solicitedServiceUUIDs: [String] = [],
                txPower: Int? = nil, isConnectable: Bool? = nil) {
        self.localName = localName; self.manufacturerData = manufacturerData
        self.serviceData = serviceData; self.serviceUUIDs = serviceUUIDs
        self.overflowServiceUUIDs = overflowServiceUUIDs; self.solicitedServiceUUIDs = solicitedServiceUUIDs
        self.txPower = txPower; self.isConnectable = isConnectable
    }
}

public struct MiniAppBluetoothPeripheral: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String?
    public let rssi: Int?
    public let advertisement: MiniAppBluetoothAdvertisement
    public init(id: UUID, name: String? = nil, rssi: Int? = nil,
                advertisement: MiniAppBluetoothAdvertisement = .init()) {
        self.id = id; self.name = name; self.rssi = rssi; self.advertisement = advertisement
    }
}

public struct MiniAppBluetoothCharacteristic: Sendable, Equatable, Hashable {
    public let service: String
    public let characteristic: String
    public init(service: String, characteristic: String) { self.service = service; self.characteristic = characteristic }
}

public enum MiniAppBluetoothWriteType: Sendable, Equatable { case withResponse, withoutResponse }
public enum MiniAppBluetoothEvent: Sendable, Equatable {
    case powerChanged(MiniAppBluetoothPower, authorization: MiniAppBluetoothAuthorization)
    case discovered(MiniAppBluetoothPeripheral)
    case connected(peripheral: UUID, generation: UUID, restored: Bool)
    case disconnected(peripheral: UUID, generation: UUID, message: String?)
    case services(peripheral: UUID, generation: UUID, identifiers: [String])
    case characteristics(peripheral: UUID, generation: UUID, service: String, identifiers: [String])
    case value(peripheral: UUID, generation: UUID, characteristic: MiniAppBluetoothCharacteristic, data: Data, notifying: Bool)
    case notificationChanged(peripheral: UUID, generation: UUID, characteristic: MiniAppBluetoothCharacteristic, enabled: Bool)
    case writeCompleted(peripheral: UUID, generation: UUID, characteristic: MiniAppBluetoothCharacteristic)
    case readyToWriteWithoutResponse(peripheral: UUID, generation: UUID, maximumLength: Int)
    case failed(peripheral: UUID?, generation: UUID?, message: String)
}

public enum MiniAppBluetoothFailure: Error, Sendable, Equatable {
    case stopped, wrongOwner, staleGeneration, unknownPeripheral, unknownCharacteristic
    case bluetoothUnavailable(MiniAppBluetoothPower)
    case permissionDenied(MiniAppBluetoothAuthorization)
    case writeTooLarge(maximum: Int)
    case writeWouldBlock(maximum: Int)
}

public struct MiniAppBluetoothConnection: Sendable, Equatable {
    public let owner: MiniAppID
    public let peripheral: UUID
    public let generation: UUID
}
public struct MiniAppBluetoothOwnerLease: Sendable, Equatable {
    public let owner: MiniAppID
    fileprivate let token: UUID
}

func miniAppBluetoothUniqueIndex<Value>(
    _ values: [Value], identifier: (Value) -> String
) -> (unique: [String: Value], ambiguous: Set<String>) {
    var unique: [String: Value] = [:], ambiguous: Set<String> = []
    for value in values {
        let key = identifier(value)
        if unique[key] == nil { unique[key] = value } else { ambiguous.insert(key) }
    }
    return (unique, ambiguous)
}

@MainActor
public protocol MiniAppBluetoothNativeCentral: AnyObject {
    var power: MiniAppBluetoothPower { get }
    var authorization: MiniAppBluetoothAuthorization { get }
    var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)? { get set }
    func scan(serviceUUIDs: [String]?, allowDuplicates: Bool)
    func stopScan()
    func connect(peripheral: UUID, generation: UUID)
    func disconnect(peripheral: UUID, generation: UUID) async
    func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID)
    func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID)
    func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID)
    func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic,
               type: MiniAppBluetoothWriteType, peripheral: UUID, generation: UUID) throws
    func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID)
    func stopAll() async
}

@MainActor
public final class MiniAppBluetoothCoordinator {
    public typealias NativeFactory = @MainActor (MiniAppID, String) -> any MiniAppBluetoothNativeCentral
    private struct Consumer { let lease: MiniAppBluetoothOwnerLease; let receive: @MainActor @Sendable (MiniAppBluetoothEvent) -> Void }
    private struct Transition { let id: UUID; let task: Task<Void, Never> }
    private struct PeripheralKey: Hashable { let owner: MiniAppID; let peripheral: UUID }
    private struct OwnerState {
        let native: any MiniAppBluetoothNativeCentral
        var lease: MiniAppBluetoothOwnerLease?
        var consumer: Consumer?
        var connections: [UUID: UUID] = [:]
        var pendingRestoration: [MiniAppBluetoothEvent] = []
        mutating func enqueueRestoration(_ event: MiniAppBluetoothEvent) {
            // Keep startup retention bounded. Overflow is an explicit failure,
            // never reported as a complete replay of the restored event stream.
            if pendingRestoration.count < 256 {
                pendingRestoration.append(event)
            } else {
                pendingRestoration[255] = .failed(peripheral: nil, generation: nil,
                    message: "Bluetooth restoration event buffer overflow; reconcile peripheral state")
            }
        }
        var admitted = false
        var restorationOpen = false
        var onRestore: (@MainActor @Sendable () -> Void)?
        var stopTransition: Transition?
    }
    public static let shared = MiniAppBluetoothCoordinator()
    private let factory: NativeFactory
    private var owners: [MiniAppID: OwnerState] = [:]
    private var busyOwners: Set<MiniAppID> = []
    private var ownerWaiters: [MiniAppID: [CheckedContinuation<Void, Never>]] = [:]
    private var busyPeripherals: Set<PeripheralKey> = []
    private var peripheralWaiters: [PeripheralKey: [CheckedContinuation<Void, Never>]] = [:]
    public init(factory: @escaping NativeFactory = { MiniAppCoreBluetoothCentral(owner: $0, restorationIdentifier: $1) }) { self.factory = factory }
    public static func restorationIdentifier(for owner: MiniAppID) -> String { "dev.jibunkit.bluetooth.central.\(owner.storageNamespace)" }

    public func prepareRestoration(owner: MiniAppID, admitted: Bool,
                                   onRestore: @escaping @MainActor @Sendable () -> Void) {
        guard admitted else { return }
        if var state = owners[owner] {
            guard state.stopTransition == nil else { return }
            state.admitted = true; state.restorationOpen = true; state.onRestore = onRestore; owners[owner] = state
            return
        }
        let native = factory(owner, Self.restorationIdentifier(for: owner))
        owners[owner] = OwnerState(native: native, admitted: true, restorationOpen: true, onRestore: onRestore)
        native.eventHandler = { [weak self] in self?.receive($0, owner: owner) }
    }
    @discardableResult
    public func connect(owner: MiniAppID,
                        receive: @escaping @MainActor @Sendable (MiniAppBluetoothEvent) -> Void) async -> MiniAppBluetoothOwnerLease {
        while true {
            if let transition = owners[owner]?.stopTransition {
                await transition.task.value
                continue
            }
            await acquireOwner(owner)
            if owners[owner]?.stopTransition == nil { break }
            releaseOwner(owner)
        }
        defer { releaseOwner(owner) }
        var state = state(for: owner, admitted: true)
        let lease = MiniAppBluetoothOwnerLease(owner: owner, token: UUID())
        state.lease = lease; state.consumer = Consumer(lease: lease, receive: receive); state.admitted = true
        let pending = state.pendingRestoration; state.pendingRestoration.removeAll(); owners[owner] = state
        pending.forEach(receive)
        return lease
    }
    public func isConnected(_ lease: MiniAppBluetoothOwnerLease) -> Bool { owners[lease.owner]?.consumer?.lease == lease }
    public func disconnect(_ lease: MiniAppBluetoothOwnerLease) async {
        guard var state = owners[lease.owner], state.lease == lease else { return }
        if let transition = state.stopTransition { await transition.task.value; return }
        state.consumer = nil; state.admitted = false; state.restorationOpen = false
        state.connections.removeAll(); state.pendingRestoration.removeAll()
        let transitionID = UUID(), native = state.native
        let transition = Transition(id: transitionID, task: Task { @MainActor [weak self] in
            guard let self else { await native.stopAll(); return }
            await self.finishStop(owner: lease.owner, lease: lease, transitionID: transitionID, native: native)
        })
        state.stopTransition = transition
        owners[lease.owner] = state
        await transition.task.value
    }
    public func unregister(_ lease: MiniAppBluetoothOwnerLease) async {
        guard let state = owners[lease.owner], state.lease == lease else { return }
        await disconnect(lease)
        guard owners[lease.owner]?.lease == lease, owners[lease.owner]?.consumer == nil else { return }
        state.native.eventHandler = nil; owners.removeValue(forKey: lease.owner)
    }

    public func power(_ lease: MiniAppBluetoothOwnerLease) throws -> MiniAppBluetoothPower { try active(lease).native.power }
    public func authorization(_ lease: MiniAppBluetoothOwnerLease) throws -> MiniAppBluetoothAuthorization { try active(lease).native.authorization }
    public func scan(_ lease: MiniAppBluetoothOwnerLease, serviceUUIDs: [String]?, allowDuplicates: Bool) throws {
        let native = try active(lease).native; try requireAvailable(native); native.scan(serviceUUIDs: serviceUUIDs, allowDuplicates: allowDuplicates)
    }
    public func stopScan(_ lease: MiniAppBluetoothOwnerLease) throws { try active(lease).native.stopScan() }
    public func currentConnection(peripheral: UUID, lease: MiniAppBluetoothOwnerLease) throws -> MiniAppBluetoothConnection? {
        let state = try active(lease)
        guard let generation = state.connections[peripheral] else { return nil }
        return .init(owner: lease.owner, peripheral: peripheral, generation: generation)
    }
    public func connect(_ lease: MiniAppBluetoothOwnerLease, peripheral: UUID) async throws -> MiniAppBluetoothConnection {
        await acquireOwner(lease.owner); defer { releaseOwner(lease.owner) }
        let key = PeripheralKey(owner: lease.owner, peripheral: peripheral)
        await acquire(key); defer { release(key) }
        var state = try active(lease); try requireAvailable(state.native)
        if let old = state.connections.removeValue(forKey: peripheral) {
            owners[lease.owner] = state
            await state.native.disconnect(peripheral: peripheral, generation: old)
            state = try active(lease)
        }
        let generation = UUID(); state.connections[peripheral] = generation; owners[lease.owner] = state
        state.native.connect(peripheral: peripheral, generation: generation)
        return .init(owner: lease.owner, peripheral: peripheral, generation: generation)
    }
    public func disconnect(_ connection: MiniAppBluetoothConnection, lease: MiniAppBluetoothOwnerLease) async throws {
        await acquireOwner(lease.owner); defer { releaseOwner(lease.owner) }
        let key = PeripheralKey(owner: lease.owner, peripheral: connection.peripheral)
        await acquire(key); defer { release(key) }
        var state = try checked(connection, lease: lease); state.connections.removeValue(forKey: connection.peripheral)
        owners[lease.owner] = state
        await state.native.disconnect(peripheral: connection.peripheral, generation: connection.generation)
    }
    public func discoverServices(_ ids: [String]?, on c: MiniAppBluetoothConnection, lease: MiniAppBluetoothOwnerLease) throws {
        let s = try checked(c, lease: lease); s.native.discoverServices(ids, peripheral: c.peripheral, generation: c.generation)
    }
    public func discoverCharacteristics(_ ids: [String]?, service: String, on c: MiniAppBluetoothConnection, lease: MiniAppBluetoothOwnerLease) throws {
        let s = try checked(c, lease: lease); s.native.discoverCharacteristics(ids, service: service, peripheral: c.peripheral, generation: c.generation)
    }
    public func read(_ key: MiniAppBluetoothCharacteristic, on c: MiniAppBluetoothConnection, lease: MiniAppBluetoothOwnerLease) throws {
        let s = try checked(c, lease: lease); s.native.read(key, peripheral: c.peripheral, generation: c.generation)
    }
    public func write(_ data: Data, to key: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType,
                      on c: MiniAppBluetoothConnection, lease: MiniAppBluetoothOwnerLease) throws {
        let s = try checked(c, lease: lease); try s.native.write(data, to: key, type: type, peripheral: c.peripheral, generation: c.generation)
    }
    public func setNotify(_ enabled: Bool, for key: MiniAppBluetoothCharacteristic,
                          on c: MiniAppBluetoothConnection, lease: MiniAppBluetoothOwnerLease) throws {
        let s = try checked(c, lease: lease); s.native.setNotify(enabled, for: key, peripheral: c.peripheral, generation: c.generation)
    }

    private func state(for owner: MiniAppID, admitted: Bool) -> OwnerState {
        if let state = owners[owner] { return state }
        let native = factory(owner, Self.restorationIdentifier(for: owner))
        let state = OwnerState(native: native, admitted: admitted); owners[owner] = state
        native.eventHandler = { [weak self] in self?.receive($0, owner: owner) }
        return owners[owner] ?? state
    }
    private func active(_ lease: MiniAppBluetoothOwnerLease) throws -> OwnerState {
        guard let state = owners[lease.owner], state.admitted, state.consumer?.lease == lease else { throw MiniAppBluetoothFailure.stopped }
        return state
    }
    private func checked(_ c: MiniAppBluetoothConnection, lease: MiniAppBluetoothOwnerLease) throws -> OwnerState {
        guard c.owner == lease.owner else { throw MiniAppBluetoothFailure.wrongOwner }
        let state = try active(lease)
        guard state.connections[c.peripheral] == c.generation else { throw MiniAppBluetoothFailure.staleGeneration }
        return state
    }
    private func requireAvailable(_ native: any MiniAppBluetoothNativeCentral) throws {
        guard native.authorization != .denied && native.authorization != .restricted else { throw MiniAppBluetoothFailure.permissionDenied(native.authorization) }
        guard native.power == .poweredOn else { throw MiniAppBluetoothFailure.bluetoothUnavailable(native.power) }
    }
    private func acquireOwner(_ owner: MiniAppID) async {
        while busyOwners.contains(owner) {
            await withCheckedContinuation { ownerWaiters[owner, default: []].append($0) }
        }
        busyOwners.insert(owner)
    }
    private func finishStop(owner: MiniAppID, lease: MiniAppBluetoothOwnerLease,
                            transitionID: UUID, native: any MiniAppBluetoothNativeCentral) async {
        await acquireOwner(owner); defer { releaseOwner(owner) }
        guard owners[owner]?.lease == lease, owners[owner]?.stopTransition?.id == transitionID else { return }
        await native.stopAll()
        if var state = owners[owner], state.stopTransition?.id == transitionID {
            state.stopTransition = nil; owners[owner] = state
        }
    }
    private func releaseOwner(_ owner: MiniAppID) {
        busyOwners.remove(owner)
        let waiters = ownerWaiters.removeValue(forKey: owner) ?? []
        waiters.forEach { $0.resume() }
    }
    private func acquire(_ key: PeripheralKey) async {
        while busyPeripherals.contains(key) {
            await withCheckedContinuation { peripheralWaiters[key, default: []].append($0) }
        }
        busyPeripherals.insert(key)
    }
    private func release(_ key: PeripheralKey) {
        busyPeripherals.remove(key)
        let waiters = peripheralWaiters.removeValue(forKey: key) ?? []
        waiters.forEach { $0.resume() }
    }
    private func receive(_ event: MiniAppBluetoothEvent, owner: MiniAppID) {
        guard var state = owners[owner], state.admitted else { return }
        switch event {
        case .connected(let peripheral, let generation, let restored):
            if restored {
                guard state.restorationOpen else { return }
                state.connections[peripheral] = generation
                if let consumer = state.consumer {
                    owners[owner] = state; consumer.receive(event)
                } else {
                    state.enqueueRestoration(event); owners[owner] = state; state.onRestore?()
                }
                return
            }
            guard state.connections[peripheral] == generation else { return }
        case .disconnected(let p, let g, _):
            guard state.connections[p] == g else { return }; state.connections.removeValue(forKey: p); owners[owner] = state
        case .services(let p, let g, _), .characteristics(let p, let g, _, _), .value(let p, let g, _, _, _),
             .notificationChanged(let p, let g, _, _), .writeCompleted(let p, let g, _), .readyToWriteWithoutResponse(let p, let g, _):
            guard state.connections[p] == g else { return }
        case .failed(let p?, let g?, _): guard state.connections[p] == g else { return }
        default: break
        }
        if let consumer = state.consumer {
            consumer.receive(event)
        } else if state.restorationOpen, !state.pendingRestoration.isEmpty {
            // Restored connection events can arrive before the Feature's async
            // lifetime has attached its consumer. Preserve their order with the
            // restored-connected event instead of silently dropping the values.
            state.enqueueRestoration(event)
            owners[owner] = state
        }
    }
}

@MainActor
public final class MiniAppBluetoothService {
    public let owner: MiniAppID
    private let coordinator: MiniAppBluetoothCoordinator
    private var lease: MiniAppBluetoothOwnerLease?
    private weak var runtime: MiniAppRuntime?
    public var receive: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    public init(owner: MiniAppID, coordinator: MiniAppBluetoothCoordinator = .shared) { precondition(owner.isValid); self.owner = owner; self.coordinator = coordinator }
    public func prepareRestoration(admitted: Bool, onRestore: @escaping @MainActor @Sendable () -> Void) {
        coordinator.prepareRestoration(owner: owner, admitted: admitted, onRestore: onRestore)
    }
    public func connect(to runtime: MiniAppRuntime) async throws {
        let admission = MiniAppBluetoothEventAdmission()
        let lease = await coordinator.connect(owner: owner) { admission.receive($0) }
        let coordinator = coordinator
        do {
            try runtime.onShutdownAsync { [weak self] in
                await coordinator.disconnect(lease)
                if self?.lease == lease { self?.runtime = nil }
            }
        } catch {
            await coordinator.unregister(lease)
            throw error
        }
        self.lease = lease; self.runtime = runtime
        admission.open { [weak self] event in
            guard let self, self.lease == lease, self.runtime?.isClosed == false else { return }
            self.receive?(event)
        }
    }
    public func unregisterAllOwned() async { guard let lease else { return }; await coordinator.unregister(lease); if self.lease == lease { self.lease = nil; runtime = nil } }
    private func activeLease() throws -> MiniAppBluetoothOwnerLease {
        guard let lease, runtime?.isClosed == false, coordinator.isConnected(lease) else { throw MiniAppBluetoothFailure.stopped }; return lease
    }
    public var power: MiniAppBluetoothPower { guard let lease else { return .unknown }; return (try? coordinator.power(lease)) ?? .unknown }
    public var authorization: MiniAppBluetoothAuthorization { guard let lease else { return .notDetermined }; return (try? coordinator.authorization(lease)) ?? .notDetermined }
    public func scan(serviceUUIDs: [String]? = nil, allowDuplicates: Bool = false) throws { try coordinator.scan(activeLease(), serviceUUIDs: serviceUUIDs, allowDuplicates: allowDuplicates) }
    public func stopScan() throws { try coordinator.stopScan(activeLease()) }
    /// Returns this lifetime's current ticket, including an OS-restored ticket.
    /// Connection readiness is still established by the connected event.
    public func currentConnection(peripheral: UUID) throws -> MiniAppBluetoothConnection? {
        try coordinator.currentConnection(peripheral: peripheral, lease: activeLease())
    }
    public func connect(peripheral: UUID) async throws -> MiniAppBluetoothConnection { try await coordinator.connect(activeLease(), peripheral: peripheral) }
    public func disconnect(_ c: MiniAppBluetoothConnection) async throws { try await coordinator.disconnect(c, lease: activeLease()) }
    public func discoverServices(_ ids: [String]? = nil, on c: MiniAppBluetoothConnection) throws { try coordinator.discoverServices(ids, on: c, lease: activeLease()) }
    public func discoverCharacteristics(_ ids: [String]? = nil, service: String, on c: MiniAppBluetoothConnection) throws { try coordinator.discoverCharacteristics(ids, service: service, on: c, lease: activeLease()) }
    public func read(_ key: MiniAppBluetoothCharacteristic, on c: MiniAppBluetoothConnection) throws { try coordinator.read(key, on: c, lease: activeLease()) }
    public func write(_ data: Data, to key: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType, on c: MiniAppBluetoothConnection) throws { try coordinator.write(data, to: key, type: type, on: c, lease: activeLease()) }
    public func setNotify(_ enabled: Bool, for key: MiniAppBluetoothCharacteristic, on c: MiniAppBluetoothConnection) throws { try coordinator.setNotify(enabled, for: key, on: c, lease: activeLease()) }
}

/// Restoration may be delivered while the coordinator is attaching its consumer.
/// Expose it only after the service has installed its runtime and lease, so the
/// Feature can immediately use the restored connection inside its callback.
@MainActor
private final class MiniAppBluetoothEventAdmission {
    private var pending: [MiniAppBluetoothEvent] = []
    private var delivery: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?

    func receive(_ event: MiniAppBluetoothEvent) {
        if let delivery { delivery(event) } else { pending.append(event) }
    }

    func open(_ delivery: @escaping @MainActor @Sendable (MiniAppBluetoothEvent) -> Void) {
        self.delivery = delivery
        let snapshot = pending
        pending.removeAll()
        snapshot.forEach(delivery)
    }
}
