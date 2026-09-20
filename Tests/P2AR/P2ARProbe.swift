#if canImport(ARKit) && os(iOS)
@preconcurrency import ARKit
import JibunKitCore
import SwiftUI

@MainActor
enum P2ARProbe {
    static let feature = P2ARFeature()
    static var definitions: [MiniAppDefinition] { [feature.definition] }
}

@MainActor
final class P2ARFeature {
    let id: MiniAppID
    let state: P2ARState
    let owner: MiniAppCaptureOwner
    let contenderOwner: MiniAppCaptureOwner
    let lifetime: MiniAppFeatureLifetime
    private let permissionProbe: any MiniAppCapturePermissionClient
    private let consentGate: P2ARConsentGate
    private let contenderOperation: @MainActor () -> MiniAppCaptureOperation
    private let runFactory: @MainActor (P2ARState) -> P2ARRun
    private var contenderScenes: [UUID: MiniAppSceneActivityDispatcher] = [:]
    private(set) var activeRun: P2ARRun?

    init(
        id: MiniAppID = MiniAppID("p2-ar"),
        coordinator: MiniAppCaptureCoordinator = .shared,
        permissions: any MiniAppCapturePermissionClient = MiniAppAVCapturePermissionClient(),
        contenderOperation: (@MainActor () -> MiniAppCaptureOperation)? = nil,
        runFactory: (@MainActor (P2ARState) -> P2ARRun)? = nil
    ) {
        self.id = id
        let state = P2ARState()
        self.state = state
        let gate = P2ARConsentGate(owner: id)
        consentGate = gate
        permissionProbe = permissions
        let captureOwner = MiniAppCaptureOwner(
            id: id, coordinator: coordinator, permissions: permissions,
            consent: { [gate] in gate.allows($0) }
        )
        owner = captureOwner
        let contender = MiniAppCaptureOwner(
            id: MiniAppID("p2-ar-camera-contender"), coordinator: coordinator,
            permissions: permissions, consent: { [gate] in gate.allows($0) }
        )
        contenderOwner = contender
        self.contenderOperation = contenderOperation ?? { Self.makeRealCameraOperation() }
        self.runFactory = runFactory ?? { P2ARRun(state: $0) }
        lifetime = MiniAppFeatureLifetime(id: id) { [captureOwner, contender, state] runtime in
            try captureOwner.connect(to: runtime)
            try contender.connect(to: runtime)
            state.runtimeGeneration += 1
            state.status = "AR利用可能"
            state.append("runtime connected generation=\(state.runtimeGeneration)")
        }
        contender.stateChanged = { [weak state] captureState in
            state?.contenderStatus = "Camera B: \(captureState)"
            state?.append("Camera B owner state=\(captureState)")
        }
        captureOwner.stateChanged = { [weak self] in self?.receiveARState($0) }
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: "AR Probe", systemImage: "arkit",
            lifetime: lifetime,
            permissions: [
                .init(id: "camera", title: "カメラ", purpose: "前景AR表示に使います",
                      deniedBehavior: "ARSessionを開始しません")
            ],
            onConsentChange: { [weak captureOwner = owner, weak contenderOwner = contenderOwner] permissionID, decision in
                guard permissionID == "camera", decision != .allowed else { return }
                Task { @MainActor in
                    await captureOwner?.suspend(.featureStopped)
                    await contenderOwner?.suspend(.featureStopped)
                }
            },
            onSceneActivityChange: { [weak self] in self?.receiveSceneActivity($0) }
        ) { [self] _ in P2ARView(feature: self) }
    }

    func attachConsent(_ store: MiniAppConsentStore?) {
        consentGate.store = store
    }

    func start(in sceneID: UUID?) async {
        guard let sceneID else { state.status = "scene未接続"; return }
        guard activeRun == nil else {
            state.append("duplicate AR start ignored; active run retained")
            return
        }
        let run = runFactory(state)
        activeRun = run
        state.activate(run: run.id)
        do {
            try await owner.start(try run.operation(), sceneScope: .scene(sceneID))
            state.status = "AR実行中"
        } catch {
            finish(run: run, reason: "start failed")
            state.status = "AR開始失敗: \(error)"
        }
    }

    func stop() async {
        let run = activeRun
        await owner.stop()
        if let run { finish(run: run, reason: "explicit stop") }
        state.status = "AR停止・camera解放"
    }

    /// Diagnostic-only OS-copy probe. This deliberately bypasses ARKit's
    /// hardware support gate so Simulator can display the real camera sheet;
    /// it does not start AR or alter the Feature-consent policy.
    func requestCameraPermissionForOSCopy() async {
        let allowed = await permissionProbe.request(.camera)
        state.status = allowed ? "camera OS許可" : "camera OS拒否"
    }

    private func receiveARState(_ captureState: MiniAppCaptureState) {
        let runID = activeRun?.id
        state.observeARState(captureState, run: runID)
        switch captureState {
        case .requesting: state.status = "AR許可確認中"
        case .starting: state.status = "AR開始中"
        case .running: state.status = "AR実行中"
        case .stopping(let reason): state.status = "AR停止中: \(reason)"
        case .suspended(let reason): state.status = "AR中断/停止: \(reason)"
        case .failed(let failure): state.status = "AR失敗: \(failure)"
        case .stopped: state.status = "AR Feature停止"
        case .idle: state.status = "AR利用可能"
        }
        switch captureState {
        case .suspended(.interrupted(_)): break
        case .stopping(_), .suspended(_), .failed(_), .stopped:
            if let run = activeRun { finish(run: run, reason: "owner state \(captureState)") }
        default: break
        }
    }

    private func finish(run: P2ARRun, reason: String) {
        guard activeRun === run else { return }
        activeRun = nil
        state.deactivate(run: run.id, reason: reason)
    }

    func startContender(switching: MiniAppCaptureSwitch, in sceneID: UUID?) async {
        guard let sceneID else { state.contenderStatus = "Camera B: scene未接続"; return }
        guard let contenderSceneID = contenderScenes[sceneID]?.connectionID else {
            state.contenderStatus = "Camera B: 対応scene未接続"
            return
        }
        do {
            try await contenderOwner.start(
                contenderOperation(), switching: switching, sceneScope: .scene(contenderSceneID)
            )
            state.contenderStatus = "Camera B: 実行中"
        } catch {
            state.contenderStatus = "Camera B: 拒否/失敗 \(error)"
            state.append("Camera B request result=\(error)")
        }
    }

    func stopContender() async {
        await contenderOwner.stop()
        state.contenderStatus = "Camera B: 停止・camera解放"
    }

    private func receiveSceneActivity(_ activity: MiniAppSceneActivity) {
        owner.receive(activity)
        if let phase = activity.phase {
            let dispatcher: MiniAppSceneActivityDispatcher
            if let existing = contenderScenes[activity.sceneID] {
                dispatcher = existing
            } else {
                dispatcher = MiniAppSceneActivityDispatcher(handlers: [
                    .init(id: contenderOwner.id) { [weak contenderOwner = contenderOwner] in
                        contenderOwner?.receive($0)
                    }
                ])
                contenderScenes[activity.sceneID] = dispatcher
            }
            dispatcher.connect(
                phase: phase,
                selectedID: activity.isSelected ? contenderOwner.id : nil
            )
        } else if let dispatcher = contenderScenes.removeValue(forKey: activity.sceneID) {
            dispatcher.disconnect()
        }
    }

    private static func makeRealCameraOperation() -> MiniAppCaptureOperation {
        let producer = MiniAppAVCaptureSessionProducer(mode: .photo)
        return MiniAppCaptureOperation(
            resources: [.camera],
            nativeEvents: { try await producer.events() },
            restartNative: { try await producer.restartAfterInterruption() },
            startNative: {
                try await producer.start()
                return { _ in await producer.stop() }
            }
        )
    }
}

