import Foundation

@MainActor
public final class MiniAppCaptureOwner {
    public nonisolated let id: MiniAppID
    public private(set) var state: MiniAppCaptureState = .idle {
        didSet { stateChanged?(state) }
    }
    /// Capture this value before scheduling external resource cleanup.
    public var operationGeneration: UUID? { operation?.generation }

    public var stateChanged: (@MainActor @Sendable (MiniAppCaptureState) -> Void)?
    private struct Started: Sendable {
        let stop: MiniAppCaptureOperation.Stop
        let releaseAudio: (@MainActor @Sendable () async -> Void)?
    }
    @MainActor private final class Operation {
        let generation = UUID()
        let sceneScope: MiniAppCaptureSceneScope
        var closed = false
        var startup: Task<Started, Error>?
        var nativeGeneration: UUID?
        var events: Task<Void, Never>?

        init(sceneScope: MiniAppCaptureSceneScope) {
            self.sceneScope = sceneScope
        }
    }
    private let coordinator: MiniAppCaptureCoordinator
    private let permissions: any MiniAppCapturePermissionClient
    private let consent: @MainActor @Sendable (MiniAppCaptureResource) -> Bool
    private weak var runtime: MiniAppRuntime?
    private var runtimeGeneration: UUID?
    private var operation: Operation?
    private var scenes: [UUID: MiniAppSceneActivity] = [:]
    private var stopTask: Task<Void, Never>?
    private var endingRuntime = false
    private var explicitEnd = false

    public init(id: MiniAppID, coordinator: MiniAppCaptureCoordinator = .shared,
                permissions: any MiniAppCapturePermissionClient,
                consent: @escaping @MainActor @Sendable (MiniAppCaptureResource) -> Bool = { _ in false }) {
        precondition(id.isValid)
        self.id = id
        self.coordinator = coordinator
        self.permissions = permissions
        self.consent = consent
    }

    public func connect(to runtime: MiniAppRuntime) throws {
        guard runtimeGeneration == nil else { throw MiniAppCaptureFailure.native("already connected") }
        guard !runtime.isClosed else { throw MiniAppCaptureFailure.stopped }
        let generation = UUID()
        self.runtime = runtime
        runtimeGeneration = generation
        endingRuntime = false
        explicitEnd = false
        state = .idle
        try runtime.onShutdownAsync { [weak self] in
            guard let self, self.runtimeGeneration == generation else { return }
            await self.stop(reason: .featureStopped, final: true)
        }
    }

    public func receive(_ activity: MiniAppSceneActivity) {
        guard activity.featureID == id else { return }
        if activity.isConnected { scenes[activity.sceneID] = activity }
        else { scenes[activity.sceneID] = nil }
        guard let pending = operation,
              shouldStop(pending, after: activity) else { return }
        let reason: MiniAppCaptureStopReason
        if activity.phase == nil { reason = .disconnected }
        else if activity.phase == .background { reason = .background }
        else if !activity.isSelected { reason = .notSelected }
        else { reason = .sceneInactive }
        Task { @MainActor [weak self] in
            guard let self, self.operation === pending,
                  self.shouldStop(pending, after: activity) else { return }
            await self.suspend(reason)
        }
    }

