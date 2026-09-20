#if os(iOS)
import CoreFoundation
import CoreLocation
import JibunKitCore
import SwiftUI
import UIKit

@MainActor
enum P2LocationProbe {
    static let coordinator = MiniAppLocationCoordinator.shared
    static let tracker = P2LocationFeature(id: MiniAppID("p2-location-tracker"), coordinator: coordinator, kind: .tracker)
    static let regions = P2LocationFeature(id: MiniAppID("p2-location-regions"), coordinator: coordinator, kind: .regions)
    static var definitions: [MiniAppDefinition] { [tracker.definition, regions.definition] }
}

@MainActor
final class P2LocationFeature {
    enum Kind { case tracker, regions }
    private static let diagnosticGeofenceID = "diagnostic-geofence"
    let id: MiniAppID
    let kind: Kind
    let coordinator: MiniAppLocationCoordinator
    let state = P2LocationState()
    let observations: P2LocationObservationLog
    private var consentStore: MiniAppConsentStore? = MiniAppConsentStore(defaults: .standard)
    private var updateGeneration: UUID?
    lazy var service = MiniAppLocationService(owner: id, coordinator: coordinator) { [weak self] in
        guard let self else { return false }
        return self.consentStore?.consent(for: self.id, permissionID: "location") == .allowed
    }
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try self.service.connect(to: runtime)
        self.observations.record("runtime接続")
        self.state.generation += 1
        self.state.status = "Feature接続済み・OS許可 \(self.coordinator.authorization.rawValue)"
    }

    init(id: MiniAppID, coordinator: MiniAppLocationCoordinator, kind: Kind) {
        self.id = id; self.coordinator = coordinator; self.kind = kind
        observations = P2LocationObservationLog(owner: id)
    }

    var definition: MiniAppDefinition {
        service.receive = { [weak self] in self?.receive($0) }
        return MiniAppDefinition(
            id: id, title: kind == .tracker ? "位置更新Probe" : "Region/iBeacon Probe",
            systemImage: kind == .tracker ? "location" : "mappin.and.ellipse",
            lifetime: lifetime,
            externalAccess: service.externalAccess,
            permissions: [.init(id: "location", title: "位置情報",
                                purpose: kind == .tracker ? "選択した精度で前景・背景の位置更新を受け取ります" : "geofenceとiBeaconの出入りを監視します",
                                deniedBehavior: "OS許可を要求せず、位置処理を開始しません")],
            onConsentChange: { [weak self] permissionID, decision in
                guard let self, permissionID == "location" else { return }
                // The value is explicit; this also works with an injected host store.
                if decision != .allowed { try self.coordinator.revoke(owner: self.id) }
                self.observations.record("Feature同意変更: \(decision)")
                self.refreshRegistrations()
            },
            onUnregister: { [weak self] in try self?.service.unregisterAllOwned() },
            onHostLaunch: { [weak self] in
                guard let self else { return }
                self.observations.record("host起動hook")
                self.report { try self.service.reconnectPersistedMonitoring() }
            }
        ) { [self] _ in P2LocationView(feature: self) }
    }

    func attachConsent(_ store: MiniAppConsentStore?) {
        consentStore = store
        report { try service.featureConsentDidChange() }
        refreshRegistrations()
    }
    func request(_ request: MiniAppLocationAuthorizationRequest) { report { try service.requestAuthorization(request) } }
    func start(background: Bool) {
        report {
            updateGeneration = try service.startUpdates(.init(
                desiredAccuracy: background ? 10 : 100,
                distanceFilter: background ? 10 : 25,
                activityType: background ? .fitness : .other,
                pausesAutomatically: true,
                background: background,
                showsBackgroundIndicator: background
            ))
            state.status = background ? "背景位置更新を開始" : "前景位置更新を開始"
            observations.record(state.status)
        }
    }
    func stopUpdates() {
        report {
            guard let updateGeneration else { return }
            try service.stopUpdates(generation: updateGeneration)
            self.updateGeneration = nil; state.status = "位置更新を停止"
            observations.record(state.status)
        }
    }
    func registerGeofence() {
        report {
            let registration = try service.register(localID: "geofence-\(state.registrations.count + 1)", region: .geofence(
                latitude: state.latitude, longitude: state.longitude, radius: state.radius,
                notifyOnEntry: true, notifyOnExit: true))
            state.status = "geofence登録 \(registration.localID)"; refreshRegistrations()
            observations.record(state.status)
        }
    }
    func registerDiagnosticGeofence() {
        report {
            if let existing = service.registrations.first(where: {
                $0.localID == Self.diagnosticGeofenceID
            }) {
                try service.unregister(localID: existing.localID, generation: existing.generation)
            }
            let registration = try service.register(
                localID: Self.diagnosticGeofenceID,
                region: .geofence(latitude: 37.3349, longitude: -122.0090, radius: 300,
                                   notifyOnEntry: true, notifyOnExit: true))
            state.status = "geofence登録 \(registration.localID)"; refreshRegistrations()
            observations.record(state.status)
        }
    }
    func unregisterDiagnosticGeofence() {
        guard let registration = service.registrations.first(where: {
            $0.localID == Self.diagnosticGeofenceID
        }) else { return }
        unregister(registration)
    }
    func requestDiagnosticGeofenceState() {
        report { try service.requestState(localID: Self.diagnosticGeofenceID) }
    }
    func registerBeacon() {
        report {
            let registration = try service.register(localID: "diagnostic-beacon", region: .beacon(
                uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!, major: 1, minor: 1,
                notifyOnEntry: true, notifyOnExit: true))
            state.status = "iBeacon監視登録 \(registration.localID)"; refreshRegistrations()
            observations.record(state.status)
        }
    }
    func unregister(_ registration: MiniAppLocationRegistration) {
        report {
            try service.unregister(localID: registration.localID, generation: registration.generation)
            state.status = "担当Regionを解除"; refreshRegistrations()
            observations.record("Region解除: \(registration.localID)")
        }
    }
    private func receive(_ event: MiniAppLocationEvent) {
        state.eventCount += 1
        // Record delivery context before view/lifetime status can replace it.
        switch event {
        case .locations(_, let samples):
            let previous = state.lastSample
            let persisted = observations.record("位置callback \(samples.count)件")
            if id == MiniAppID("p2-location-tracker"), persisted?.appState == "background",
               let previous, let current = samples.last,
               CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude)) >= 50 {
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName(rawValue:
                        "com.jibunkit.tests.p2-location-tracker.background-callback" as CFString),
                    nil, nil, true
                )
            }
        case .authorizationChanged(let value): observations.record("OS許可callback: \(value.rawValue)")
        case .entered(let value):
            let persisted = observations.record("進入callback: \(value.localID)")
            postDiagnosticGeofenceSignal("enter", registration: value, persisted: persisted)
        case .exited(let value):
            let persisted = observations.record("退出callback: \(value.localID)")
            postDiagnosticGeofenceSignal("exit", registration: value, persisted: persisted)
        case .state(let value, let regionState): observations.record("状態callback: \(value.localID) \(regionState)")
        case .monitoringFailed: observations.record("監視失敗callback")
        case .failed: observations.record("位置失敗callback")
        }
        switch event {
        case .locations(_, let samples):
            state.status = "位置更新 \(samples.count)件"; state.lastSample = samples.last
            if let sample = samples.last { state.latitude = sample.latitude; state.longitude = sample.longitude }
        case .authorizationChanged(let value): state.status = "OS許可変更: \(value.rawValue)"
        case .entered(let value): state.status = "進入: \(value.localID)"; refreshRegistrations()
        case .exited(let value): state.status = "退出: \(value.localID)"; refreshRegistrations()
        case .state(let value, let regionState): state.status = "状態 \(value.localID): \(regionState)"
        case .monitoringFailed(_, let message), .failed(_, let message): state.status = "失敗: \(message)"
        }
    }
    private func report(_ operation: () throws -> Void) {
        do { try operation() } catch { state.status = "拒否/失敗: \(error)" }
    }
    private func postDiagnosticGeofenceSignal(
        _ event: String,
        registration: MiniAppLocationRegistration,
        persisted: P2LocationObservationLog.Entry?
    ) {
        guard id == MiniAppID("p2-location-regions"),
              registration.localID == Self.diagnosticGeofenceID,
              persisted != nil else { return }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue:
                "com.jibunkit.tests.p2-location-regions.geofence-\(event)" as CFString),
            nil, nil, true
        )
    }
    private func refreshRegistrations() { state.registrations = service.registrations }
}