@MainActor
final class P2ARState: ObservableObject {
    @Published var status = "未接続"
    @Published var frameCount = 0
    @Published var anchorCount = 0
    @Published var runtimeGeneration = 0
    @Published var contenderStatus = "Camera B: 停止中"
    @Published private(set) var observationLines: [String] = []
    private struct Interruption {
        let run: UUID
        let sequence: Int
        var ended = false
        var restarted = false
        var receivedFrame = false
    }
    private var activeRun: UUID?
    private var nextSequence = 0
    private var interruption: Interruption?

    func append(_ message: String) {
        observationLines.append("\(Date.now.ISO8601Format()) \(message)")
        if observationLines.count > 80 { observationLines.removeFirst(observationLines.count - 80) }
    }

    func activate(run: UUID) {
        activeRun = run
        interruption = nil
        append("AR run=\(short(run)) activated")
    }

    func deactivate(run: UUID, reason: String) {
        guard activeRun == run else {
            append("unattributed deactivate ignored run=\(short(run)) reason=\(reason)")
            return
        }
        activeRun = nil
        interruption = nil
        append("AR run=\(short(run)) deactivated reason=\(reason)")
    }

    func interruptionBegan(run: UUID, source: String) {
        guard activeRun == run else {
            append("unattributed \(source) interruption began ignored run=\(short(run))")
            return
        }
        guard interruption == nil else {
            append("duplicate \(source) interruption began ignored run=\(short(run))")
            return
        }
        nextSequence += 1
        interruption = .init(run: run, sequence: nextSequence)
        append("\(source) interruption began run=\(short(run)) seq=\(nextSequence)")
    }

