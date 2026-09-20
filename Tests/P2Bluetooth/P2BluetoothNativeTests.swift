#if os(iOS)
import XCTest
@testable import JibunKitCore
@preconcurrency import CoreBluetooth
@testable import JibunKit_App

@MainActor
final class P2BluetoothNativeTests: XCTestCase {
    func testProbePublishesTwoFeatureDefinitionsWithOwnedLifecycleAndLaunchHook() {
        let definitions = P2BluetoothProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-bluetooth-sensor"), MiniAppID("p2-bluetooth-accessory")])
        XCTAssertTrue(definitions.allSatisfy { $0.lifetime != nil && $0.onHostLaunch != nil && $0.onUnregister != nil })
        XCTAssertEqual(definitions.flatMap(\.permissions).map(\.id), ["bluetooth", "bluetooth"])
    }
    func testFeatureLifetimesAreIndependent() async throws {
        let fixture = try makeFixture(), definitions = fixture.definitions, store = fixture.store
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        definitions.forEach { store.setConsent(.allowed, for: $0.id, permissionID: "bluetooth") }
        try await definitions[0].lifetime?.start(); try await definitions[1].lifetime?.start()
        let runtimeB = definitions[1].lifetime?.runtime
        await definitions[0].lifetime?.stop()
        XCTAssertTrue(definitions[1].lifetime?.runtime === runtimeB)
        XCTAssertEqual(definitions[1].lifetime?.state, .running)
        await definitions[1].lifetime?.stop()
    }
    func testNativeAdapterUsesStableDistinctRestoreIdentifiersWithoutConstructingManager() {
        let a = MiniAppID("native-ble-a"), b = MiniAppID("native-ble-b")
        XCTAssertNotEqual(MiniAppBluetoothCoordinator.restorationIdentifier(for: a),
                          MiniAppBluetoothCoordinator.restorationIdentifier(for: b))
    }

    func testDiagnosticUUIDValidationAcceptsBLEFormsAndRejectsMalformedInput() {
        XCTAssertEqual(P2BluetoothDiagnosticInput.normalizedUUID(" 180d "), "180D")
        XCTAssertEqual(P2BluetoothDiagnosticInput.normalizedUUID("12345678"), "12345678")
        XCTAssertEqual(P2BluetoothDiagnosticInput.normalizedUUID("00112233445566778899aabbccddeeff"),
                       "00112233-4455-6677-8899-AABBCCDDEEFF")
        XCTAssertEqual(P2BluetoothDiagnosticInput.normalizedUUID("00112233-4455-6677-8899-aabbccddeeff"),
                       "00112233-4455-6677-8899-AABBCCDDEEFF")
        XCTAssertNil(P2BluetoothDiagnosticInput.normalizedUUID("180"))
        XCTAssertNil(P2BluetoothDiagnosticInput.normalizedUUID("ZZZZ"))
        XCTAssertNil(P2BluetoothDiagnosticInput.normalizedUUID("１８０Ｄ"))
    }

    func testDiagnosticHexValidationIsLosslessAndRejectsBeforeNativeUse() {
        XCTAssertEqual(P2BluetoothDiagnosticInput.data(hex: "00 ff 10"), Data([0, 255, 16]))
        XCTAssertEqual(P2BluetoothDiagnosticInput.hex(Data([0, 255, 16])), "00 FF 10")
        XCTAssertNil(P2BluetoothDiagnosticInput.data(hex: ""))
        XCTAssertNil(P2BluetoothDiagnosticInput.data(hex: "0"))
        XCTAssertNil(P2BluetoothDiagnosticInput.data(hex: "GG"))
    }

