import Foundation

public enum MiniAppLocationAuthorization: String, Codable, Sendable, Equatable {
    case notDetermined, restricted, denied, whenInUse, always
}

public enum MiniAppLocationAuthorizationRequest: String, Codable, Sendable {
    case whenInUse, always
}

public struct MiniAppLocationUpdateConfiguration: Sendable, Equatable {
    public var desiredAccuracy: Double
    public var distanceFilter: Double
    public var activityType: MiniAppLocationActivity
    public var pausesAutomatically: Bool
    public var background: Bool
    public var showsBackgroundIndicator: Bool

    public init(desiredAccuracy: Double, distanceFilter: Double = 0,
                activityType: MiniAppLocationActivity = .other,
                pausesAutomatically: Bool = true, background: Bool = false,
                showsBackgroundIndicator: Bool = false) {
        self.desiredAccuracy = desiredAccuracy
        self.distanceFilter = distanceFilter
        self.activityType = activityType
        self.pausesAutomatically = pausesAutomatically
        self.background = background
        self.showsBackgroundIndicator = showsBackgroundIndicator
    }
}

public enum MiniAppLocationActivity: String, Codable, Sendable, Equatable {
    case other, automotiveNavigation, fitness, otherNavigation, airborne
}

public struct MiniAppLocationSample: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let timestamp: Date
    public let altitude: Double
    public let verticalAccuracy: Double
    public let course: Double
    public let courseAccuracy: Double
    public let speed: Double
    public let speedAccuracy: Double
    public let isSimulatedBySoftware: Bool?
    public let isProducedByAccessory: Bool?

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date,
                altitude: Double = 0, verticalAccuracy: Double = -1,
                course: Double = -1, courseAccuracy: Double = -1,
                speed: Double = -1, speedAccuracy: Double = -1,
                isSimulatedBySoftware: Bool? = nil, isProducedByAccessory: Bool? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
        self.altitude = altitude; self.verticalAccuracy = verticalAccuracy
        self.course = course; self.courseAccuracy = courseAccuracy
        self.speed = speed; self.speedAccuracy = speedAccuracy
        self.isSimulatedBySoftware = isSimulatedBySoftware
        self.isProducedByAccessory = isProducedByAccessory
    }
}

public enum MiniAppLocationRegion: Codable, Sendable, Equatable {
    case geofence(latitude: Double, longitude: Double, radius: Double, notifyOnEntry: Bool, notifyOnExit: Bool)
    case beacon(uuid: UUID, major: UInt16?, minor: UInt16?, notifyOnEntry: Bool, notifyOnExit: Bool)
}

public struct MiniAppLocationRegistration: Codable, Sendable, Equatable, Identifiable {
    public let owner: MiniAppID
    public let localID: String
    public let generation: UUID
    public let region: MiniAppLocationRegion

    public init(owner: MiniAppID, localID: String, generation: UUID = UUID(), region: MiniAppLocationRegion) throws {
        guard owner.isValid, !localID.isEmpty else { throw MiniAppLocationFailure.invalidRegistration }
        if case .geofence(let latitude, let longitude, let radius, _, _) = region {
            guard latitude.isFinite, longitude.isFinite, radius.isFinite,
                  (-90...90).contains(latitude), (-180...180).contains(longitude), radius > 0 else {
                throw MiniAppLocationFailure.invalidRegistration
            }
        }
        if case .beacon(_, let major, let minor, _, _) = region, major == nil && minor != nil {
            throw MiniAppLocationFailure.invalidRegistration
        }
        self.owner = owner
        self.localID = localID
        self.generation = generation
        self.region = region
    }

    public var id: String {
        let encoded = Data(localID.utf8).base64EncodedString()
        return "jibunkit.location.\(owner.storageNamespace).\(encoded).\(generation.uuidString.lowercased())"
    }

    private enum CodingKeys: String, CodingKey { case owner, localID, generation, region }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(owner: values.decode(MiniAppID.self, forKey: .owner),
                      localID: values.decode(String.self, forKey: .localID),
                      generation: values.decode(UUID.self, forKey: .generation),
                      region: values.decode(MiniAppLocationRegion.self, forKey: .region))
    }
}

public enum MiniAppLocationRegionState: Sendable, Equatable { case inside, outside, unknown }
public enum MiniAppLocationMonitoringKind: Sendable, Hashable { case geofence, beacon }

public enum MiniAppLocationEvent: Sendable, Equatable {
    case locations(generation: UUID, samples: [MiniAppLocationSample])
    case authorizationChanged(MiniAppLocationAuthorization)
    case entered(MiniAppLocationRegistration)
    case exited(MiniAppLocationRegistration)
    case state(MiniAppLocationRegistration, MiniAppLocationRegionState)
    case monitoringFailed(MiniAppLocationRegistration?, String)
    case failed(generation: UUID?, String)
}

public enum MiniAppLocationFailure: Error, Sendable, Equatable {
    case featureConsentDenied
    case osAuthorizationDenied(MiniAppLocationAuthorization)
    case invalidRegistration
    case duplicateLocalID
    case monitoringUnavailable
    case radiusExceedsMaximum(requested: Double, maximum: Double)
    case capacityExceeded(limit: Int, occupied: Int)
    case wrongOwner
    case staleGeneration
    case stopped
    case persistenceUnavailable(String)
}

extension MiniAppID: Codable {
    public init(from decoder: Decoder) throws { self.init(try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