    func interruptionEnded(run: UUID, source: String) {
        guard activeRun == run, var current = interruption,
              current.run == run, !current.ended else {
            append("unmatched \(source) interruption ended ignored run=\(short(run))")
            return
        }
        current.ended = true
        interruption = current
        append("\(source) interruption ended run=\(short(run)) seq=\(current.sequence); restart pending")
    }

    func observeARState(_ value: MiniAppCaptureState, run: UUID?) {
        append("AR owner state=\(value) run=\(run.map { short($0) } ?? "none")")
        guard let run, activeRun == run, var current = interruption,
              current.run == run, current.ended, !current.restarted else { return }
        if case .running = value {
            current.restarted = true
            interruption = current
            append("AR restart completed run=\(short(run)) seq=\(current.sequence)")
        } else {
            switch value {
            case .failed(_), .stopped, .suspended(.failure(_)), .suspended(.user),
                 .suspended(.featureStopped), .suspended(.switched(to: _)):
                interruption = nil
                append("AR interruption recovery ended without resumed frame run=\(short(run)) seq=\(current.sequence)")
            default: break
            }
        }
    }

    func receivedFrame(run: UUID, source: String) {
        guard activeRun == run else {
            append("unattributed \(source) frame ignored run=\(short(run))")
            return
        }
        frameCount += 1
        guard var current = interruption, current.run == run, current.ended,
              current.restarted, !current.receivedFrame else { return }
        current.receivedFrame = true
        append("first frame after interruption run=\(short(run)) seq=\(current.sequence)")
        interruption = nil
    }

    func receivedAnchors(_ count: Int, run: UUID) {
        guard activeRun == run else {
            append("unattributed anchors ignored run=\(short(run)) count=\(count)")
            return
        }
        anchorCount += count
    }

    private func short(_ value: UUID) -> String { String(value.uuidString.suffix(8)) }
}

@MainActor
private final class P2ARConsentGate {
    let owner: MiniAppID
    var store: MiniAppConsentStore?
    init(owner: MiniAppID) { self.owner = owner }
    func allows(_ resource: MiniAppCaptureResource) -> Bool {
        resource == .camera && store?.consent(for: owner, permissionID: "camera") == .allowed
    }
}

@MainActor
final class P2ARRun {
    let id: UUID
    let session: ARSession
    let delegate: P2ARFeatureDelegate
    let adapter: MiniAppARSessionAdapter
    private let operationOverride: MiniAppCaptureOperation?

    init(state: P2ARState, operation: MiniAppCaptureOperation? = nil) {
        let runID = UUID()
        let session = ARSession()
        let bridge = MiniAppARSessionEventBridge()
        let delegate = P2ARFeatureDelegate(run: runID, state: state)
        id = runID
        self.session = session
        self.delegate = delegate
        operationOverride = operation
        adapter = MiniAppARSessionAdapter(
            session: session,
            configuration: ARWorldTrackingConfiguration(),
            runOptions: [.resetTracking, .removeExistingAnchors],
            restartOptions: [],
            eventBridge: bridge,
            isSupported: { ARWorldTrackingConfiguration.isSupported },
            installForwarder: { [weak delegate] in delegate?.install($0) },
            removeForwarder: { [weak delegate] in delegate?.remove(generation: $0) }
        )
        session.delegate = delegate
    }

