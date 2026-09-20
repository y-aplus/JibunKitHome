import XCTest
@testable import JibunKitCore
#if os(iOS)
import CoreLocation
#endif
#if os(iOS)
import CoreLocation
#endif

@MainActor
final class MiniAppLocationCoordinatorTests: XCTestCase {
    func testReplacedServiceCannotStartOrCancelTheNewConnection() async throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let old = MiniAppLocationService(owner: MiniAppID("a"), coordinator: coordinator) { true }
        let current = MiniAppLocationService(owner: MiniAppID("a"), coordinator: coordinator) { true }
        let oldRuntime = MiniAppRuntime(), currentRuntime = MiniAppRuntime()
        try old.connect(to: oldRuntime); try current.connect(to: currentRuntime)
        let generation = try current.startUpdates(.init(desiredAccuracy: 17))
        XCTAssertThrowsError(try old.startUpdates(.init(desiredAccuracy: 99)))
        XCTAssertThrowsError(try old.unregisterAll())
        await oldRuntime.shutdown()
        XCTAssertEqual(native.configurations[generation]?.desiredAccuracy, 17)
        await currentRuntime.shutdown()
        XCTAssertNil(native.configurations[generation])
    }

    func testReleasedServiceStillStopsItsOwnedNativeUpdatesOnRuntimeShutdown() async throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        var service: MiniAppLocationService? = MiniAppLocationService(owner: MiniAppID("a"), coordinator: coordinator) { true }
        let runtime = MiniAppRuntime()
        try service?.connect(to: runtime)
        let generation = try XCTUnwrap(service?.startUpdates(.init(desiredAccuracy: 27)))
        service = nil
        await runtime.shutdown()
        XCTAssertNil(native.configurations[generation])
    }

    func testCorruptPartialMetadataCannotBeOverwrittenByMonitoringFailure() throws {
        let a = try MiniAppLocationRegistration(owner: MiniAppID("a"), localID: "same", region: fence())
        let duplicate = try MiniAppLocationRegistration(owner: a.owner, localID: a.localID, region: fence())
        let store = LocationStore(); store.values = [a, duplicate]
        let native = LocationNative()
        let coordinator = MiniAppLocationCoordinator(native: native, store: store)
        XCTAssertNotNil(coordinator.persistenceFailure)
        native.send(.monitoringFailed(identifier: a.id, message: "late"))
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(store.values, [a, duplicate])
    }

    func testRestoreSuppressesOnlyOwnerColdEventsAndDoesNotUndoManagementClose() async throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let a = MiniAppLocationService(owner: MiniAppID("a"), coordinator: coordinator) { true }
        let b = MiniAppLocationService(owner: MiniAppID("b"), coordinator: coordinator) { true }
        let valuesA = LocationEvents(), valuesB = LocationEvents()
        a.receive = { valuesA.values.append($0) }; b.receive = { valuesB.values.append($0) }
        try a.externalAccess.prepare(true); try b.externalAccess.prepare(true)
        let ar = try coordinator.register(owner: a.owner, localID: "a", region: fence(), featureConsent: true)
        let br = try coordinator.register(owner: b.owner, localID: "b", region: fence(), featureConsent: true)
        let restore = a.externalAccess.restoreLifecycle(nil)
        try await restore.stop()
        native.send(.entered(identifier: ar.id)); native.send(.entered(identifier: br.id))
        XCTAssertTrue(valuesA.values.isEmpty); XCTAssertEqual(valuesB.values, [.entered(br)])
        try await a.externalAccess.close()
        try await restore.resume()
        try a.reconnectPersistedMonitoring()
        XCTAssertFalse(native.ids.contains(ar.id)); XCTAssertTrue(native.ids.contains(br.id))
        XCTAssertEqual(valuesB.values, [.entered(br)])
    }

    func testFeatureConsentPrecedesOSPromptAndNativeWork() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        XCTAssertThrowsError(try coordinator.requestAuthorization(owner: MiniAppID("a"), featureConsent: false, request: .always)) {
            XCTAssertEqual($0 as? MiniAppLocationFailure, .featureConsentDenied)
        }
        XCTAssertThrowsError(try coordinator.register(owner: MiniAppID("a"), localID: "home", region: fence(), featureConsent: false))
        XCTAssertTrue(native.actions.isEmpty)
    }

    func testTwoOwnersWithSameLocalIDReceiveOnlyTheirRegistration() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let a = LocationEvents(), b = LocationEvents()
        coordinator.connect(owner: MiniAppID("a")) { a.values.append($0) }
        coordinator.connect(owner: MiniAppID("b")) { b.values.append($0) }
        let ar = try coordinator.register(owner: MiniAppID("a"), localID: "same", region: fence(), featureConsent: true)
        let br = try coordinator.register(owner: MiniAppID("b"), localID: "same", region: fence(), featureConsent: true)
        native.send(.entered(identifier: ar.id)); native.send(.exited(identifier: br.id))
        XCTAssertEqual(a.values, [.entered(ar)]); XCTAssertEqual(b.values, [.exited(br)])
        XCTAssertNotEqual(ar.id, br.id)
    }

    func testOwnerUnregisterPreservesOtherOwnerAndUnknownNativeRegion() throws {
        let native = LocationNative(); native.authorization = .always
        native.ids = ["host-owned"]
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let a = try coordinator.register(owner: MiniAppID("a"), localID: "a", region: fence(), featureConsent: true)
        let b = try coordinator.register(owner: MiniAppID("b"), localID: "b", region: fence(), featureConsent: true)
        try coordinator.unregisterAll(owner: MiniAppID("a"))
        XCTAssertTrue(native.ids.contains("host-owned")); XCTAssertFalse(native.ids.contains(a.id)); XCTAssertTrue(native.ids.contains(b.id))
    }

    func testSharedTwentyRegionLimitIncludesUnknownNativeRegistrations() throws {
        let native = LocationNative(); native.authorization = .always
        native.ids = Set((0..<20).map { "external-\($0)" })
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        XCTAssertThrowsError(try coordinator.register(owner: MiniAppID("a"), localID: "overflow", region: fence(), featureConsent: true)) {
            XCTAssertEqual($0 as? MiniAppLocationFailure, .capacityExceeded(limit: 20, occupied: 20))
        }
        XCTAssertEqual(native.ids.count, 20)
    }

    func testFailedPersistenceRollsBackReservationBeforeNativeStart() {
        let native = LocationNative(); native.authorization = .always
        let store = LocationStore(); store.writeError = StoreError.failed
        let coordinator = MiniAppLocationCoordinator(native: native, store: store)
        XCTAssertThrowsError(try coordinator.register(owner: MiniAppID("a"), localID: "x", region: fence(), featureConsent: true))
        XCTAssertTrue(coordinator.allRegistrations.isEmpty); XCTAssertTrue(native.ids.isEmpty)
    }

    func testLateUpdateFromStoppedGenerationIsDropped() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let events = LocationEvents()
        coordinator.connect(owner: MiniAppID("a")) { events.values.append($0) }
        let generation = try coordinator.startUpdates(owner: MiniAppID("a"), featureConsent: true,
            configuration: .init(desiredAccuracy: 10))
        try coordinator.stopUpdates(owner: MiniAppID("a"), generation: generation)
        native.send(.locations(generation: generation, [.init(latitude: 1, longitude: 2, horizontalAccuracy: 3, timestamp: .distantPast)]))
        XCTAssertTrue(events.values.isEmpty)
    }

    func testPersistedRegionsReconnectWithoutRestartingContinuousUpdates() throws {
        let native = LocationNative(); native.authorization = .always
        let persisted = try MiniAppLocationRegistration(owner: MiniAppID("a"), localID: "cold", region: fence())
        let store = LocationStore(); store.values = [persisted]
        let coordinator = MiniAppLocationCoordinator(native: native, store: store)
        let admission = MiniAppLocationAdmission(); admission.setAllowed(true)
        coordinator.prepare(owner: MiniAppID("a"), admission: admission) { _ in }
        try coordinator.reconnectPersistedMonitoring(owner: MiniAppID("a"))
        XCTAssertEqual(native.ids, [persisted.id])
        XCTAssertFalse(native.actions.contains(where: { $0.hasPrefix("updates:") }))
    }

    func testBackgroundAndForegroundPreserveConfigurationWithWhenInUse() throws {
        let native = LocationNative(); native.authorization = .whenInUse
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        _ = try coordinator.startUpdates(owner: MiniAppID("a"), featureConsent: true,
                                         configuration: .init(desiredAccuracy: 100, background: false))
        _ = try coordinator.startUpdates(owner: MiniAppID("b"), featureConsent: true,
                                         configuration: .init(desiredAccuracy: 5, background: true))
        XCTAssertEqual(native.actions.filter { $0.hasPrefix("updates:") }.count, 2)
        XCTAssertEqual(native.configurations.values.map(\.desiredAccuracy).sorted(), [5, 100])
        XCTAssertEqual(native.configurations.values.filter(\.background).count, 1)
    }

    func testAuthorizationRevocationStopsEveryUpdateButKeepsDurableRegions() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let registration = try coordinator.register(owner: MiniAppID("a"), localID: "durable", region: fence(), featureConsent: true)
        _ = try coordinator.startUpdates(owner: MiniAppID("a"), featureConsent: true, configuration: .init(desiredAccuracy: 10))
        _ = try coordinator.startUpdates(owner: MiniAppID("b"), featureConsent: true, configuration: .init(desiredAccuracy: 100))
        native.authorization = .denied; native.send(.authorizationChanged(.denied))
        XCTAssertEqual(native.actions.filter { $0.hasPrefix("stop-updates:") }.count, 2)
        XCTAssertEqual(coordinator.allRegistrations, [registration])
    }

    func testMonitoringFailureReleasesOwnedReservation() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let registration = try coordinator.register(owner: MiniAppID("a"), localID: "failed", region: fence(), featureConsent: true)
        native.send(.monitoringFailed(identifier: registration.id, message: "limit"))
        XCTAssertTrue(coordinator.allRegistrations.isEmpty)
    }

    func testFeatureConsentRevocationStopsAndRemovesOnlyThatOwner() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let a = try coordinator.register(owner: MiniAppID("a"), localID: "a", region: fence(), featureConsent: true)
        let b = try coordinator.register(owner: MiniAppID("b"), localID: "b", region: fence(), featureConsent: true)
        _ = try coordinator.startUpdates(owner: MiniAppID("a"), featureConsent: true, configuration: .init(desiredAccuracy: 10))
        try coordinator.revoke(owner: MiniAppID("a"))
        XCTAssertFalse(native.ids.contains(a.id)); XCTAssertTrue(native.ids.contains(b.id))
        XCTAssertEqual(coordinator.allRegistrations, [b])
        XCTAssertEqual(native.actions.filter { $0.hasPrefix("stop-updates:") }.count, 1)
    }

    func testClosedRuntimeConnectionRollsBackAndRejectsOperations() async {
        let native = LocationNative(); native.authorization = .always
        let service = MiniAppLocationService(owner: MiniAppID("a"),
            coordinator: MiniAppLocationCoordinator(native: native, store: LocationStore())) { true }
        let runtime = MiniAppRuntime(); await runtime.shutdown()
        XCTAssertThrowsError(try service.connect(to: runtime))
        XCTAssertThrowsError(try service.startUpdates(.init(desiredAccuracy: 10))) {
            XCTAssertEqual($0 as? MiniAppLocationFailure, .stopped)
        }
        XCTAssertTrue(native.configurations.isEmpty)
    }

    func testLateOldRuntimeCleanupDoesNotDisconnectNewGeneration() async throws {
        let native = LocationNative(); native.authorization = .always
        let service = MiniAppLocationService(owner: MiniAppID("a"),
            coordinator: MiniAppLocationCoordinator(native: native, store: LocationStore())) { true }
        let old = MiniAppRuntime(), current = MiniAppRuntime()
        try service.connect(to: old); try service.connect(to: current)
        await old.shutdown()
        let generation = try service.startUpdates(.init(desiredAccuracy: 42))
        XCTAssertEqual(native.configurations[generation]?.desiredAccuracy, 42)
        await current.shutdown()
        XCTAssertTrue(native.actions.contains("stop-updates:\(generation)"))
    }

    func testCorruptStoreIsVisibleAndRefusesDestructiveWrite() {
        let native = LocationNative(); native.authorization = .always
        let store = LocationStore(); store.readError = StoreError.failed
        let coordinator = MiniAppLocationCoordinator(native: native, store: store)
        XCTAssertNotNil(coordinator.persistenceFailure)
        XCTAssertThrowsError(try coordinator.register(owner: MiniAppID("a"), localID: "x",
                                                       region: fence(), featureConsent: true)) {
            guard let failure = $0 as? MiniAppLocationFailure,
                  case .persistenceUnavailable = failure else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
        XCTAssertEqual(store.writeCount, 0)
    }

    func testFailedOwnerRemovalRollsBackAndSurvivesRestartWithOtherOwner() throws {
        let native = LocationNative(); native.authorization = .always
        let store = LocationStore()
        let coordinator = MiniAppLocationCoordinator(native: native, store: store)
        let a = try coordinator.register(owner: MiniAppID("a"), localID: "a", region: fence(), featureConsent: true)
        let b = try coordinator.register(owner: MiniAppID("b"), localID: "b", region: fence(), featureConsent: true)
        store.writeError = StoreError.failed
        XCTAssertThrowsError(try coordinator.unregisterAll(owner: MiniAppID("a")))
        XCTAssertEqual(Set(coordinator.allRegistrations.map(\.id)), [a.id, b.id])
        store.writeError = nil
        let restarted = MiniAppLocationCoordinator(native: LocationNative(), store: store)
        XCTAssertEqual(Set(restarted.allRegistrations.map(\.id)), [a.id, b.id])
    }

    func testUnknownMonitoringFailureIsNotBroadcastButGlobalFailureIs() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let events = LocationEvents(); coordinator.connect(owner: MiniAppID("a")) { events.values.append($0) }
        native.send(.monitoringFailed(identifier: "unknown", message: "foreign"))
        XCTAssertTrue(events.values.isEmpty)
        native.send(.monitoringFailed(identifier: nil, message: "global"))
        XCTAssertEqual(events.values, [.monitoringFailed(nil, "global")])
    }

    func testColdHookFiltersDisabledOwnerAndDeliversEnabledOwnerBeforeViewConnection() throws {
        let a = try MiniAppLocationRegistration(owner: MiniAppID("a"), localID: "a", region: fence())
        let b = try MiniAppLocationRegistration(owner: MiniAppID("b"), localID: "b", region: fence())
        let store = LocationStore(); store.values = [a, b]
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: store)
        let admissionA = MiniAppLocationAdmission(), admissionB = MiniAppLocationAdmission()
        admissionA.setAllowed(false); admissionB.setAllowed(true)
        let eventsA = LocationEvents(), eventsB = LocationEvents()
        coordinator.prepare(owner: a.owner, admission: admissionA) { eventsA.values.append($0) }
        coordinator.prepare(owner: b.owner, admission: admissionB) { eventsB.values.append($0) }
        try coordinator.reconnectPersistedMonitoring(owner: a.owner)
        try coordinator.reconnectPersistedMonitoring(owner: b.owner)
        XCTAssertFalse(native.ids.contains(a.id)); XCTAssertTrue(native.ids.contains(b.id))
        native.send(.entered(identifier: b.id))
        XCTAssertTrue(eventsA.values.isEmpty); XCTAssertEqual(eventsB.values, [.entered(b)])
        try coordinator.revoke(owner: a.owner)
        XCTAssertEqual(eventsB.values, [.entered(b)], "A management must preserve B's noninitial state")
    }

    func testBeaconMinorWithoutMajorAndOversizeRadiusAreExplained() throws {
        XCTAssertThrowsError(try MiniAppLocationRegistration(owner: MiniAppID("a"), localID: "bad",
            region: .beacon(uuid: UUID(), major: nil, minor: 1, notifyOnEntry: true, notifyOnExit: true))) {
            XCTAssertEqual($0 as? MiniAppLocationFailure, .invalidRegistration)
        }
        let native = LocationNative(); native.authorization = .always; native.maximumRegionMonitoringDistance = 50
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        XCTAssertThrowsError(try coordinator.register(owner: MiniAppID("a"), localID: "wide",
            region: .geofence(latitude: 1, longitude: 2, radius: 51, notifyOnEntry: true, notifyOnExit: true),
            featureConsent: true)) {
            XCTAssertEqual($0 as? MiniAppLocationFailure, .radiusExceedsMaximum(requested: 51, maximum: 50))
        }
    }

    func testDecodedRegistrationRevalidatesOwnerAndRegion() throws {
        let valid = try MiniAppLocationRegistration(owner: MiniAppID("a"), localID: "x", region: fence())
        let data = try JSONEncoder().encode(valid)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let corrupt = Data(text.replacingOccurrences(of: "\"owner\":\"a\"", with: "\"owner\":\"INVALID\"").utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MiniAppLocationRegistration.self, from: corrupt))
    }

    func testColdServiceDoesNotReconnectWhenFeatureConsentWasRevoked() throws {
        let registration = try MiniAppLocationRegistration(owner: MiniAppID("a"), localID: "old", region: fence())
        let store = LocationStore(); store.values = [registration]
        let native = LocationNative(); native.authorization = .always
        let service = MiniAppLocationService(owner: registration.owner,
            coordinator: MiniAppLocationCoordinator(native: native, store: store)) { false }
        try service.externalAccess.prepare(true)
        try service.reconnectPersistedMonitoring()
        XCTAssertTrue(native.ids.isEmpty); XCTAssertTrue(store.values.isEmpty)
    }
}