@MainActor
final class P2LocationState: ObservableObject {
    @Published var status = "未接続"
    @Published var eventCount = 0
    @Published var generation = 0
    @Published var lastSample: MiniAppLocationSample?
    @Published var latitude = 0.0
    @Published var longitude = 0.0
    @Published var radius = 150.0
    @Published var registrations: [MiniAppLocationRegistration] = []
}

private struct P2LocationView: View {
    @Environment(\.miniAppConsentStore) private var consentStore
    @ObservedObject var state: P2LocationState
    let feature: P2LocationFeature
    init(feature: P2LocationFeature) { self.feature = feature; state = feature.state }
    private var locationConsent: MiniAppConsent {
        consentStore?.consent(for: feature.id, permissionID: "location") ?? .notDetermined
    }
    var body: some View {
        Form {
            Text(state.status).accessibilityIdentifier("p2.location.\(feature.id.rawValue).status")
            Text("event \(state.eventCount) / runtime世代 \(state.generation)")
                .accessibilityIdentifier("p2.location.\(feature.id.rawValue).events")
            Button("When In Use許可を要求") { feature.request(.whenInUse) }
            Button("Always許可を要求") { feature.request(.always) }
            if feature.kind == .tracker {
                Button("前景位置更新") { feature.start(background: false) }
                    .accessibilityIdentifier("p2.location.tracker.foreground")
                Button("背景位置更新") { feature.start(background: true) }
                    .accessibilityIdentifier("p2.location.tracker.background")
                Button("位置更新停止") { feature.stopUpdates() }
                    .accessibilityIdentifier("p2.location.tracker.stop")
            } else {
                Button("現在地を取得") { feature.start(background: false) }
                    .accessibilityIdentifier("p2.location.regions.current-location")
                Button("位置更新停止") { feature.stopUpdates() }
                    .accessibilityIdentifier("p2.location.regions.stop")
                TextField("緯度", value: $state.latitude, format: .number)
                TextField("経度", value: $state.longitude, format: .number)
                TextField("半径m", value: $state.radius, format: .number)
                Button("入力地点のgeofence登録") { feature.registerGeofence() }
                Button("診断geofence登録") { feature.registerDiagnosticGeofence() }
                    .accessibilityIdentifier("p2.location.regions.diagnostic-geofence")
                Button("診断geofence状態確認") { feature.requestDiagnosticGeofenceState() }
                    .accessibilityIdentifier("p2.location.regions.diagnostic-geofence-state")
                Button("診断geofence解除") { feature.unregisterDiagnosticGeofence() }
                    .accessibilityIdentifier("p2.location.regions.diagnostic-geofence-remove")
                Button("診断iBeacon登録") { feature.registerBeacon() }
                ForEach(state.registrations) { registration in
                    HStack {
                        Text(registration.localID)
                        Spacer()
                        Button("解除") { feature.unregister(registration) }
                    }
                }
            }
            if let sample = state.lastSample {
                Text("\(sample.latitude), \(sample.longitude) ±\(sample.horizontalAccuracy)m")
                    .accessibilityIdentifier("p2.location.\(feature.id.rawValue).sample")
            }
            P2LocationObservationView(owner: feature.id, log: feature.observations)
        }
        .onAppear { feature.attachConsent(consentStore) }
        .onChange(of: locationConsent) { _, _ in feature.attachConsent(consentStore) }
    }
}
#endif