    func testPersistentDiagnosticRequiresRestorationChainAndBoundsSavedEpochs() throws {
        let suite = "P2BluetoothPersistentDiagnostic.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstID = UUID(), secondID = UUID(), owner = MiniAppID("restored-observation")
        let restoredGeneration = UUID(), otherGeneration = UUID()
        let first = P2BluetoothDiagnosticLog(defaults: defaults, processID: firstID, systemPID: 101,
            now: { Date(timeIntervalSince1970: 1) })
        first.record(.hostLaunch, owner: owner, message: "onHostLaunch admitted=true")
        first.record(.ownerOnRestore, owner: owner, message: "manual hook alone is not restoration")
        XCTAssertEqual(first.coldRestoreStatus, "このprocessではOS復元callback由来のconnectedを確認していません")

        let second = P2BluetoothDiagnosticLog(defaults: defaults, processID: secondID, systemPID: 202,
            now: { Date(timeIntervalSince1970: 2) })
        XCTAssertEqual(second.previousProcessID, firstID)
        second.record(.ownerOnRestore, owner: owner, message: "owner onRestore invoked")
        second.record(.consumerConnectBegin, owner: owner, message: "consumer-connect begin")
        second.record(.consumerConnectFailed, owner: owner, message: "consumer-connect failed")
        second.record(.restoredConnected, owner: owner, generation: restoredGeneration,
            message: "restored-connected delivered peripheral=11223344 generation=AABBCCDD")
        XCTAssertEqual(second.coldRestoreStatus, "このprocessではOS復元callback由来のconnectedを確認していません")
        second.appendNative(owner: MiniAppID("different-owner"),
            message: "willRestoreState callback restoredCount=1")
        XCTAssertEqual(second.coldRestoreStatus, "このprocessではOS復元callback由来のconnectedを確認していません")
        second.appendNative(owner: owner,
            message: "willRestoreState callback restoredCount=1")
        XCTAssertEqual(second.coldRestoreStatus, "このprocessではOS復元callback由来のconnectedを確認していません")
        second.record(.consumerConnectCompleted, owner: owner, message: "consumer-connect completed")
        XCTAssertEqual(second.coldRestoreStatus, "新processでOS復元callbackからconnectedを確認（OSの起動契機は未判定）")
        second.record(.restoredNotification, owner: owner, generation: otherGeneration,
            message: "first restored notification generation=DEADBEEF characteristic=2A37 bytes=2")
        XCTAssertEqual(second.coldRestoreStatus, "新processでOS復元callbackからconnectedを確認（OSの起動契機は未判定）")
        second.record(.restoredNotification, owner: owner, generation: restoredGeneration,
            message: "first restored notification generation=AABBCCDD characteristic=2A37 bytes=2")
        XCTAssertEqual(second.coldRestoreStatus, "新processでOS復元callbackと同一世代の初回通知を確認（OSの起動契機は未判定）")
        XCTAssertTrue(second.text.contains(secondID.uuidString))
        XCTAssertTrue(second.text.contains("generation=AABBCCDD"))

        for index in 0..<150 { second.record(.hostLaunch, owner: owner, message: "bounded-event-\(index)") }
        XCTAssertEqual(second.lines.count, 120)
        XCTAssertFalse(second.text.contains("bounded-event-0\n"))
        XCTAssertTrue(second.text.contains("bounded-event-149"))
        for index in 0..<100 { second.appendNative(owner: owner, message: "volatile-event-\(index)") }
        XCTAssertEqual(second.lines.count, 200)
        XCTAssertFalse(second.text.contains("volatile-event-0\n"))
        XCTAssertTrue(second.text.contains("volatile-event-99"))
        let reloaded = P2BluetoothDiagnosticLog(defaults: defaults, processID: UUID(), systemPID: 303,
            now: { Date(timeIntervalSince1970: 3) })
        XCTAssertEqual(reloaded.previousProcessID, secondID)
        XCTAssertEqual(reloaded.lines.count, 120)
        XCTAssertFalse(reloaded.text.contains("volatile-event-99"))

        let manualSuite = "P2BluetoothManualNewProcess.\(UUID().uuidString)"
        let manualDefaults = try XCTUnwrap(UserDefaults(suiteName: manualSuite))
        defer { manualDefaults.removePersistentDomain(forName: manualSuite) }
        _ = P2BluetoothDiagnosticLog(defaults: manualDefaults, processID: UUID(), systemPID: 1)
        let manual = P2BluetoothDiagnosticLog(defaults: manualDefaults, processID: UUID(), systemPID: 2)
        manual.record(.hostLaunch, owner: owner, message: "manual new process")
        manual.record(.consumerConnectCompleted, owner: owner, message: "consumer-connect completed")
        manual.record(.restoredConnected, owner: owner, generation: UUID(), message: "manual connected")
        XCTAssertEqual(manual.coldRestoreStatus, "このprocessではOS復元callback由来のconnectedを確認していません")

        let importedSuite = "P2BluetoothImportedDiagnostic.\(UUID().uuidString)"
        let importedDefaults = try XCTUnwrap(UserDefaults(suiteName: importedSuite))
        defer { importedDefaults.removePersistentDomain(forName: importedSuite) }
        let oversized = (0..<130).map { index in
            ["time": 0, "processID": UUID().uuidString, "owner": owner.rawValue,
             "kind": "hostLaunch", "message": index == 129 ? String(repeating: "x", count: 700) : "load-event-\(index)"] as [String: Any]
        }
        importedDefaults.set(try JSONSerialization.data(withJSONObject: oversized), forKey: "entries.v2")
        let imported = P2BluetoothDiagnosticLog(defaults: importedDefaults, processID: UUID(), systemPID: 3)
        XCTAssertEqual(imported.lines.count, 120)
        XCTAssertFalse(imported.text.contains("load-event-10\n"))
        XCTAssertTrue(imported.text.contains("load-event-11"))
        XCTAssertTrue(imported.text.contains(String(repeating: "x", count: 512)))
        XCTAssertFalse(imported.text.contains(String(repeating: "x", count: 513)))
    }

