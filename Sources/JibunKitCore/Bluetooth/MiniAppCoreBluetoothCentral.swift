import Foundation
#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth

/// The OS can restore a connected peripheral with an already discovered GATT
/// graph. Rebuild the same identity indexes used by live delegate callbacks
/// before admitting restored notifications. No manager or radio is created here.
@MainActor
struct MiniAppBluetoothRestoredAttributes {
    let services: [String: CBService]
    let ambiguousServices: Set<String>
    let characteristics: [MiniAppBluetoothCharacteristic: CBCharacteristic]

    init(_ restoredServices: [CBService]) {
        let serviceIndex = miniAppBluetoothUniqueIndex(restoredServices) { $0.uuid.uuidString }
        services = serviceIndex.unique
        ambiguousServices = serviceIndex.ambiguous
        var result: [MiniAppBluetoothCharacteristic: CBCharacteristic] = [:]
        for (serviceID, service) in serviceIndex.unique where !serviceIndex.ambiguous.contains(serviceID) {
            let index = miniAppBluetoothUniqueIndex(service.characteristics ?? []) { $0.uuid.uuidString }
            for (characteristicID, characteristic) in index.unique where !index.ambiguous.contains(characteristicID) {
                result[.init(service: serviceID, characteristic: characteristicID)] = characteristic
            }
        }
        characteristics = result
    }
}

