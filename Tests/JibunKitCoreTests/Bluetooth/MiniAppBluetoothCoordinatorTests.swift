import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppBluetoothCoordinatorTests: XCTestCase {
    func testStopClosesDeliveryBeforeJoiningNativeAndPreservesOtherOwner() async throws {
        let pool = FakePool(), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let a = MiniAppBluetoothService(owner: MiniAppID("ble-a"), coordinator: coordinator)
        let b = MiniAppBluetoothService(owner: MiniAppID("ble-b"), coordinator: coordinator)
        let ra = MiniAppRuntime(), rb = MiniAppRuntime(); try await a.connect(to: ra); try await b.connect(to: rb)
        let events = EventBox(); a.receive = { events.values.append($0) }
        let ca = try await a.connect(peripheral: UUID()), cb = try await b.connect(peripheral: UUID())
        pool[a.owner].blockStop = true
        let stopping = Task { @MainActor in await ra.shutdown() }
        await pool[a.owner].stopEntered.wait()
        pool[a.owner].emit(.connected(peripheral: ca.peripheral, generation: ca.generation, restored: false))
        XCTAssertTrue(events.values.isEmpty)
        try b.discoverServices(nil, on: cb)
        pool[a.owner].releaseStop.open(); await stopping.value
        XCTAssertEqual(pool[b.owner].stopCount, 0)
    }

    func testNormalLateConnectedNeverReAdoptsAfterExplicitDisconnect() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-late"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator), runtime = MiniAppRuntime()
        try await service.connect(to: runtime); let events = EventBox(); service.receive = { events.values.append($0) }
        let connection = try await service.connect(peripheral: UUID()); try await service.disconnect(connection)
        pool[owner].emit(.connected(peripheral: connection.peripheral, generation: connection.generation, restored: false))
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertThrowsError(try service.read(.init(service: "s", characteristic: "c"), on: connection))
    }

    func testReconnectJoinsOldNativeGenerationBeforeStartingNew() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-reconnect"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator), runtime = MiniAppRuntime(); try await service.connect(to: runtime)
        let events = EventBox(); service.receive = { events.values.append($0) }
        let peripheral = UUID(), first = try await service.connect(peripheral: peripheral)
        pool[owner].blockDisconnect = true
        let task = Task { @MainActor in try await service.connect(peripheral: peripheral) }
        await pool[owner].disconnectEntered.wait()
        let thirdTask = Task { @MainActor in try await service.connect(peripheral: peripheral) }
        XCTAssertEqual(pool[owner].connectGenerations, [first.generation])
        pool[owner].releaseDisconnect.open(); let second = try await task.value
        let third = try await thirdTask.value
        XCTAssertEqual(pool[owner].connectGenerations, [first.generation, second.generation, third.generation])
        pool[owner].emit(.services(peripheral: peripheral, generation: first.generation, identifiers: ["OLD"]))
        pool[owner].emit(.services(peripheral: peripheral, generation: second.generation, identifiers: ["ALSO-OLD"]))
        pool[owner].emit(.services(peripheral: peripheral, generation: third.generation, identifiers: ["NEW"]))
        XCTAssertEqual(events.values, [.services(peripheral: peripheral, generation: third.generation, identifiers: ["NEW"])])
    }

    func testNewLeaseWaitsForOldOwnerStopJoin() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-owner-barrier"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let old = MiniAppBluetoothService(owner: owner, coordinator: coordinator), replacement = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let oldRuntime = MiniAppRuntime(), newRuntime = MiniAppRuntime(); try await old.connect(to: oldRuntime)
        pool[owner].blockStop = true
        let stopping = Task { @MainActor in await oldRuntime.shutdown() }
        await pool[owner].stopEntered.wait()
        let starting = Task { @MainActor in try await replacement.connect(to: newRuntime) }
        await Task.yield()
        XCTAssertEqual(pool.created.count, 1)
        pool[owner].releaseStop.open(); await stopping.value; try await starting.value
        _ = try await replacement.connect(peripheral: UUID())
        await newRuntime.shutdown()
    }

    func testStopPublishedDuringReconnectWinsBeforeNewLeaseAdmission() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-stop-reconnect"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let old = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let replacement = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let oldRuntime = MiniAppRuntime(), newRuntime = MiniAppRuntime(); try await old.connect(to: oldRuntime)
        let peripheral = UUID(), first = try await old.connect(peripheral: peripheral)
        pool[owner].blockDisconnect = true; pool[owner].blockStop = true
        let reconnecting = Task { @MainActor in try await old.connect(peripheral: peripheral) }
        await pool[owner].disconnectEntered.wait()
        let stopping = Task { @MainActor in await oldRuntime.shutdown() }
        await Task.yield()
        let starting = Task { @MainActor in try await replacement.connect(to: newRuntime) }
        await Task.yield()
        pool[owner].releaseDisconnect.open()
        do { _ = try await reconnecting.value; XCTFail("Stop must reject reconnect") }
        catch MiniAppBluetoothFailure.stopped { }
        await pool[owner].stopEntered.wait()
        XCTAssertEqual(pool[owner].connectGenerations, [first.generation])
        pool[owner].releaseStop.open(); await stopping.value; try await starting.value
        _ = try await replacement.connect(peripheral: peripheral)
        await newRuntime.shutdown()
    }

    func testClosedRuntimeRegistrationRollsBackCreatedLease() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-runtime-rollback"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let closed = MiniAppRuntime(); await closed.shutdown()
        let failed = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        do {
            try await failed.connect(to: closed)
            XCTFail("Expected closed runtime registration failure")
        } catch MiniAppRuntime.Failure.closed { }
        let replacement = MiniAppBluetoothService(owner: owner, coordinator: coordinator), runtime = MiniAppRuntime()
        try await replacement.connect(to: runtime)
        XCTAssertEqual(pool.created.count, 2)
        await runtime.shutdown()
    }

    func testColdRestoreStartsLifetimeAndSnapshotWaitsForConsumer() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-restore"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let lifetime = MiniAppFeatureLifetime(id: owner) { runtime in try await service.connect(to: runtime) }
        let events = EventBox(); service.receive = { events.values.append($0) }
        service.prepareRestoration(admitted: true) { Task { try? await lifetime.start() } }
        let peripheral = UUID(), generation = UUID()
        pool[owner].emit(.connected(peripheral: peripheral, generation: generation, restored: true))
        for _ in 0..<20 where lifetime.state != .running { await Task.yield() }
        XCTAssertEqual(lifetime.state, .running)
        XCTAssertEqual(events.values, [.connected(peripheral: peripheral, generation: generation, restored: true)])
        await lifetime.stop()
    }

    func testDisabledRestoreDoesNotConstructManager() {
        let pool = FakePool(), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        coordinator.prepareRestoration(owner: MiniAppID("disabled"), admitted: false, onRestore: {})
        XCTAssertTrue(pool.created.isEmpty)
    }

    func testRestoredConnectionIsUsableInsideTheFirstConsumerCallback() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-restored-ticket")
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let runtime = MiniAppRuntime(), peripheral = UUID(), generation = UUID()
        service.prepareRestoration(admitted: true, onRestore: {})
        pool[owner].emit(.connected(peripheral: peripheral, generation: generation, restored: true))
        let events = EventBox()
        service.receive = { event in
            events.values.append(event)
            do {
                let connection = try XCTUnwrap(service.currentConnection(peripheral: peripheral))
                XCTAssertEqual(connection.owner, owner)
                XCTAssertEqual(connection.generation, generation)
                try service.discoverServices(on: connection)
            } catch { XCTFail("Restored callback preceded usable runtime: \(error)") }
        }
        try await service.connect(to: runtime)
        XCTAssertEqual(events.values.count, 1)
        let connection = try XCTUnwrap(service.currentConnection(peripheral: peripheral))
        try await service.disconnect(connection)
        XCTAssertNil(try service.currentConnection(peripheral: peripheral))
        await runtime.shutdown()
        XCTAssertThrowsError(try service.currentConnection(peripheral: peripheral))
        service.receive = nil
    }

    func testRejectedRuntimeDoesNotDeliverBufferedRestoration() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-restored-rollback")
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        service.prepareRestoration(admitted: true, onRestore: {})
        pool[owner].emit(.connected(peripheral: UUID(), generation: UUID(), restored: true))
        let events = EventBox()
        service.receive = { events.values.append($0) }
        let runtime = MiniAppRuntime()
        await runtime.shutdown()
        do {
            try await service.connect(to: runtime)
            XCTFail("Closed runtime should reject connection")
        } catch {}
        XCTAssertTrue(events.values.isEmpty)
    }

    func testOldServiceCannotUnregisterReplacementLease() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-lease"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let old = MiniAppBluetoothService(owner: owner, coordinator: coordinator), replacement = MiniAppBluetoothService(owner: owner, coordinator: coordinator)
        let oldRuntime = MiniAppRuntime(), newRuntime = MiniAppRuntime(); try await old.connect(to: oldRuntime); try await replacement.connect(to: newRuntime)
        await old.unregisterAllOwned()
        _ = try await replacement.connect(peripheral: UUID())
        XCTAssertEqual(pool[owner].stopCount, 0)
        await newRuntime.shutdown()
    }

    func testPowerPermissionAndWriteBackpressureAreVisible() async throws {
        let pool = FakePool(), owner = MiniAppID("ble-write"), coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let service = MiniAppBluetoothService(owner: owner, coordinator: coordinator), runtime = MiniAppRuntime(); try await service.connect(to: runtime)
        pool[owner].power = .poweredOff
        XCTAssertThrowsError(try service.scan())
        pool[owner].power = .poweredOn; let c = try await service.connect(peripheral: UUID())
        pool[owner].writeFailure = .writeWouldBlock(maximum: 20)
        XCTAssertThrowsError(try service.write(Data([1]), to: .init(service: "s", characteristic: "c"), type: .withoutResponse, on: c)) {
            XCTAssertEqual($0 as? MiniAppBluetoothFailure, .writeWouldBlock(maximum: 20))
        }
    }

    func testAdvertisementSnapshotPreservesBinaryStandardFields() {
        let snapshot = MiniAppBluetoothAdvertisement(localName: "sensor", manufacturerData: Data([0, 255]),
            serviceData: ["180D": Data([1, 2])], serviceUUIDs: ["180D"], txPower: -4, isConnectable: true)
        XCTAssertEqual(snapshot.manufacturerData, Data([0, 255]))
        XCTAssertEqual(snapshot.serviceData["180D"], Data([1, 2]))
    }

    func testDuplicateServiceUUIDIndexDoesNotTrapAndMarksAmbiguity() {
        let result = miniAppBluetoothUniqueIndex(["180D:first", "180F:only", "180D:second"]) {
            String($0.prefix(4))
        }
        XCTAssertEqual(result.unique["180D"], "180D:first")
        XCTAssertEqual(result.unique["180F"], "180F:only")
        XCTAssertEqual(result.ambiguous, ["180D"])
    }
}