private func fence() -> MiniAppLocationRegion {
    .geofence(latitude: 35, longitude: 139, radius: 100, notifyOnEntry: true, notifyOnExit: true)
}

private enum StoreError: Error { case failed }
@MainActor private final class LocationEvents { var values: [MiniAppLocationEvent] = [] }
private final class LocationStore: MiniAppLocationRegistrationStore, @unchecked Sendable {
    var values: [MiniAppLocationRegistration] = []
    var writeError: Error?
    var readError: Error?
    var writeCount = 0
    func read() throws -> [MiniAppLocationRegistration] { if let readError { throw readError }; return values }
    func write(_ registrations: [MiniAppLocationRegistration]) throws {
        writeCount += 1; if let writeError { throw writeError }; values = registrations
    }
}

@MainActor private final class LocationNative: MiniAppLocationNativeClient {
    var authorization: MiniAppLocationAuthorization = .notDetermined
    var ids: Set<String> = []
    var monitoredRegionIDs: Set<String> { ids }
    var monitoringAvailability: [MiniAppLocationMonitoringKind: Bool] = [.geofence: true, .beacon: true]
    func isMonitoringAvailable(for kind: MiniAppLocationMonitoringKind) -> Bool { monitoringAvailability[kind] ?? false }
    var maximumRegionMonitoringDistance: Double = 100_000
    var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)?
    #if os(iOS)
    var coreLocationHandler: (@MainActor (UUID, [CLLocation]) -> Void)?
    #endif
    var actions: [String] = []
    var configurations: [UUID: MiniAppLocationUpdateConfiguration] = [:]
    func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) { actions.append("permission:\(request.rawValue)") }
    func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID) {
        configurations[generation] = configuration; actions.append("updates:\(generation)")
    }
    func stopUpdates(generation: UUID) { configurations[generation] = nil; actions.append("stop-updates:\(generation)") }
    func startMonitoring(_ registration: MiniAppLocationRegistration) { ids.insert(registration.id); actions.append("monitor:\(registration.id)") }
    func stopMonitoring(identifier: String) { ids.remove(identifier); actions.append("stop:\(identifier)") }
    func requestState(identifier: String) { actions.append("state:\(identifier)") }
    func send(_ event: MiniAppLocationNativeEvent) { eventHandler?(event) }
}