    func testLatestCompletedRestoreEvidenceSurvivesRestartAndRejectsMixedEvents() throws {
        let suite = "P2BluetoothHistoricalRestoreEvidence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = MiniAppID("historical-owner"), otherOwner = MiniAppID("historical-other")
        let completedProcess = UUID(), completedGeneration = UUID()
        var instant = Date(timeIntervalSince1970: 10)
        _ = P2BluetoothDiagnosticLog(defaults: defaults, processID: UUID(), systemPID: 500, now: { instant })
        let first = P2BluetoothDiagnosticLog(defaults: defaults, processID: completedProcess, systemPID: 501,
            now: { instant })
        first.appendNative(owner: owner, message: "willRestoreState callback restoredCount=1")
        first.record(.ownerOnRestore, owner: owner, message: "owner onRestore invoked")
        first.record(.consumerConnectCompleted, owner: owner, message: "consumer-connect completed")
        first.record(.restoredConnected, owner: owner, generation: completedGeneration,
                     message: "restored-connected")
        instant = Date(timeIntervalSince1970: 16)
        first.record(.restoredNotification, owner: owner, generation: completedGeneration,
                     message: "first restored notification")
        XCTAssertEqual(first.coldRestoreStatus,
                       "新processでOS復元callbackと同一世代の初回通知を確認（OSの起動契機は未判定）")

        instant = Date(timeIntervalSince1970: 20)
        let second = P2BluetoothDiagnosticLog(defaults: defaults, processID: UUID(), systemPID: 502,
            now: { instant })
        XCTAssertEqual(second.coldRestoreStatus, "このprocessではOS復元callback由来のconnectedを確認していません")
        XCTAssertTrue(second.latestCompletedRestoreEvidence.contains(Date(timeIntervalSince1970: 16).ISO8601Format()))
        XCTAssertTrue(second.latestCompletedRestoreEvidence.contains("process=\(completedProcess.uuidString)"))
        XCTAssertTrue(second.latestCompletedRestoreEvidence.contains("owner=\(owner.rawValue)"))
        XCTAssertTrue(second.latestCompletedRestoreEvidence.contains("generation=\(completedGeneration.uuidString)"))

        let incompleteGeneration = UUID(), wrongGeneration = UUID()
        second.appendNative(owner: owner, message: "willRestoreState callback restoredCount=1")
        second.record(.ownerOnRestore, owner: owner, message: "owner onRestore invoked")
        second.record(.consumerConnectCompleted, owner: owner, message: "consumer-connect completed")
        second.record(.restoredConnected, owner: owner, generation: incompleteGeneration,
                      message: "restored-connected")
        second.record(.restoredNotification, owner: otherOwner, generation: incompleteGeneration,
                      message: "wrong owner")
        second.record(.restoredNotification, owner: owner, generation: wrongGeneration,
                      message: "wrong generation")
        XCTAssertEqual(second.coldRestoreStatus,
                       "新processでOS復元callbackからconnectedを確認（OSの起動契機は未判定）")
        XCTAssertTrue(second.latestCompletedRestoreEvidence.contains("process=\(completedProcess.uuidString)"))
        XCTAssertFalse(second.latestCompletedRestoreEvidence.contains(incompleteGeneration.uuidString))

        instant = Date(timeIntervalSince1970: 30)
        let thirdProcess = UUID()
        let third = P2BluetoothDiagnosticLog(defaults: defaults, processID: thirdProcess, systemPID: 503,
            now: { instant })
        third.record(.restoredNotification, owner: owner, generation: incompleteGeneration,
                     message: "matching owner and generation but different process")
        XCTAssertTrue(third.latestCompletedRestoreEvidence.contains("process=\(completedProcess.uuidString)"))
        XCTAssertFalse(third.latestCompletedRestoreEvidence.contains(incompleteGeneration.uuidString))

        instant = Date(timeIntervalSince1970: 40)
        let reloaded = P2BluetoothDiagnosticLog(defaults: defaults, processID: UUID(), systemPID: 504,
            now: { instant })
        XCTAssertEqual(reloaded.previousProcessID, thirdProcess)
        XCTAssertTrue(reloaded.latestCompletedRestoreEvidence.contains("process=\(completedProcess.uuidString)"))
        XCTAssertTrue(reloaded.latestCompletedRestoreEvidence.contains("generation=\(completedGeneration.uuidString)"))
    }