    func operation() throws -> MiniAppCaptureOperation {
        if let operationOverride { return operationOverride }
        return try adapter.operation()
    }
}

/// One delegate belongs to exactly one ARSession run. A delayed callback keeps
/// that run ID and can never borrow the next run's forwarder.
final class P2ARFeatureDelegate: NSObject, ARSessionDelegate, @unchecked Sendable {
    private let run: UUID
    private weak var state: P2ARState?
    private let lock = NSLock()
    private var forwarder: MiniAppARSessionEventForwarder?

    init(run: UUID, state: P2ARState) {
        self.run = run
        self.state = state
        super.init()
    }

    nonisolated func install(_ value: MiniAppARSessionEventForwarder) {
        lock.withLock { forwarder = value }
    }

    nonisolated func remove(generation: UUID) {
        lock.withLock {
            if forwarder?.generation == generation { forwarder = nil }
        }
    }

    private nonisolated func currentForwarder() -> MiniAppARSessionEventForwarder? {
        lock.withLock { forwarder }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        recordFrame(source: "OS ARSessionDelegate")
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let count = anchors.count
        Task { @MainActor [weak state, run] in state?.receivedAnchors(count, run: run) }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        recordInterruptionBegan(source: "OS ARSessionDelegate")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        recordInterruptionEnded(source: "OS ARSessionDelegate")
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        currentForwarder()?.runtimeFailed(reason: String(describing: error), canRestart: false)
    }

    func recordInterruptionBegan(source: String) {
        let forwarder = currentForwarder()
        Task { @MainActor [weak state, run] in
            state?.interruptionBegan(run: run, source: source)
            forwarder?.interruptionBegan()
        }
    }

    func recordInterruptionEnded(source: String) {
        let forwarder = currentForwarder()
        Task { @MainActor [weak state, run] in
            state?.interruptionEnded(run: run, source: source)
            forwarder?.interruptionEnded()
        }
    }

    func recordFrame(source: String) {
        Task { @MainActor [weak state, run] in state?.receivedFrame(run: run, source: source) }
    }
}

private struct P2ARView: View {
    @Environment(\.miniAppConsentStore) private var consentStore
    @Environment(\.miniAppSceneActivityID) private var sceneID
    @ObservedObject var state: P2ARState
    let feature: P2ARFeature

    init(feature: P2ARFeature) {
        self.feature = feature
        state = feature.state
    }

    var body: some View {
        Form {
            Text(state.status).accessibilityIdentifier("p2.ar.status")
            Text("frames \(state.frameCount) / anchors \(state.anchorCount) / runtime \(state.runtimeGeneration)")
                .accessibilityIdentifier("p2.ar.counts")
            Button("AR開始") { Task { await feature.start(in: sceneID) } }
                .accessibilityIdentifier("p2.ar.start")
            Button("AR停止") { Task { await feature.stop() } }
                .accessibilityIdentifier("p2.ar.stop")
            Button("camera OS文言を確認") {
                Task { await feature.requestCameraPermissionForOSCopy() }
            }
            .accessibilityIdentifier("p2.ar.camera-permission-copy")
            Section("同一画面のcamera競合") {
                Text(state.contenderStatus).accessibilityIdentifier("p2.ar.contender.status")
                Button("Camera B要求（reject）") {
                    Task { await feature.startContender(switching: .reject, in: sceneID) }
                }
                Button("Camera B要求（stopCurrent）") {
                    Task { await feature.startContender(switching: .stopCurrent, in: sceneID) }
                }
                Button("Camera B停止") { Task { await feature.stopContender() } }
            }
            Section("AR観測（最大80行）") {
                ShareLink("AR観測を共有", item: state.observationLines.joined(separator: "\n"))
                Text(state.observationLines.isEmpty ? "記録なし" : state.observationLines.joined(separator: "\n"))
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .onAppear { feature.attachConsent(consentStore) }
    }
}
#endif
