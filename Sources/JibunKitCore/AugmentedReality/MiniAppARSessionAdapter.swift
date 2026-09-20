#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import Foundation

public struct MiniAppARSessionEventForwarder: Sendable {
    public let generation: UUID
    private let send: @Sendable (MiniAppCaptureNativeEvent) -> Void

    fileprivate init(generation: UUID, send: @escaping @Sendable (MiniAppCaptureNativeEvent) -> Void) {
        self.generation = generation
        self.send = send
    }

    public func interruptionBegan(reason: String? = nil) {
        send(.interrupted(generation: generation, reason: reason))
    }

    public func interruptionEnded() {
        send(.interruptionEnded(generation: generation))
    }

    public func runtimeFailed(reason: String, canRestart: Bool) {
        send(.runtimeFailed(generation: generation, reason: reason, canRestart: canRestart))
    }
}

/// Converts only AR session lifetime events into the existing capture contract.
/// It never assigns `ARSession.delegate`: a Feature keeps its full frame/anchor
/// delegate and forwards the three observer callbacks it wants coordinated.
@MainActor
public final class MiniAppARSessionEventBridge: NSObject, @preconcurrency ARSessionDelegate {
    public nonisolated let canRestartRuntimeFailure: @Sendable (String) -> Bool
    private nonisolated let generationBox = MiniAppARGenerationBox()
    private var active: MiniAppCaptureNativeEvents?
    private var continuation: AsyncStream<MiniAppCaptureNativeEvent>.Continuation?

    public init(canRestartRuntimeFailure: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.canRestartRuntimeFailure = canRestartRuntimeFailure
        super.init()
    }

    func begin() throws -> (MiniAppCaptureNativeEvents, MiniAppARSessionEventForwarder) {
        guard active == nil else { throw MiniAppCaptureFailure.unavailable("AR event bridge already active") }
        let generation = UUID()
        let pair = AsyncStream<MiniAppCaptureNativeEvent>.makeStream()
        let events = MiniAppCaptureNativeEvents(generation: generation, stream: pair.stream)
        active = events
        continuation = pair.continuation
        generationBox.set(generation)
        let forwarder = MiniAppARSessionEventForwarder(generation: generation) { [weak self] event in
            Task { @MainActor in self?.emit(event, expected: generation) }
        }
        return (events, forwarder)
    }

    func end(generation: UUID) {
        guard active?.generation == generation else { return }
        continuation?.finish()
        continuation = nil
        active = nil
        generationBox.clear(generation)
    }

    /// Call from a Feature-owned ARSessionDelegate when it keeps the delegate.
    public nonisolated func interruptionBegan(reason: String? = nil) {
        guard let generation = generationBox.current() else { return }
        let event = MiniAppCaptureNativeEvent.interrupted(generation: generation, reason: reason)
        Task { @MainActor [weak self] in self?.emit(event, expected: generation) }
    }

    /// Call from a Feature-owned ARSessionDelegate when it keeps the delegate.
    public nonisolated func interruptionEnded() {
        guard let generation = generationBox.current() else { return }
        let event = MiniAppCaptureNativeEvent.interruptionEnded(generation: generation)
        Task { @MainActor [weak self] in self?.emit(event, expected: generation) }
    }

    /// Call from a Feature-owned delegate to preserve its Error-specific policy.
    public nonisolated func runtimeFailed(reason: String, canRestart: Bool) {
        guard let generation = generationBox.current() else { return }
        let event = MiniAppCaptureNativeEvent.runtimeFailed(
            generation: generation, reason: reason, canRestart: canRestart
        )
        Task { @MainActor [weak self] in self?.emit(event, expected: generation) }
    }

    public nonisolated func sessionWasInterrupted(_ session: ARSession) {
        interruptionBegan()
    }

    public nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        interruptionEnded()
    }

    public nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        let reason = String(describing: error)
        runtimeFailed(reason: reason, canRestart: canRestartRuntimeFailure(reason))
    }

    private func emit(_ event: MiniAppCaptureNativeEvent, expected generation: UUID) {
        guard active?.generation == generation, event.generation == generation else { return }
        continuation?.yield(event)
    }
}

private final class MiniAppARGenerationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UUID?
    func set(_ value: UUID) { lock.withLock { generation = value } }
    func clear(_ value: UUID) { lock.withLock { if generation == value { generation = nil } } }
    func current() -> UUID? { lock.withLock { generation } }
}