    func testDiagnosticStateShowsDiscoveryReadWriteAndNotifyCallbacks() async throws {
        let suite = "P2BluetoothDiagnostic.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MiniAppConsentStore(defaults: defaults), pool = P2BluetoothNativeFakePool()
        let feature = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-diagnostic"), title: "Diagnostic",
            coordinator: MiniAppBluetoothCoordinator(factory: pool.make), consents: store)
        store.setConsent(.allowed, for: feature.id, permissionID: "bluetooth")
        try await feature.lifetime.start()
        let peripheral = UUID(); feature.connect(.init(id: peripheral))
        for _ in 0..<20 where feature.connection == nil { await Task.yield() }
        let connection = try XCTUnwrap(feature.connection)
        let native = try XCTUnwrap(pool.centrals.first)
        let key = MiniAppBluetoothCharacteristic(service: "180D", characteristic: "2A37")
        feature.serviceUUID = "invalid"; feature.read()
        feature.serviceUUID = "180D"; feature.writeHex = "GG"; feature.write()
        XCTAssertEqual(native.readCalls, 0); XCTAssertEqual(native.writeCalls, 0)
        feature.writeHex = "01"
        native.emit(.services(peripheral: connection.peripheral, generation: connection.generation, identifiers: ["180D", "180F"]))
        native.emit(.characteristics(peripheral: connection.peripheral, generation: connection.generation,
                                     service: "180D", identifiers: ["2A37", "2A38"]))
        feature.read()
        native.emit(.value(peripheral: connection.peripheral, generation: connection.generation,
                           characteristic: key, data: Data([1, 2]), notifying: false))
        native.emit(.value(peripheral: connection.peripheral, generation: connection.generation,
                           characteristic: key, data: Data([0, 255]), notifying: true))
        native.emit(.writeCompleted(peripheral: connection.peripheral, generation: connection.generation, characteristic: key))
        native.emit(.notificationChanged(peripheral: connection.peripheral, generation: connection.generation,
                                         characteristic: key, enabled: true))
        XCTAssertEqual(feature.discoveredServices, ["180D", "180F"])
        XCTAssertEqual(feature.discoveredCharacteristics, ["2A37", "2A38"])
        XCTAssertEqual(feature.lastReadHex, "2A37: 01 02")
        XCTAssertEqual(feature.lastNotifyHex, "2A37: 00 FF")
        XCTAssertEqual(feature.writeResult, "成功: 2A37")
        XCTAssertEqual(feature.notifyResult, "2A37: 購読中")
        await feature.lifetime.stop(); await feature.service.unregisterAllOwned()
    }

    func testRestoredConnectedEventRecoversOperationalConnectionTicket() async throws {
        let suite = "P2BluetoothRestoredDiagnostic.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MiniAppConsentStore(defaults: defaults), pool = P2BluetoothNativeFakePool()
        let diagnostics = P2BluetoothDiagnosticLog(defaults: defaults, processID: UUID(), systemPID: 404,
            now: { Date(timeIntervalSince1970: 4) })
        let feature = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-restored-ui"), title: "Restored",
            coordinator: MiniAppBluetoothCoordinator(factory: pool.make), consents: store,
            diagnostics: diagnostics)
        store.setConsent(.allowed, for: feature.id, permissionID: "bluetooth")
        try feature.definition.onHostLaunch?()
        let native = try XCTUnwrap(pool.centrals.first)
        let peripheral = UUID(), generation = UUID()
        native.emit(.connected(peripheral: peripheral, generation: generation, restored: true))
        for _ in 0..<20 where feature.lifetime.state != .running { await Task.yield() }
        let connection = try XCTUnwrap(feature.connection)
        XCTAssertEqual(connection.peripheral, peripheral)
        XCTAssertEqual(connection.generation, generation)
        XCTAssertEqual(feature.status, "復元接続済み（診断操作可能）")
        let key = MiniAppBluetoothCharacteristic(service: "180D", characteristic: "2A37")
        native.emit(.value(peripheral: peripheral, generation: generation, characteristic: key,
                           data: Data([0x11, 0x12]), notifying: true))
        native.emit(.value(peripheral: peripheral, generation: generation, characteristic: key,
                           data: Data([0xFE]), notifying: true))
        XCTAssertEqual(diagnostics.text.components(separatedBy: "first restored notification generation=").count - 1, 1)
        XCTAssertTrue(diagnostics.text.contains("generation=\(generation.uuidString.suffix(8))"))
        XCTAssertTrue(diagnostics.text.contains("characteristic=2A37 bytes=2"))
        XCTAssertFalse(diagnostics.text.contains("11 12"))
        await feature.lifetime.stop(); await feature.service.unregisterAllOwned()
    }

    func testNotificationAfterRestoredDisconnectAndNormalReconnectIsNotClassifiedAsRestored() async throws {
        let suite = "P2BluetoothRestoredGenerationBoundary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MiniAppConsentStore(defaults: defaults), pool = P2BluetoothNativeFakePool()
        let diagnostics = P2BluetoothDiagnosticLog(defaults: defaults, processID: UUID(), systemPID: 405)
        let feature = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-generation-boundary"), title: "Boundary",
            coordinator: MiniAppBluetoothCoordinator(factory: pool.make), consents: store,
            diagnostics: diagnostics)
        store.setConsent(.allowed, for: feature.id, permissionID: "bluetooth")
        try feature.definition.onHostLaunch?()
        let native = try XCTUnwrap(pool.centrals.first)
        let peripheral = UUID(), restoredGeneration = UUID()
        native.emit(.connected(peripheral: peripheral, generation: restoredGeneration, restored: true))
        for _ in 0..<20 where feature.lifetime.state != .running { await Task.yield() }
        XCTAssertEqual(feature.connection?.generation, restoredGeneration)

        native.emit(.disconnected(peripheral: peripheral, generation: restoredGeneration, message: nil))
        feature.connect(.init(id: peripheral))
        for _ in 0..<20 where feature.connection == nil { await Task.yield() }
        let normalConnection = try XCTUnwrap(feature.connection)
        XCTAssertNotEqual(normalConnection.generation, restoredGeneration)
        native.emit(.connected(peripheral: peripheral, generation: normalConnection.generation, restored: false))
        native.emit(.value(peripheral: peripheral, generation: normalConnection.generation,
                           characteristic: .init(service: "180D", characteristic: "2A37"),
                           data: Data([0x23, 0x24]), notifying: true))

        XCTAssertEqual(feature.lastNotifyHex, "2A37: 23 24")
        XCTAssertFalse(diagnostics.text.contains("first restored notification generation="))
        await feature.lifetime.stop(); await feature.service.unregisterAllOwned()
    }

    func testManagementDisableStopsOnlySelectedFeature() async throws {
        let fixture = try makeFixture(), definitions = fixture.definitions, featureConsents = fixture.store
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        definitions.forEach { featureConsents.setConsent(.allowed, for: $0.id, permissionID: "bluetooth") }
        let suite = "P2BluetoothManagement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let management = MiniAppManagement(registrations: definitions.map { definition in
            .init(id: definition.id, lifetime: definition.lifetime,
                  unregister: { try await definition.onUnregister?() })
        }, defaults: defaults, consents: MiniAppConsentStore(defaults: defaults))
        try await definitions[0].lifetime?.start(); try await definitions[1].lifetime?.start()
        let runtimeB = definitions[1].lifetime?.runtime
        fixture.features[1].status = "B noninitial"
        try await management.disable(definitions[0].id)
        XCTAssertTrue(definitions[1].lifetime?.runtime === runtimeB)
        XCTAssertEqual(fixture.features[1].status, "B noninitial")
        await definitions[1].lifetime?.stop()
        await fixture.features[1].service.unregisterAllOwned()
    }

    func testRestoredGATTGraphIndexesOriginalNativeObjectIdentities() {
        let service = CBMutableService(type: CBUUID(string: "180D"), primary: true)
        let characteristic = CBMutableCharacteristic(type: CBUUID(string: "2A37"),
            properties: [.read, .notify], value: nil, permissions: [.readable])
        service.characteristics = [characteristic]
        let restored = MiniAppBluetoothRestoredAttributes([service])
        XCTAssertTrue(restored.services["180D"] === service)
        XCTAssertTrue(restored.characteristics[.init(service: "180D", characteristic: "2A37")] === characteristic)
        XCTAssertTrue(restored.ambiguousServices.isEmpty)
    }

    func testRestoredGATTGraphDoesNotGuessAmongRepeatedUUIDs() {
        let first = CBMutableService(type: CBUUID(string: "180D"), primary: true)
        let second = CBMutableService(type: CBUUID(string: "180D"), primary: true)
        let c1 = CBMutableCharacteristic(type: CBUUID(string: "2A37"),
            properties: [.notify], value: nil, permissions: [.readable])
        let c2 = CBMutableCharacteristic(type: CBUUID(string: "2A37"),
            properties: [.notify], value: nil, permissions: [.readable])
        first.characteristics = [c1]; second.characteristics = [c2]
        let duplicateServices = MiniAppBluetoothRestoredAttributes([first, second])
        XCTAssertEqual(duplicateServices.ambiguousServices, ["180D"])
        XCTAssertTrue(duplicateServices.characteristics.isEmpty)
        first.characteristics = [c1, c2]
        XCTAssertTrue(MiniAppBluetoothRestoredAttributes([first]).characteristics.isEmpty)
        XCTAssertTrue(MiniAppBluetoothRestoredAttributes([]).services.isEmpty)
    }

    func testRestoredNotificationBeforeFeatureAdmissionIsDeliveredInOrderAndStoppedOwnerIsClosed() async throws {
        let pool = P2BluetoothNativeFakePool()
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let owner = MiniAppID("restored-early-notify")
        coordinator.prepareRestoration(owner: owner, admitted: true, onRestore: {})
        let native = try XCTUnwrap(pool.centrals.first)
        let peripheral = UUID(), generation = UUID()
        let key = MiniAppBluetoothCharacteristic(service: "180D", characteristic: "2A37")
        let connected = MiniAppBluetoothEvent.connected(peripheral: peripheral, generation: generation, restored: true)
        let value = MiniAppBluetoothEvent.value(peripheral: peripheral, generation: generation,
            characteristic: key, data: Data([0x11, 0x12]), notifying: true)
        native.emit(connected)
        native.emit(.value(peripheral: peripheral, generation: UUID(), characteristic: key,
            data: Data([0xFF]), notifying: true))
        native.emit(value)
        let received = P2BluetoothReceivedEvents()
        let lease = await coordinator.connect(owner: owner) { received.values.append($0) }
        XCTAssertEqual(received.values, [connected, value])
        await coordinator.disconnect(lease)
        native.emit(value)
        XCTAssertEqual(received.values, [connected, value])
    }

    func testRestoredStartupBufferIsBoundedAndReportsOverflow() async throws {
        let pool = P2BluetoothNativeFakePool()
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let owner = MiniAppID("restored-overflow")
        coordinator.prepareRestoration(owner: owner, admitted: true, onRestore: {})
        let native = try XCTUnwrap(pool.centrals.first)
        let peripheral = UUID(), generation = UUID()
        native.emit(.connected(peripheral: peripheral, generation: generation, restored: true))
        let key = MiniAppBluetoothCharacteristic(service: "180D", characteristic: "2A37")
        for _ in 0..<300 {
            native.emit(.value(peripheral: peripheral, generation: generation,
                characteristic: key, data: Data([1]), notifying: true))
        }
        let received = P2BluetoothReceivedEvents()
        let lease = await coordinator.connect(owner: owner) { received.values.append($0) }
        XCTAssertEqual(received.values.count, 256)
        let last = try XCTUnwrap(received.values.last)
        guard case .failed(_, _, let message) = last else {
            return XCTFail("Truncated restoration must be reported")
        }
        XCTAssertTrue(message.contains("overflow"))
        await coordinator.disconnect(lease)
    }

    private func makeFixture() throws -> (features: [P2BluetoothFeature], definitions: [MiniAppDefinition],
                                           store: MiniAppConsentStore, defaults: UserDefaults, suite: String) {
        let suite = "P2BluetoothFixture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = MiniAppConsentStore(defaults: defaults)
        let pool = P2BluetoothNativeFakePool()
        let coordinator = MiniAppBluetoothCoordinator(factory: pool.make)
        let features = [
            P2BluetoothFeature(id: MiniAppID("p2-bluetooth-sensor"), title: "BLE Sensor", coordinator: coordinator, consents: store),
            P2BluetoothFeature(id: MiniAppID("p2-bluetooth-accessory"), title: "BLE Accessory", coordinator: coordinator, consents: store),
        ]
        return (features, features.map(\.definition), store, defaults, suite)
    }
}

