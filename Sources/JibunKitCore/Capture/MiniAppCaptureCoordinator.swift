import Foundation

public enum MiniAppCaptureResource: String, Sendable, Hashable, Codable {
    case camera
    case microphone
}

public enum MiniAppCaptureSwitch: Sendable, Equatable {
    case reject
    case stopCurrent
}

/// Chooses which host scene keeps a capture operation eligible to run.
/// Existing capture integrations retain aggregate visibility by default;
/// scene-bound surfaces such as AR explicitly pass their originating scene ID.
public enum MiniAppCaptureSceneScope: Sendable, Equatable {
    case anyVisible
    case scene(UUID)
}

public enum MiniAppCaptureStopReason: Sendable, Equatable {
    case user
    case sceneInactive
    case background
    case notSelected
    case disconnected
    case featureStopped
    case switched(to: MiniAppID)
    case interrupted(String?)
    case failure(String)
}

public enum MiniAppCaptureFailure: Error, Sendable, Equatable {
    case wrongOwner
    case featureConsentDenied(MiniAppCaptureResource)
    case osPermissionDenied(MiniAppCaptureResource)
    case missingAudioHook
    case cameraInUse(by: MiniAppID)
    case switchFailed(owner: MiniAppID, reason: String)
    case stopped
    case staleGeneration
    case unsupported
    case unavailable(String)
    case presentationEnded
    case initialization(String)
    case runtime(String)
    case native(String)
}

public enum MiniAppCaptureState: Sendable, Equatable {
    case idle
    case requesting(Set<MiniAppCaptureResource>)
    case starting
    case running(Set<MiniAppCaptureResource>)
    case stopping(MiniAppCaptureStopReason)
    case suspended(MiniAppCaptureStopReason)
    case failed(MiniAppCaptureFailure)
    case stopped
}

/// SDK notifications are converted to values before leaving the native
/// producer's serial actor. `generation` rejects notifications from an older
/// AVCaptureSession after a new operation starts.
public enum MiniAppCaptureNativeEvent: Sendable, Equatable {
    case interrupted(generation: UUID, reason: String?)
    case interruptionEnded(generation: UUID)
    case runtimeFailed(generation: UUID, reason: String, canRestart: Bool)

    public var generation: UUID {
        switch self {
        case .interrupted(let generation, _), .interruptionEnded(let generation),
             .runtimeFailed(let generation, _, _): generation
        }
    }
}

public struct MiniAppCaptureNativeEvents: Sendable {
    public let generation: UUID
    public let stream: AsyncStream<MiniAppCaptureNativeEvent>

    public init(generation: UUID, stream: AsyncStream<MiniAppCaptureNativeEvent>) {
        self.generation = generation
        self.stream = stream
    }
}

@MainActor
public protocol MiniAppCapturePermissionClient: AnyObject {
    func request(_ resource: MiniAppCaptureResource) async -> Bool
}

/// A Feature-owned native producer. The closure must create and use SDK objects
/// on its own declared isolation context and return only after native start has
/// completed. Its stop closure must return only after the producer has stopped.
public struct MiniAppCaptureOperation: Sendable {
    public typealias Stop = @MainActor @Sendable (MiniAppCaptureStopReason) async -> Void
    public typealias Start = @MainActor @Sendable () async throws -> Stop
    public typealias AcquireAudio = @MainActor @Sendable () async throws -> (@MainActor @Sendable () async -> Void)
    public typealias Events = @MainActor @Sendable () async throws -> MiniAppCaptureNativeEvents
    public typealias Restart = @MainActor @Sendable () async throws -> Void

    public let resources: Set<MiniAppCaptureResource>
    public let startNative: Start
    public let acquireAudio: AcquireAudio?
    public let nativeEvents: Events?
    public let restartNative: Restart?
    public let stopsOnInterruption: Bool

    public init(
        resources: Set<MiniAppCaptureResource>,
        acquireAudio: AcquireAudio? = nil,
        nativeEvents: Events? = nil,
        restartNative: Restart? = nil,
        stopsOnInterruption: Bool = false,
        startNative: @escaping Start
    ) {
        precondition(resources.contains(.camera), "Capture operations require camera ownership.")
        self.resources = resources
        self.acquireAudio = acquireAudio
        self.nativeEvents = nativeEvents
        self.restartNative = restartNative
        self.stopsOnInterruption = stopsOnInterruption
        self.startNative = startNative
    }
}

/// Process-shared camera arbitration. Use one native-default instance for the
/// app process; tests may inject an independent instance. Microphone ownership
/// intentionally isn't represented here.
@MainActor
public final class MiniAppCaptureCoordinator {
    public static let shared = MiniAppCaptureCoordinator()

    private struct Reservation {
        let generation: UUID
        let stopProducer: @MainActor @Sendable (MiniAppCaptureStopReason) async -> Void
    }

    private var reservations: [MiniAppID: Reservation] = [:]
    private var cameraOwner: MiniAppID?
    private var transition: Task<Void, Error>?
    private var transitionID: UUID?

    public init() {}

    public var currentCameraOwner: MiniAppID? { cameraOwner }

    /// Serializes acquisition with an in-flight explicit switch. A rejected
    /// request never invokes another owner's stop callback.
    func reserveCamera(
        owner: MiniAppID,
        generation: UUID,
        switching: MiniAppCaptureSwitch,
        accepting: @escaping @MainActor @Sendable () -> Bool,
        stopProducer: @escaping @MainActor @Sendable (MiniAppCaptureStopReason) async -> Void
    ) async throws {
        let predecessor = transition
        let expectedOwner = cameraOwner
        let expectedGeneration = cameraOwner.flatMap { reservations[$0]?.generation }
        let ticket = UUID()
        let task = Task { @MainActor in
            _ = await predecessor?.result
            guard accepting() else { throw MiniAppCaptureFailure.stopped }
            try await self.performReservation(owner: owner, generation: generation,
                switching: switching, expectedOwner: expectedOwner,
                expectedGeneration: expectedGeneration, accepting: accepting, stopProducer: stopProducer)
        }
        transition = task
        transitionID = ticket
        defer {
            if transitionID == ticket { transition = nil; transitionID = nil }
        }
        try await task.value
    }

    private func performReservation(
        owner: MiniAppID, generation: UUID, switching: MiniAppCaptureSwitch,
        expectedOwner: MiniAppID?, expectedGeneration: UUID?,
        accepting: @MainActor @Sendable () -> Bool,
        stopProducer: @escaping @MainActor @Sendable (MiniAppCaptureStopReason) async -> Void
    ) async throws {
        if let occupied = cameraOwner {
            guard occupied != owner, switching == .stopCurrent,
                  let reservation = reservations[occupied]
            else { throw MiniAppCaptureFailure.cameraInUse(by: occupied) }
            guard expectedOwner == occupied, expectedGeneration == reservation.generation else {
                throw MiniAppCaptureFailure.staleGeneration
            }
            await reservation.stopProducer(.switched(to: owner))
            guard cameraOwner == nil else {
                throw MiniAppCaptureFailure.switchFailed(owner: occupied, reason: "producer did not release camera")
            }
        }
        guard accepting() else { throw MiniAppCaptureFailure.stopped }
        cameraOwner = owner
        reservations[owner] = Reservation(generation: generation, stopProducer: stopProducer)
    }

    func releaseCamera(owner: MiniAppID, generation: UUID) {
        guard cameraOwner == owner, reservations[owner]?.generation == generation else { return }
        reservations[owner] = nil
        cameraOwner = nil
    }
}
