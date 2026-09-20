#if os(iOS)
import CoreLocation
import Foundation

/// Direct Core Location adapter. Each continuous update generation gets its own
/// manager, while a distinct manager reconnects the app-wide monitored regions.
@MainActor
public final class MiniAppCoreLocationClient: NSObject, MiniAppLocationNativeClient, @preconcurrency CLLocationManagerDelegate {
    public var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)?
    public var coreLocationHandler: (@MainActor (UUID, [CLLocation]) -> Void)?
    private let regionManager: CLLocationManager
    private var updateManagers: [ObjectIdentifier: (manager: CLLocationManager, generation: UUID,
                                                       configuration: MiniAppLocationUpdateConfiguration)] = [:]
    private var requestedRegions: [String: CLRegion] = [:]
    private var cancelledRegionIDs: Set<String> = []
    private var startedRegionIDs: Set<String> = []

    public override init() {
        regionManager = CLLocationManager()
        super.init()
        regionManager.delegate = self
    }

    public var authorization: MiniAppLocationAuthorization { Self.authorization(regionManager.authorizationStatus) }
    public var monitoredRegionIDs: Set<String> {
        Set(regionManager.monitoredRegions.map(\.identifier)).union(requestedRegions.keys)
    }
    public func isMonitoringAvailable(for kind: MiniAppLocationMonitoringKind) -> Bool {
        switch kind {
        case .geofence: CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        case .beacon: CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self)
        }
    }
    public var maximumRegionMonitoringDistance: Double { regionManager.maximumRegionMonitoringDistance }

    public func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) {
        switch request {
        case .whenInUse: regionManager.requestWhenInUseAuthorization()
        case .always: regionManager.requestAlwaysAuthorization()
        }
    }

    public func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID) {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = configuration.desiredAccuracy
        manager.distanceFilter = configuration.distanceFilter
        manager.activityType = Self.activity(configuration.activityType)
        manager.pausesLocationUpdatesAutomatically = configuration.pausesAutomatically
        manager.allowsBackgroundLocationUpdates = configuration.background
        manager.showsBackgroundLocationIndicator = configuration.showsBackgroundIndicator
        updateManagers[ObjectIdentifier(manager)] = (manager, generation, configuration)
        manager.startUpdatingLocation()
    }

    public func stopUpdates(generation: UUID) {
        guard let entry = updateManagers.first(where: { $0.value.generation == generation }) else { return }
        entry.value.manager.stopUpdatingLocation()
        entry.value.manager.delegate = nil
        updateManagers.removeValue(forKey: entry.key)
    }

    public func startMonitoring(_ registration: MiniAppLocationRegistration) {
        let region: CLRegion
        switch registration.region {
        case .geofence(let latitude, let longitude, let radius, let entry, let exit):
            let circular = CLCircularRegion(center: .init(latitude: latitude, longitude: longitude),
                                            radius: radius,
                                            identifier: registration.id)
            circular.notifyOnEntry = entry; circular.notifyOnExit = exit
            region = circular
        case .beacon(let uuid, let major, let minor, let entry, let exit):
            let beacon: CLBeaconRegion
            if let major, let minor { beacon = CLBeaconRegion(uuid: uuid, major: major, minor: minor, identifier: registration.id) }
            else if let major { beacon = CLBeaconRegion(uuid: uuid, major: major, identifier: registration.id) }
            else { beacon = CLBeaconRegion(uuid: uuid, identifier: registration.id) }
            beacon.notifyOnEntry = entry; beacon.notifyOnExit = exit
            region = beacon
        }
        requestedRegions[registration.id] = region
        cancelledRegionIDs.remove(registration.id)
        regionManager.startMonitoring(for: region)
    }

    public func stopMonitoring(identifier: String) {
        if requestedRegions[identifier] == nil,
           let monitored = regionManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            regionManager.stopMonitoring(for: monitored)
            cancelledRegionIDs.remove(identifier); startedRegionIDs.remove(identifier)
            return
        }
        guard let region = requestedRegions[identifier] else { return }
        regionManager.stopMonitoring(for: region)
        if startedRegionIDs.remove(identifier) != nil {
            requestedRegions.removeValue(forKey: identifier)
            cancelledRegionIDs.remove(identifier)
        } else {
            cancelledRegionIDs.insert(identifier)
        }
    }

    public func requestState(identifier: String) {
        guard let region = regionManager.monitoredRegions.first(where: { $0.identifier == identifier }) else { return }
        regionManager.requestState(for: region)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        eventHandler?(.authorizationChanged(Self.authorization(manager.authorizationStatus)))
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let generation = updateManagers[ObjectIdentifier(manager)]?.generation else { return }
        coreLocationHandler?(generation, locations)
        eventHandler?(.locations(generation: generation, locations.map(Self.sample)))
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard manager === regionManager else { return }; eventHandler?(.entered(identifier: region.identifier))
    }
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard manager === regionManager else { return }; eventHandler?(.exited(identifier: region.identifier))
    }
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard manager === regionManager else { return }
        let value: MiniAppLocationRegionState = state == .inside ? .inside : state == .outside ? .outside : .unknown
        eventHandler?(.state(identifier: region.identifier, value))
    }
    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let id = region?.identifier {
            requestedRegions.removeValue(forKey: id); cancelledRegionIDs.remove(id); startedRegionIDs.remove(id)
        }
        eventHandler?(.monitoringFailed(identifier: region?.identifier, message: error.localizedDescription))
    }
    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        guard manager === regionManager else { return }
        finishMonitoringStart(region)
    }
    private func finishMonitoringStart(_ region: CLRegion) {
        if cancelledRegionIDs.remove(region.identifier) != nil {
            regionManager.stopMonitoring(for: requestedRegions[region.identifier] ?? region)
            requestedRegions.removeValue(forKey: region.identifier)
        } else {
            startedRegionIDs.insert(region.identifier)
        }
    }
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        eventHandler?(.failed(generation: updateManagers[ObjectIdentifier(manager)]?.generation, message: error.localizedDescription))
    }

    private static func authorization(_ status: CLAuthorizationStatus) -> MiniAppLocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .denied
        }
    }
    private static func activity(_ value: MiniAppLocationActivity) -> CLActivityType {
        switch value {
        case .other: .other
        case .automotiveNavigation: .automotiveNavigation
        case .fitness: .fitness
        case .otherNavigation: .otherNavigation
        case .airborne: .airborne
        }
    }

    @_spi(Testing) public var activeConfigurations: [UUID: MiniAppLocationUpdateConfiguration] {
        Dictionary(uniqueKeysWithValues: updateManagers.values.map {
            ($0.generation, MiniAppLocationUpdateConfiguration(
                desiredAccuracy: $0.manager.desiredAccuracy,
                distanceFilter: $0.manager.distanceFilter,
                activityType: Self.activity($0.manager.activityType),
                pausesAutomatically: $0.manager.pausesLocationUpdatesAutomatically,
                background: $0.manager.allowsBackgroundLocationUpdates,
                showsBackgroundIndicator: $0.manager.showsBackgroundLocationIndicator))
        })
    }
    @_spi(Testing) public var pendingOrStartedRegionIDs: Set<String> { Set(requestedRegions.keys) }
    @_spi(Testing) public func finishMonitoringStartForTesting(identifier: String) {
        guard let region = requestedRegions[identifier] else { return }
        finishMonitoringStart(region)
    }
    @_spi(Testing) public static func sample(_ location: CLLocation) -> MiniAppLocationSample {
        .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
              horizontalAccuracy: location.horizontalAccuracy, timestamp: location.timestamp,
              altitude: location.altitude, verticalAccuracy: location.verticalAccuracy,
              course: location.course, courseAccuracy: location.courseAccuracy,
              speed: location.speed, speedAccuracy: location.speedAccuracy,
              isSimulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware,
              isProducedByAccessory: location.sourceInformation?.isProducedByAccessory)
    }
    private static func activity(_ value: CLActivityType) -> MiniAppLocationActivity {
        switch value {
        case .automotiveNavigation: .automotiveNavigation
        case .fitness: .fitness
        case .otherNavigation: .otherNavigation
        case .airborne: .airborne
        default: .other
        }
    }
}
#else
import Foundation

@MainActor
public final class MiniAppCoreLocationClient: MiniAppLocationNativeClient {
    public init() {}
    public var authorization: MiniAppLocationAuthorization { .denied }
    public var monitoredRegionIDs: Set<String> { [] }
    public func isMonitoringAvailable(for kind: MiniAppLocationMonitoringKind) -> Bool { false }
    public var maximumRegionMonitoringDistance: Double { 0 }
    public var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)?
    public func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) {}
    public func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID) {}
    public func stopUpdates(generation: UUID) {}
    public func startMonitoring(_ registration: MiniAppLocationRegistration) {}
    public func stopMonitoring(identifier: String) {}
    public func requestState(identifier: String) {}
}
#endif