    public func start(_ request: MiniAppCaptureOperation,
                      switching: MiniAppCaptureSwitch = .reject,
                      sceneScope: MiniAppCaptureSceneScope = .anyVisible) async throws {
        while let stopTask { await stopTask.value }
        guard let runtimeGeneration, runtime?.isClosed == false else { throw MiniAppCaptureFailure.stopped }
        guard operation == nil else { throw MiniAppCaptureFailure.unavailable("capture already active") }
        guard isVisible(in: sceneScope) else {
            throw MiniAppCaptureFailure.unavailable("capture scene is not active and selected")
        }
        let pending = Operation(sceneScope: sceneScope)
        operation = pending
        explicitEnd = false
        state = .requesting(request.resources)
        do {
            for resource in [MiniAppCaptureResource.camera, .microphone] where request.resources.contains(resource) {
                guard consent(resource) else { throw MiniAppCaptureFailure.featureConsentDenied(resource) }
                let allowed = await permissions.request(resource)
                try check(pending, runtimeGeneration)
                guard allowed else { throw MiniAppCaptureFailure.osPermissionDenied(resource) }
            }
            // Feature consent may be revoked while an OS permission sheet is
            // pending. Recheck every requested resource before reserving camera.
            for resource in request.resources {
                guard consent(resource) else { throw MiniAppCaptureFailure.featureConsentDenied(resource) }
            }
            guard request.resources.contains(.microphone) == (request.acquireAudio != nil) else {
                throw MiniAppCaptureFailure.missingAudioHook
            }
            try await coordinator.reserveCamera(owner: id, generation: pending.generation,
                switching: switching, accepting: { [weak self] in
                    !pending.closed && self?.runtime?.isClosed == false
                }, stopProducer: { [weak self] reason in
                    await self?.stop(reason: reason, final: false)
                })
            try check(pending, runtimeGeneration)
            state = .starting
            // Stop joins this phase before handing camera/audio to another owner.
            let startup = Task { @MainActor in
                let audio = try await request.acquireAudio?()
                do {
                    guard !pending.closed else { throw MiniAppCaptureFailure.stopped }
                    let stop = try await request.startNative()
                    return Started(stop: stop, releaseAudio: audio)
                } catch {
                    await audio?()
                    throw error
                }
            }
            pending.startup = startup
            _ = try await startup.value
            try check(pending, runtimeGeneration)
            state = .running(request.resources)
            if let nativeEvents = request.nativeEvents {
                let events = try await nativeEvents()
                try check(pending, runtimeGeneration)
                pending.nativeGeneration = events.generation
                pending.events = Task { @MainActor [weak self, weak pending] in
                    for await event in events.stream {
                        guard let self, let pending, self.operation === pending,
                              !pending.closed else { return }
                        guard pending.nativeGeneration == event.generation else { continue }
                        await self.handle(event, operation: pending, request: request)
                    }
                }
            }
        } catch {
            let failure = error as? MiniAppCaptureFailure ?? .native(String(describing: error))
            if operation === pending {
                await stop(reason: .failure(String(describing: error)), final: false)
                if self.runtimeGeneration == runtimeGeneration,
                   case .suspended(.failure(_)) = state { state = .failed(failure) }
            } else {
                coordinator.releaseCamera(owner: id, generation: pending.generation)
            }
            throw failure
        }
    }

    public func stop() async {
        explicitEnd = true
        await stop(reason: .user, final: false)
    }

    public func suspend(_ reason: MiniAppCaptureStopReason) async {
        await stop(reason: reason, final: false)
    }

    /// Reject an external resource callback belonging to an earlier operation.
    public func suspend(_ reason: MiniAppCaptureStopReason, ifGeneration generation: UUID) async {
        guard operation?.generation == generation else { return }
        await stop(reason: reason, final: false)
    }

    public func handleInterruptionEnded(restart: @MainActor @Sendable () async throws -> Void) async throws {
        guard let pending = operation, !explicitEnd, isVisible(in: pending.sceneScope), runtime?.isClosed == false,
              case .suspended(.interrupted(_)) = state else { return }
        try await restart()
    }