/// Adapts one Feature-owned ARSession to camera ownership without wrapping or
/// replacing ARConfiguration, frames, anchors, or the Feature's delegate.
@MainActor
public final class MiniAppARSessionAdapter {
    public let session: ARSession
    public let configuration: ARConfiguration
    public let eventBridge: MiniAppARSessionEventBridge
    private let runOptions: ARSession.RunOptions
    private let restartOptions: ARSession.RunOptions
    private let isSupported: @MainActor @Sendable () -> Bool
    private let installForwarder: @MainActor @Sendable (MiniAppARSessionEventForwarder) -> Void
    private let removeForwarder: @MainActor @Sendable (UUID) -> Void
    private let runSession: @MainActor @Sendable (ARSession, ARConfiguration, ARSession.RunOptions) -> Void
    private let pauseSession: @MainActor @Sendable (ARSession) -> Void

    public init(
        session: ARSession,
        configuration: ARConfiguration,
        runOptions: ARSession.RunOptions = [],
        restartOptions: ARSession.RunOptions = [],
        eventBridge: MiniAppARSessionEventBridge,
        isSupported: @escaping @MainActor @Sendable () -> Bool,
        installForwarder: @escaping @MainActor @Sendable (MiniAppARSessionEventForwarder) -> Void = { _ in },
        removeForwarder: @escaping @MainActor @Sendable (UUID) -> Void = { _ in }
    ) {
        self.session = session
        self.configuration = configuration
        self.runOptions = runOptions
        self.restartOptions = restartOptions
        self.eventBridge = eventBridge
        self.isSupported = isSupported
        self.installForwarder = installForwarder
        self.removeForwarder = removeForwarder
        runSession = { $0.run($1, options: $2) }
        pauseSession = { $0.pause() }
    }

    init(
        session: ARSession,
        configuration: ARConfiguration,
        runOptions: ARSession.RunOptions = [],
        restartOptions: ARSession.RunOptions = [],
        eventBridge: MiniAppARSessionEventBridge,
        isSupported: @escaping @MainActor @Sendable () -> Bool,
        installForwarder: @escaping @MainActor @Sendable (MiniAppARSessionEventForwarder) -> Void = { _ in },
        removeForwarder: @escaping @MainActor @Sendable (UUID) -> Void = { _ in },
        runSession: @escaping @MainActor @Sendable (ARSession, ARConfiguration, ARSession.RunOptions) -> Void,
        pauseSession: @escaping @MainActor @Sendable (ARSession) -> Void
    ) {
        self.session = session
        self.configuration = configuration
        self.runOptions = runOptions
        self.restartOptions = restartOptions
        self.eventBridge = eventBridge
        self.isSupported = isSupported
        self.installForwarder = installForwarder
        self.removeForwarder = removeForwarder
        self.runSession = runSession
        self.pauseSession = pauseSession
    }

    public func operation() throws -> MiniAppCaptureOperation {
        guard isSupported() else { throw MiniAppCaptureFailure.unsupported }
        let session = session
        let configuration = configuration
        let eventBridge = eventBridge
        let runOptions = runOptions
        let restartOptions = restartOptions
        let isSupported = isSupported
        let installForwarder = installForwarder
        let removeForwarder = removeForwarder
        let runSession = runSession
        let pauseSession = pauseSession
        let context = MiniAppAROperationContext()
        return MiniAppCaptureOperation(
            resources: [.camera],
            nativeEvents: {
                guard let events = context.events else { throw MiniAppCaptureFailure.stopped }
                return events
            },
            restartNative: {
                guard isSupported() else { throw MiniAppCaptureFailure.unsupported }
                runSession(session, configuration, restartOptions)
            },
            startNative: {
                guard isSupported() else { throw MiniAppCaptureFailure.unsupported }
                let (events, forwarder) = try eventBridge.begin()
                context.events = events
                context.forwarder = forwarder
                installForwarder(forwarder)
                runSession(session, configuration, runOptions)
                return { _ in
                    pauseSession(session)
                    eventBridge.end(generation: forwarder.generation)
                    if context.forwarder?.generation == forwarder.generation {
                        context.events = nil
                        context.forwarder = nil
                        removeForwarder(forwarder.generation)
                    }
                }
            }
        )
    }
}

@MainActor
private final class MiniAppAROperationContext {
    var events: MiniAppCaptureNativeEvents?
    var forwarder: MiniAppARSessionEventForwarder?
}
#endif