@MainActor private final class P2BluetoothReceivedEvents {
    var values: [MiniAppBluetoothEvent] = []
}

@MainActor private final class P2BluetoothNativeFakePool {
    var centrals: [P2BluetoothNativeFakeCentral] = []
    lazy var make: MiniAppBluetoothCoordinator.NativeFactory = { [self] _, _ in
        let central = P2BluetoothNativeFakeCentral(); self.centrals.append(central); return central
    }
}

@MainActor private final class P2BluetoothNativeFakeCentral: MiniAppBluetoothNativeCentral {
    var power: MiniAppBluetoothPower = .poweredOn
    var authorization: MiniAppBluetoothAuthorization = .allowed
    var eventHandler: (@MainActor @Sendable (MiniAppBluetoothEvent) -> Void)?
    var readCalls = 0, writeCalls = 0
    func emit(_ event: MiniAppBluetoothEvent) { eventHandler?(event) }
    func scan(serviceUUIDs: [String]?, allowDuplicates: Bool) {}
    func stopScan() {}
    func connect(peripheral: UUID, generation: UUID) {}
    func disconnect(peripheral: UUID, generation: UUID) async {}
    func discoverServices(_ serviceUUIDs: [String]?, peripheral: UUID, generation: UUID) {}
    func discoverCharacteristics(_ characteristicUUIDs: [String]?, service: String, peripheral: UUID, generation: UUID) {}
    func read(_ characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) { readCalls += 1 }
    func write(_ data: Data, to characteristic: MiniAppBluetoothCharacteristic, type: MiniAppBluetoothWriteType,
               peripheral: UUID, generation: UUID) throws { writeCalls += 1 }
    func setNotify(_ enabled: Bool, for characteristic: MiniAppBluetoothCharacteristic, peripheral: UUID, generation: UUID) {}
    func stopAll() async {}
}
#endif