@MainActor
public final class MiniAppCoreBluetoothCentral: NSObject, MiniAppBluetoothNativeCentral,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    public var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)? {
        didSet {
            guard let eventHandler else { return }
            let pending = pendingEvents; pendingEvents.removeAll()
            for event in pending { eventHandler(event) }
        }
    }
    public private(set) var restorationIdentifier: String
    public let owner: MiniAppID
    private var central: CBCentralManager!
    private let diagnostics: (@MainActor (String) -> Void)?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var generations: [UUID: UUID] = [:]
    private var restoredGenerations: Set<UUID> = []
    private var cancelling: Set<UUID> = []
    private var disconnectWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var services: [UUID: [String: CBService]] = [:]
    private var ambiguousServiceUUIDs: [UUID: Set<String>] = [:]
    private var serviceDiscoveryGenerations: [UUID: UUID] = [:]
    private var characteristics: [UUID: [MiniAppBluetoothCharacteristic: CBCharacteristic]] = [:]
    private var serviceGenerations: [ObjectIdentifier: UUID] = [:]
    private var characteristicGenerations: [ObjectIdentifier: UUID] = [:]
    private var pendingEvents: [MiniAppBluetoothEvent] = []

    public init(owner: MiniAppID, restorationIdentifier: String,
                diagnostics: (@MainActor (String) -> Void)? = nil) {
        self.owner = owner; self.restorationIdentifier = restorationIdentifier
        self.diagnostics = diagnostics
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restorationIdentifier])
    }
    public var power: MiniAppBluetoothPower { Self.power(central.state) }
    public var authorization: MiniAppBluetoothAuthorization {
        switch CBManager.authorization {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .allowedAlways: .allowed
        @unknown default: .unsupported
        }
    }
    public func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {
        central.scanForPeripherals(withServices: serviceUUIDs?.map { CBUUID(string: $0) },
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates])
    }
    public func stopScan() { central.stopScan() }
    public func connect(peripheral id: UUID, generation: UUID) {
        guard let peripheral = peripheral(id) else {
            return emit(.disconnected(peripheral: id, generation: generation,
                                      message: "Peripheral is not known to this owner"))
        }
        guard generations[id] == nil else { return fail(id, generation, "Native generation is still active") }
        trace("connect before delegate assignment", peripheral)
        generations[id] = generation; peripheral.delegate = self
        trace("connect after delegate assignment", peripheral)
        central.connect(peripheral)
    }
    public func disconnect(peripheral id: UUID, generation: UUID) async {
        guard generations[id] == generation else { return }
        guard let peripheral = peripherals[id], peripheral.state != .disconnected else { finish(id, generation: generation); return }
        trace("cancel connection", peripheral)
        cancelling.insert(id); central.cancelPeripheralConnection(peripheral)
        await withCheckedContinuation { disconnectWaiters[id, default: []].append($0) }
    }
    public func discoverServices(_ ids: [String]?, peripheral id: UUID, generation: UUID) {
        guard let peripheral = checked(id, generation) else { return }
        serviceDiscoveryGenerations[id] = generation
        peripheral.discoverServices(ids?.map { CBUUID(string: $0) })
    }
    public func discoverCharacteristics(_ ids: [String]?, service: String, peripheral id: UUID, generation: UUID) {
        guard ambiguousServiceUUIDs[id]?.contains(service) != true else {
            return fail(id, generation, "Multiple services share UUID \(service); select a device-specific CBService directly")
        }
        guard let peripheral = checked(id, generation), let service = services[id]?[service] else {
            return fail(id, generation, "Service is not known")
        }
        peripheral.discoverCharacteristics(ids?.map { CBUUID(string: $0) }, for: service)
    }
    public func read(_ key: MiniAppBluetoothCharacteristic, peripheral id: UUID, generation: UUID) {
        guard let peripheral = checked(id, generation), let characteristic = characteristics[id]?[key] else {
            return fail(id, generation, "Characteristic is not known")
        }
        trace("read request characteristic=\(characteristic.uuid.uuidString)", peripheral)
        peripheral.readValue(for: characteristic)
    }
    public func write(_ data: Data, to key: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType,
                      peripheral id: UUID, generation: UUID) throws {
        guard let peripheral = checked(id, generation), let characteristic = characteristics[id]?[key] else {
            throw MiniAppBluetoothFailure.unknownCharacteristic
        }
        let nativeType: CBCharacteristicWriteType
        switch type { case .withResponse: nativeType = .withResponse; case .withoutResponse: nativeType = .withoutResponse }
        let maximum = peripheral.maximumWriteValueLength(for: nativeType)
        guard data.count <= maximum else { throw MiniAppBluetoothFailure.writeTooLarge(maximum: maximum) }
        if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse {
            throw MiniAppBluetoothFailure.writeWouldBlock(maximum: maximum)
        }
        trace("write request characteristic=\(characteristic.uuid.uuidString) bytes=\(data.count)", peripheral)
        peripheral.writeValue(data, for: characteristic, type: nativeType)
    }
    public func setNotify(_ enabled: Bool, for key: MiniAppBluetoothCharacteristic,
                          peripheral id: UUID, generation: UUID) {
        guard let peripheral = checked(id, generation), let characteristic = characteristics[id]?[key] else {
            return fail(id, generation, "Characteristic is not known")
        }
        trace("notify request=\(enabled) characteristic=\(characteristic.uuid.uuidString) notifying=\(characteristic.isNotifying)", peripheral)
        peripheral.setNotifyValue(enabled, for: characteristic)
    }
    public func stopAll() async {
        central.stopScan()
        let active = Array(generations)
        for (id, generation) in active { await disconnect(peripheral: id, generation: generation) }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emit(.powerChanged(Self.power(central.state), authorization: authorization))
        if central.state != .poweredOn {
            for (id, generation) in Array(generations) {
                emit(.disconnected(peripheral: id, generation: generation,
                                   message: "Bluetooth became \(Self.power(central.state).rawValue)"))
                finish(id, generation: generation)
            }
        }
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Nearby advertisements must not evict connection evidence from a
        // bounded diagnostic log. Only report an active object's replacement.
        if generations[peripheral.identifier] != nil,
           peripherals[peripheral.identifier] !== peripheral {
            trace("discovered alternate object; active object retained", peripheral)
        }
        // Discovery is not an ownership transfer. In particular, ongoing scans
        // must not replace a delegate installed by a connection.
        if generations[peripheral.identifier] == nil {
            peripherals[peripheral.identifier] = peripheral
        }
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:])
            .reduce(into: [String: Data]()) { $0[$1.key.uuidString] = $1.value }
        let snapshot = MiniAppBluetoothAdvertisement(
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceData: serviceData,
            serviceUUIDs: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString),
            overflowServiceUUIDs: (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString),
            solicitedServiceUUIDs: (advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString),
            txPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue)
        emit(.discovered(.init(id: peripheral.identifier, name: peripheral.name,
                               rssi: RSSI.intValue, advertisement: snapshot)))
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        trace("connected callback", peripheral)
        guard let generation = generations[peripheral.identifier] else { return }
        if cancelling.contains(peripheral.identifier) { central.cancelPeripheralConnection(peripheral); return }
        let restored = restoredGenerations.remove(generation) != nil
        emit(.connected(peripheral: peripheral.identifier, generation: generation, restored: restored))
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                               error: (any Error)?) {
        trace("connection failure callback", peripheral)
        guard let generation = generations[peripheral.identifier] else { return }
        emit(.disconnected(peripheral: peripheral.identifier, generation: generation,
                           message: error?.localizedDescription ?? "Connect failed"))
        finish(peripheral.identifier, generation: generation)
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: (any Error)?) {
        trace("disconnected callback", peripheral)
        guard let generation = generations[peripheral.identifier] else { return }
        emit(.disconnected(peripheral: peripheral.identifier, generation: generation,
                           message: error?.localizedDescription))
        finish(peripheral.identifier, generation: generation)
    }
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        diagnostics?("willRestoreState callback restoredCount=\(restored.count)")
        for peripheral in restored {
            trace("willRestoreState peripheral before delegate assignment", peripheral)
            peripherals[peripheral.identifier] = peripheral; peripheral.delegate = self
            guard peripheral.state == .connected || peripheral.state == .connecting else { continue }
            let generation = UUID(); generations[peripheral.identifier] = generation
            restoreAttributes(peripheral, generation: generation)
            if peripheral.state == .connected {
                emit(.connected(peripheral: peripheral.identifier, generation: generation, restored: true))
            } else { restoredGenerations.insert(generation) }
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        guard serviceDiscoveryGenerations.removeValue(forKey: peripheral.identifier) == generation else { return }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let found = peripheral.services ?? []
        let index = miniAppBluetoothUniqueIndex(found) { $0.uuid.uuidString }
        services[peripheral.identifier] = index.unique
        ambiguousServiceUUIDs[peripheral.identifier] = index.ambiguous
        for service in found { serviceGenerations[ObjectIdentifier(service)] = generation }
        emit(.services(peripheral: peripheral.identifier, generation: generation,
                       identifiers: found.map { $0.uuid.uuidString }))
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                           error: (any Error)?) {
        guard let generation = generations[peripheral.identifier] else { return }
        guard serviceGenerations[ObjectIdentifier(service)] == generation else { return }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let found = service.characteristics ?? []
        var map = characteristics[peripheral.identifier] ?? [:]
        for value in found {
            map[.init(service: service.uuid.uuidString, characteristic: value.uuid.uuidString)] = value
            characteristicGenerations[ObjectIdentifier(value)] = generation
        }
        characteristics[peripheral.identifier] = map
        emit(.characteristics(peripheral: peripheral.identifier, generation: generation,
            service: service.uuid.uuidString, identifiers: found.map { $0.uuid.uuidString }))
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                           error: (any Error)?) {
        trace("value callback received error=\(error != nil)", peripheral)
        guard let generation = generations[peripheral.identifier] else {
            trace("dropped value callback: no active generation", peripheral)
            return
        }
        guard characteristicGenerations[ObjectIdentifier(characteristic)] == generation else {
            trace("dropped characteristic callback: unknown generation", peripheral)
            return
        }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let key = MiniAppBluetoothCharacteristic(service: characteristic.service?.uuid.uuidString ?? "",
                                                  characteristic: characteristic.uuid.uuidString)
        trace("value callback characteristic=\(characteristic.uuid.uuidString) bytes=\(characteristic.value?.count ?? 0) notifying=\(characteristic.isNotifying)", peripheral)
        emit(.value(peripheral: peripheral.identifier, generation: generation, characteristic: key,
                    data: characteristic.value ?? Data(), notifying: characteristic.isNotifying))
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                           error: (any Error)?) {
        trace("write callback received error=\(error != nil)", peripheral)
        guard let generation = generations[peripheral.identifier] else {
            trace("dropped write callback: no active generation", peripheral)
            return
        }
        guard characteristicGenerations[ObjectIdentifier(characteristic)] == generation else {
            trace("dropped characteristic callback: unknown generation", peripheral)
            return
        }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let key = MiniAppBluetoothCharacteristic(service: characteristic.service?.uuid.uuidString ?? "",
                                                  characteristic: characteristic.uuid.uuidString)
        trace("write callback characteristic=\(characteristic.uuid.uuidString)", peripheral)
        emit(.writeCompleted(peripheral: peripheral.identifier, generation: generation, characteristic: key))
    }
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: (any Error)?) {
        trace("notify callback received error=\(error != nil)", peripheral)
        guard let generation = generations[peripheral.identifier] else {
            trace("dropped notify callback: no active generation", peripheral)
            return
        }
        guard characteristicGenerations[ObjectIdentifier(characteristic)] == generation else {
            trace("dropped characteristic callback: unknown generation", peripheral)
            return
        }
        if let error { return fail(peripheral.identifier, generation, error.localizedDescription) }
        let key = MiniAppBluetoothCharacteristic(service: characteristic.service?.uuid.uuidString ?? "",
                                                  characteristic: characteristic.uuid.uuidString)
        trace("notify callback characteristic=\(characteristic.uuid.uuidString) enabled=\(characteristic.isNotifying)", peripheral)
        emit(.notificationChanged(peripheral: peripheral.identifier, generation: generation,
                                  characteristic: key, enabled: characteristic.isNotifying))
    }
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard let generation = generations[peripheral.identifier], !cancelling.contains(peripheral.identifier) else { return }
        emit(.readyToWriteWithoutResponse(peripheral: peripheral.identifier, generation: generation,
            maximumLength: peripheral.maximumWriteValueLength(for: .withoutResponse)))
    }
    private func restoreAttributes(_ peripheral: CBPeripheral, generation: UUID) {
        let restored = MiniAppBluetoothRestoredAttributes(peripheral.services ?? [])
        services[peripheral.identifier] = restored.services
        ambiguousServiceUUIDs[peripheral.identifier] = restored.ambiguousServices
        characteristics[peripheral.identifier] = restored.characteristics
        for service in restored.services.values {
            serviceGenerations[ObjectIdentifier(service)] = generation
        }
        for characteristic in restored.characteristics.values {
            characteristicGenerations[ObjectIdentifier(characteristic)] = generation
        }
        trace("restored attributes services=\(restored.services.count) characteristics=\(restored.characteristics.count)", peripheral)
    }
    private func peripheral(_ id: UUID) -> CBPeripheral? {
        if let value = peripherals[id] { return value }
        let value = central.retrievePeripherals(withIdentifiers: [id]).first
        if let value { peripherals[id] = value; trace("retrieved (delegate unchanged)", value) }
        return value
    }
    private func checked(_ id: UUID, _ generation: UUID) -> CBPeripheral? {
        guard generations[id] == generation else { fail(id, generation, "Stale connection generation"); return nil }
        return peripheral(id)
    }
    private func finish(_ id: UUID, generation: UUID) {
        guard generations[id] == generation else { return }
        generations[id] = nil; restoredGenerations.remove(generation); cancelling.remove(id)
        serviceDiscoveryGenerations[id] = nil
        ambiguousServiceUUIDs[id] = nil
        if let owned = services.removeValue(forKey: id)?.values {
            for service in owned { serviceGenerations[ObjectIdentifier(service)] = nil }
        }
        if let owned = characteristics.removeValue(forKey: id)?.values {
            for characteristic in owned { characteristicGenerations[ObjectIdentifier(characteristic)] = nil }
        }
        let waiters = disconnectWaiters.removeValue(forKey: id) ?? []; waiters.forEach { $0.resume() }
    }
    private func trace(_ action: String, _ peripheral: CBPeripheral) {
        guard let diagnostics else { return }
        let delegateOwner: String
        if let adapter = peripheral.delegate as? MiniAppCoreBluetoothCentral {
            delegateOwner = adapter.owner.rawValue
        } else { delegateOwner = peripheral.delegate == nil ? "nil" : "external" }
        diagnostics("\(action); peripheral=\(peripheral.identifier.uuidString.suffix(8)); object=\(ObjectIdentifier(peripheral)); manager=\(ObjectIdentifier(central)); generation=\(generations[peripheral.identifier]?.uuidString.suffix(8) ?? "none"); delegate=\(delegateOwner); state=\(peripheral.state.rawValue)")
    }
    private func fail(_ id: UUID?, _ generation: UUID?, _ message: String) {
        emit(.failed(peripheral: id, generation: generation, message: message))
    }
    private func emit(_ event: MiniAppBluetoothEvent) {
        if let eventHandler { eventHandler(event) } else { pendingEvents.append(event) }
    }
    private static func power(_ state: CBManagerState) -> MiniAppBluetoothPower {
        switch state {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
    }
}
#else
@MainActor
public final class MiniAppCoreBluetoothCentral: MiniAppBluetoothNativeCentral {
    public var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    public let owner: MiniAppID
    public let restorationIdentifier: String
    public init(owner: MiniAppID, restorationIdentifier: String) { self.owner = owner; self.restorationIdentifier = restorationIdentifier }
    public var power: MiniAppBluetoothPower { .unsupported }
    public var authorization: MiniAppBluetoothAuthorization { .unsupported }
    public func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {}
    public func stopScan() {}
    public func connect(peripheral: UUID, generation: UUID) {}
    public func disconnect(peripheral: UUID, generation: UUID) async {}
    public func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID) {}
    public func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID) {}
    public func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    public func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType, peripheral: UUID, generation: UUID) throws {}
    public func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    public func stopAll() async {}
}
#endif