@MainActor private final class FakePool {
    var created: [MiniAppID] = []; var values: [MiniAppID: FakeCentral] = [:]
    lazy var make: MiniAppBluetoothCoordinator.NativeFactory = { [unowned self] owner, _ in self.created.append(owner); let value = FakeCentral(); self.values[owner] = value; return value }
    subscript(_ owner: MiniAppID) -> FakeCentral { values[owner]! }
}
@MainActor private final class FakeCentral: MiniAppBluetoothNativeCentral {
    var power: MiniAppBluetoothPower = .poweredOn, authorization: MiniAppBluetoothAuthorization = .allowed
    var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    var blockStop = false, blockDisconnect = false, stopCount = 0
    var connectGenerations: [UUID] = [], writeFailure: MiniAppBluetoothFailure?
    let stopEntered = Gate(), disconnectEntered = Gate(), releaseStop = Gate(), releaseDisconnect = Gate()
    func emit(_ event: MiniAppBluetoothEvent) { eventHandler?(event) }
    func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {}
    func stopScan() {}
    func connect(peripheral: UUID, generation: UUID) { connectGenerations.append(generation) }
    func disconnect(peripheral: UUID, generation: UUID) async { disconnectEntered.open(); if blockDisconnect { await releaseDisconnect.wait() } }
    func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID) {}
    func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID) {}
    func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType, peripheral: UUID, generation: UUID) throws { if let writeFailure { throw writeFailure } }
    func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    func stopAll() async { stopCount += 1; stopEntered.open(); if blockStop { await releaseStop.wait() } }
}
@MainActor private final class Gate {
    var openState = false; var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if openState { return }; await withCheckedContinuation { waiters.append($0) } }
    func open() { openState = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
}
@MainActor private final class EventBox { var values: [MiniAppBluetoothEvent] = [] }
