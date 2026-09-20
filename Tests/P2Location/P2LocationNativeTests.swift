#if os(iOS)
import XCTest
import CoreLocation
import SwiftUI
@_spi(Testing) import JibunKitCore
@testable import JibunKit_App

@MainActor
final class P2LocationNativeTests: XCTestCase {
    func testObservationLogPreservesDeliveryStateAcrossProcessesAndIsolatesOwners() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = MiniAppID("observation-a"), b = MiniAppID("observation-b")
        let aFiles = try MiniAppFiles(context: MiniAppContext(id: a), containerURL: root)
        let bFiles = try MiniAppFiles(context: MiniAppContext(id: b), containerURL: root)
        let oldProcess = UUID(), newProcess = UUID()
        let old = P2LocationObservationLog(owner: a, files: aFiles, process: oldProcess, appState: { "background" })
        let received = Date(timeIntervalSince1970: 12345)
        let persisted = old.record("位置callback 1件", at: received)
        XCTAssertEqual(persisted?.appState, "background")
        XCTAssertEqual(persisted?.process, oldProcess)
        let reopened = P2LocationObservationLog(owner: a, files: aFiles, process: newProcess, appState: { "active" })
        reopened.record("runtime接続", at: received.addingTimeInterval(10))
        XCTAssertNil(reopened.error)
        XCTAssertEqual(reopened.entries.map(\.appState), ["background", "active"])
        XCTAssertEqual(reopened.entries.map(\.process), [oldProcess, newProcess])
        XCTAssertEqual(reopened.entries.first?.receivedAt, received)
        let other = P2LocationObservationLog(owner: b, files: bFiles, appState: { "inactive" })
        XCTAssertTrue(other.entries.isEmpty)
        other.record("B受信")
        for index in 0..<70 { reopened.record("位置callback \(index)") }
        let trimmed = P2LocationObservationLog(owner: a, files: aFiles)
        XCTAssertEqual(trimmed.entries.count, 64)
        XCTAssertEqual(trimmed.entries.first?.event, "位置callback 6")
        XCTAssertEqual(P2LocationObservationLog(owner: b, files: bFiles).entries.map(\.event), ["B受信"])
    }

    func testCorruptObservationEvidenceIsPreservedAndFailureVisible() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = MiniAppID("observation-corrupt")
        let files = try MiniAppFiles(context: MiniAppContext(id: id), containerURL: root)
        let original = Data("unreadable evidence".utf8)
        try files.write(original, named: P2LocationObservationLog.filename)
        let log = P2LocationObservationLog(owner: id, files: files)
        XCTAssertNotNil(log.error)
        XCTAssertNil(log.record("新しいcallback"))
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(try files.read(named: P2LocationObservationLog.filename), original)
        XCTAssertNotNil(log.error)
    }

    func testDefinitionConsentSavesBeforeCallbackAndPreservesDenialOnCleanupFailure() throws {
        let suite = "P2Consent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MiniAppConsentStore(defaults: defaults)
        let a = MiniAppID("consent-a"), b = MiniAppID("consent-b")
        store.setConsent(.allowed, for: a, permissionID: "location")
        store.setConsent(.allowed, for: b, permissionID: "location")
        enum CleanupFailure: Error { case unavailable }
        var calls = 0
        let definition = MiniAppDefinition(id: a, title: "A", systemImage: "location",
            permissions: [.init(id: "location", title: "Location", purpose: "Test", deniedBehavior: "Stop")],
            onConsentChange: { permission, decision in
                calls += 1
                XCTAssertEqual(store.consent(for: a, permissionID: permission), decision)
                throw CleanupFailure.unavailable
            }) { _ in EmptyView() }
        XCTAssertThrowsError(try definition.setConsent(.denied, permissionID: "location", in: store))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.consent(for: a, permissionID: "location"), .denied)
        XCTAssertEqual(store.consent(for: b, permissionID: "location"), .allowed)
    }

    func testProbePublishesTwoRealFeatureDefinitionsWithSeparateOwners() {
        let definitions = P2LocationProbe.definitions
        XCTAssertEqual(definitions.map(\.id), [MiniAppID("p2-location-tracker"), MiniAppID("p2-location-regions")])
        XCTAssertEqual(definitions.flatMap(\.permissions).map(\.id), ["location", "location"])
        XCTAssertTrue(definitions.allSatisfy {
            $0.lifetime != nil && $0.externalAccess != nil && $0.onHostLaunch != nil && $0.onUnregister != nil
        })
    }

    func testRealFeatureLifetimesStartAndStopIndependently() async throws {
        let tracker = P2LocationProbe.tracker.definition
        let regions = P2LocationProbe.regions.definition
        try await tracker.lifetime?.start(); try await regions.lifetime?.start()
        let regionRuntime = regions.lifetime?.runtime
        await tracker.lifetime?.stop()
        XCTAssertTrue(regions.lifetime?.runtime === regionRuntime)
        XCTAssertEqual(regions.lifetime?.state, .running)
        await regions.lifetime?.stop()
    }

    func testHostLaunchHookIsSynchronousAndIdempotent() throws {
        let definitions = P2LocationProbe.definitions
        for definition in definitions { try definition.externalAccess?.prepare(true) }
        for definition in definitions { try definition.onHostLaunch?(); try definition.onHostLaunch?() }
    }

    func testCoreLocationAdapterPreservesConfigurationAndFullSDKLocation() {
        let client = MiniAppCoreLocationClient()
        let generation = UUID()
        let configuration = MiniAppLocationUpdateConfiguration(
            desiredAccuracy: 7, distanceFilter: 13, activityType: .automotiveNavigation,
            pausesAutomatically: false, background: false, showsBackgroundIndicator: true)
        client.startUpdates(configuration: configuration, generation: generation)
        XCTAssertEqual(client.activeConfigurations[generation], configuration)
        let date = Date(timeIntervalSince1970: 123)
        let location = CLLocation(coordinate: .init(latitude: 35, longitude: 139), altitude: 44,
                                  horizontalAccuracy: 5, verticalAccuracy: 6,
                                  course: 70, courseAccuracy: 8, speed: 9, speedAccuracy: 10,
                                  timestamp: date)
        let sample = MiniAppCoreLocationClient.sample(location)
        XCTAssertEqual(sample.altitude, 44); XCTAssertEqual(sample.verticalAccuracy, 6)
        XCTAssertEqual(sample.course, 70); XCTAssertEqual(sample.courseAccuracy, 8)
        XCTAssertEqual(sample.speed, 9); XCTAssertEqual(sample.speedAccuracy, 10)
        client.stopUpdates(generation: generation)
        XCTAssertNil(client.activeConfigurations[generation])
    }

    func testPendingRegionCancellationIsSweptAfterLateDidStart() throws {
        let client = MiniAppCoreLocationClient()
        let registration = try MiniAppLocationRegistration(owner: MiniAppID("native-region"), localID: "pending",
            region: .geofence(latitude: 35, longitude: 139, radius: 25, notifyOnEntry: true, notifyOnExit: true))
        client.startMonitoring(registration)
        XCTAssertTrue(client.pendingOrStartedRegionIDs.contains(registration.id))
        client.stopMonitoring(identifier: registration.id)
        client.finishMonitoringStartForTesting(identifier: registration.id)
        XCTAssertFalse(client.pendingOrStartedRegionIDs.contains(registration.id))
    }

    func testRealFeatureManagementDisablePreservesOtherRuntimeAndState() async throws {
        let definitions = P2LocationProbe.definitions
        let suite = "P2LocationNativeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let management = MiniAppManagement(registrations: definitions.map { definition in
            MiniAppManagement.Registration(id: definition.id, lifetime: definition.lifetime,
                  externalAccess: definition.externalAccess,
                  unregister: { try await definition.onUnregister?() })
        }, defaults: defaults, consents: MiniAppConsentStore(defaults: defaults))
        try await definitions[0].lifetime?.start(); try await definitions[1].lifetime?.start()
        let runtimeB = definitions[1].lifetime?.runtime
        P2LocationProbe.regions.state.status = "B noninitial"
        try await management.disable(definitions[0].id)
        XCTAssertTrue(definitions[1].lifetime?.runtime === runtimeB)
        XCTAssertEqual(P2LocationProbe.regions.state.status, "B noninitial")
        await definitions[1].lifetime?.stop()
    }
}
#endif