    private func handle(_ event: MiniAppCaptureNativeEvent, operation pending: Operation,
                        request: MiniAppCaptureOperation) async {
        switch event {
        case .interrupted(_, let reason):
            guard self.operation === pending, !pending.closed else { return }
            state = .suspended(.interrupted(reason))
            if request.stopsOnInterruption {
                Task { @MainActor [weak self] in
                    await self?.stop(reason: .interrupted(reason), final: false)
                }
            }
        case .interruptionEnded:
            guard self.operation === pending, !pending.closed, !explicitEnd,
                  isVisible(in: pending.sceneScope),
                  runtime?.isClosed == false,
                  case .suspended(.interrupted(_)) = state,
                  let restart = request.restartNative else { return }
            do {
                try await restart()
                guard self.operation === pending, !pending.closed else { return }
                state = .running(request.resources)
            } catch {
                let reason = String(describing: error)
                Task { @MainActor [weak self] in
                    await self?.failRuntime(operation: pending, reason: reason)
                }
            }
        case .runtimeFailed(_, let reason, let canRestart):
            state = .suspended(.failure(reason))
            if canRestart, !explicitEnd, isVisible(in: pending.sceneScope),
               let restart = request.restartNative {
                do {
                    try await restart()
                    guard self.operation === pending, !pending.closed else { return }
                    state = .running(request.resources)
                    return
                } catch {
                    let restartReason = String(describing: error)
                    Task { @MainActor [weak self] in
                        await self?.failRuntime(operation: pending, reason: restartReason)
                    }
                    return
                }
            }
            Task { @MainActor [weak self] in
                await self?.failRuntime(operation: pending, reason: reason)
            }
        }
    }

    private func failRuntime(operation pending: Operation, reason: String) async {
        guard operation === pending, !pending.closed else { return }
        await stop(reason: .failure(reason), final: false)
        if case .suspended(.failure(_)) = state { state = .failed(.runtime(reason)) }
    }

    private var isVisible: Bool { scenes.values.contains { $0.phase == .active && $0.isSelected } }

    private func isVisible(in scope: MiniAppCaptureSceneScope) -> Bool {
        switch scope {
        case .anyVisible: isVisible
        case .scene(let sceneID):
            scenes[sceneID]?.phase == .active && scenes[sceneID]?.isSelected == true
        }
    }

    private func shouldStop(_ pending: Operation, after activity: MiniAppSceneActivity) -> Bool {
        switch pending.sceneScope {
        case .anyVisible:
            return !isVisible
        case .scene(let sceneID):
            return activity.sceneID == sceneID && !isVisible(in: pending.sceneScope)
        }
    }

    private func check(_ pending: Operation, _ generation: UUID) throws {
        guard runtimeGeneration == generation else { throw MiniAppCaptureFailure.staleGeneration }
        guard operation === pending, !pending.closed, runtime?.isClosed == false else {
            throw MiniAppCaptureFailure.stopped
        }
        guard isVisible(in: pending.sceneScope) else {
            throw MiniAppCaptureFailure.unavailable("capture scene is not active and selected")
        }
        try Task.checkCancellation()
    }

    private func stop(reason: MiniAppCaptureStopReason, final: Bool) async {
        if final { endingRuntime = true }
        if let stopTask { await stopTask.value; finishRuntimeIfNeeded(); return }
        guard let pending = operation else { finishRuntimeIfNeeded(); return }
        pending.closed = true
        let events = pending.events
        events?.cancel()
        pending.events = nil
        state = .stopping(reason)
        let task = Task { @MainActor in
            // A non-cooperative restart may ignore cancellation. Join it before
            // stopping native resources or releasing camera to another owner.
            await events?.value
            if let startup = pending.startup, case .success(let started) = await startup.result {
                await started.stop(reason)
                await started.releaseAudio?()
            }
            self.coordinator.releaseCamera(owner: self.id, generation: pending.generation)
            if self.operation === pending { self.operation = nil }
            self.state = reason == .user ? .idle : .suspended(reason)
            self.stopTask = nil
            self.finishRuntimeIfNeeded()
        }
        stopTask = task
        await task.value
    }

    private func finishRuntimeIfNeeded() {
        guard endingRuntime else { return }
        runtime = nil
        runtimeGeneration = nil
        // Preserve scene observations across restart in an unchanged host scene.
        state = .stopped
        endingRuntime = false
    }
}
