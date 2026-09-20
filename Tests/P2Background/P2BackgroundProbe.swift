#if os(iOS)
import Foundation
import CryptoKit
import Darwin
import JibunKitCore
import SwiftUI

@MainActor
enum P2BackgroundProbe {
    static let center = MiniAppContinuedProcessingCenter()
    static let ownerA = P2BackgroundFeature(
        id: MiniAppID("p2-background-a"), title: "Background A",
        continued: center.tasks(for: MiniAppContext(id: MiniAppID("p2-background-a"))),
        requiresBackgroundServices: true)
    static let ownerB = P2BackgroundFeature(
        id: MiniAppID("p2-background-b"), title: "Background B",
        continued: center.tasks(for: MiniAppContext(id: MiniAppID("p2-background-b"))),
        requiresBackgroundServices: true)
    static let definitions: [MiniAppDefinition] = [ownerA.definition, ownerB.definition]
}

@MainActor
final class P2BackgroundFeature: ObservableObject {
    typealias Work = @MainActor @Sendable (
        _ progress: @escaping @MainActor @Sendable (Int64, Int64) -> Void
    ) async throws -> Void

    let id: MiniAppID
    let title: String
    let continuedBaseIdentifier: String
    let observations: P2BackgroundObservationLog
    let nativeComparison: P2ContinuedNativeComparison
    @Published private(set) var status = "未開始"
    @Published private(set) var continuedEvents: [String] = []
    @Published private(set) var progress: Int64 = 0
    @Published private(set) var resultCount = 0
    @Published private(set) var generation = 0
    @Published private(set) var ordinaryStatus = "未受付"
    @Published private(set) var sharedStatus = "未受付"
    @Published private(set) var transferStatus = "未開始"

    private let continued: MiniAppContinuedProcessingTasks
    private let work: Work
    private let backgroundWork: @MainActor @Sendable () async throws -> Void
    private let requiresBackgroundServices: Bool
    private var runtime: MiniAppRuntime?
    private var receipt: MiniAppContinuedProcessingReceipt?
    private var pendingJobIdentifier: UUID?
    private var isCancelling = false
    private var execution: MiniAppContinuedProcessingExecution?
    private var worker: Task<Void, Never>?
    private var backgroundWorkers: [UUID: Task<Void, Never>] = [:]

    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try self.connect(runtime)
    }

    init(id: MiniAppID, title: String, continued: MiniAppContinuedProcessingTasks,
         work: @escaping Work = P2BackgroundFeature.productionWork,
         backgroundWork: @escaping @MainActor @Sendable () async throws -> Void = {
             try await Task.sleep(for: .seconds(1))
         }, requiresBackgroundServices: Bool = false) {
        self.id = id
        observations = P2BackgroundObservationLog(owner: id, persist: requiresBackgroundServices)
        nativeComparison = P2ContinuedNativeComparison(owner: id.rawValue)
        self.title = title
        self.continued = continued
        self.work = work
        self.backgroundWork = backgroundWork
        self.requiresBackgroundServices = requiresBackgroundServices
        continuedBaseIdentifier = "com.jibunkit.app.\(id.rawValue).export"
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: title, systemImage: "gearshape.2", lifetime: lifetime,
            onUnregister: { [weak self] in
                guard let self else { return }
                await self.disable()
                await P2BackgroundServices.deactivate(owner: self.id)
            },
            onHostLaunch: { [self] in
                observations.record("host起動hook（起動理由は未判定）")
                try P2BackgroundServices.register(feature: self)
                observations.record("host背景登録完了")
            }
        ) { [self] _ in P2BackgroundProbeView(feature: self) }
    }

    func submitContinued(strategy: MiniAppContinuedProcessingStrategy = .queue) {
        guard let runtime, !runtime.isClosed, !isCancelling, worker == nil, receipt == nil,
              pendingJobIdentifier == nil, nativeComparison.pendingIdentifier == nil else {
            status = "受付拒否: Feature停止中または仕事実行中"
            return
        }
        let request = MiniAppContinuedProcessingRequest(
            baseIdentifier: continuedBaseIdentifier,
            title: title + " export", subtitle: "Waiting to start", strategy: strategy)
        progress = 0
        pendingJobIdentifier = request.jobIdentifier
        recordContinued("要求 \(strategy == .fail ? "即時" : "待機可") job=\(request.jobIdentifier.uuidString.prefix(8))")
        status = "OS受付応答待ち"
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { recordContinued("受付API: 非同期completion") }
        else { recordContinued("受付API: 旧同期（エラー範囲に制限）") }
        #else
        recordContinued("受付API: 旧SDK同期（エラー範囲に制限）")
        #endif
        do {
            let submitted = try continued.submitReportingResult(request, completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.recordContinued("OS受付応答: 成功（OS開始とは別）")
                    if self.pendingJobIdentifier == request.jobIdentifier {
                        self.status = "受付済み・OS開始未確認 job=\(request.jobIdentifier.uuidString.prefix(8))"
                    }
                case .failure(let error):
                    self.recordContinued("OS受付応答: \(Self.submissionError(error))")
                    if self.pendingJobIdentifier == request.jobIdentifier {
                        self.pendingJobIdentifier = nil
                        self.receipt = nil
                        self.status = Self.submissionError(error)
                    }
                }
            }, launch: { [weak self, weak runtime] execution in
                self?.receive(execution, runtime: runtime)
            })
            if pendingJobIdentifier == request.jobIdentifier { receipt = submitted }
        } catch {
            pendingJobIdentifier = nil
            status = Self.submissionError(error)
            recordContinued(status)
        }
    }

    private static func submissionError(_ error: Error) -> String {
        let native = error as NSError
        return "受付失敗: \(error) [\(native.domain) code=\(native.code)]"
    }

    func compareNative() {
        guard let runtime, !runtime.isClosed, !isCancelling, worker == nil,
              receipt == nil, pendingJobIdentifier == nil else {
            status = "直接比較の受付拒否: Feature停止中または仕事実行中"
            return
        }
        nativeComparison.start()
    }

    func cancelContinued() async {
        guard !isCancelling else { return }
        isCancelling = true
        defer { isCancelling = false }
        // Close admission before cancellation: the OS may already have queued its callback.
        pendingJobIdentifier = nil
        recordContinued("取消要求")
        nativeComparison.cancel()
        if let receipt { try? continued.cancelPendingRequest(identifier: receipt.identifier) }
        receipt = nil
        await cancelWorkerAndJoin(success: false, reason: "Feature取消済み")
        recordContinued(status)
    }

    private func recordContinued(_ message: String) {
        continuedEvents.append("\(Date().ISO8601Format()) \(message)")
        if continuedEvents.count > 32 { continuedEvents.removeFirst(continuedEvents.count - 32) }
    }

    func submitOrdinary() {
        guard runtime?.isClosed == false else { ordinaryStatus = "受付拒否: Feature停止中"; return }
        ordinaryStatus = P2BackgroundServices.submitOrdinary(owner: id)
        observations.record(ordinaryStatus.hasPrefix("受付済み") ? "通常要求: 同期submit成功（OS開始とは別）" : "通常要求: 受付失敗")
    }
    func submitSharedRefresh() {
        guard runtime?.isClosed == false else { sharedStatus = "受付拒否: Feature停止中"; return }
        sharedStatus = P2BackgroundServices.submitShared(owner: id)
        observations.record(sharedStatus.hasPrefix("journal受付 generation=") ? "共有要求: journal受付（OS開始とは別）" : "共有要求: 受付失敗")
    }
    func refreshSharedJournalStatus() { sharedStatus = P2BackgroundServices.sharedStatus(owner: id) }
    func startDownload(urlText: String) async {
        guard let runtime, !runtime.isClosed else { transferStatus = "受付拒否: Feature停止中"; return }
        transferStatus = await P2BackgroundServices.startDownload(
            owner: id, urlText: urlText, runtime: runtime)
    }
    func terminateTransferProcessForDiagnostic() async {
        transferStatus = await P2BackgroundServices.terminateTransferProcessForDiagnostic(owner: id)
    }
    func showSavedTransferEvidence() {
        transferStatus = P2BackgroundServices.transferEvidence(owner: id)
    }

    func admitOrdinary(_ execution: MiniAppBackgroundTaskExecution) {
        observations.record("通常scheduler callback受信")
        Task { @MainActor [weak self, weak execution] in
            guard let self, let execution else { return }
            do {
                try await lifetime.start()
                guard !execution.isExpired else { throw CancellationError() }
                guard let runtime, !runtime.isClosed else { throw P2BackgroundAdmissionFailure.closed }
                let workID = UUID()
                let task = try runtime.start { @MainActor [weak self, weak execution] in
                    guard let execution else { return }
                    await self?.runOrdinary(workID: workID, execution: execution)
                }
                backgroundWorkers[workID] = task
                execution.onExpiration = { [weak self] in self?.backgroundWorkers[workID]?.cancel() }
                ordinaryStatus = "OS起動・runtime仕事中"
            } catch {
                execution.complete(success: false)
                ordinaryStatus = "OS起動拒否: \(error)"
                observations.record("通常callback: runtime受付拒否")
            }
        }
    }

    func admitShared(_ execution: MiniAppSharedRefreshExecution) {
        observations.record(execution.request.isRecovery ? "共有callback受信: journal再試行" : "共有callback受信")
        Task { @MainActor [weak self, weak execution] in
            guard let self, let execution else { return }
            do {
                try await lifetime.start()
                guard !execution.isExpired else { throw CancellationError() }
                guard let runtime, !runtime.isClosed else { throw P2BackgroundAdmissionFailure.closed }
                let workID = UUID()
                let task = try runtime.start { @MainActor [weak self, weak execution] in
                    guard let execution else { return }
                    await self?.runShared(workID: workID, execution: execution)
                }
                backgroundWorkers[workID] = task
                execution.onExpiration = { [weak self] in self?.backgroundWorkers[workID]?.cancel() }
                sharedStatus = execution.request.isRecovery
                    ? "cold recovery runtime仕事中" : "共有refresh runtime仕事中"
            } catch {
                _ = execution.complete(success: false)
                sharedStatus = "共有OS起動拒否・再試行保持: \(error)"
                observations.record("共有callback: runtime受付拒否")
            }
        }
    }

    fileprivate func setTransferStatus(_ value: String) { transferStatus = value }
    fileprivate func setSharedStatus(_ value: String) { sharedStatus = value }

    private func connect(_ runtime: MiniAppRuntime) throws {
        try P2BackgroundServices.bind(
            owner: id, runtime: runtime, required: requiresBackgroundServices)
        try runtime.onShutdownAsync { [weak self, weak runtime] in
            await self?.shutdown(runtime: runtime)
        }
        self.runtime = runtime
        observations.record("runtime接続")
        generation += 1
        status = "利用可能 generation=\(generation)"
    }

    private func receive(_ execution: MiniAppContinuedProcessingExecution, runtime expected: MiniAppRuntime?) {
        recordContinued("OS callback job=\(execution.jobIdentifier.uuidString.prefix(8))")
        guard let runtime, runtime === expected, !runtime.isClosed, !isCancelling,
              worker == nil, pendingJobIdentifier == execution.jobIdentifier else {
            execution.complete(success: false)
            recordContinued("遅着OS起動を拒否")
            if pendingJobIdentifier == nil && self.execution == nil { status = "遅着OS起動を拒否" }
            return
        }
        pendingJobIdentifier = nil
        self.execution = execution
        receipt = nil
        generation += 1
        let acceptedGeneration = generation
        execution.onExpiration = { [weak self, weak execution] in
            guard let self, self.execution === execution else { return }
            Task { @MainActor in
                await self.cancelWorkerAndJoin(success: false, reason: "OS取消/期限切れ cleanup完了")
            }
        }
        status = "OS起動 generation=\(acceptedGeneration)"
        recordContinued(status)
        worker = Task { @MainActor [weak self, weak execution, work] in
            guard let self, let execution else { return }
            do {
                try await work { [weak self, weak execution] completed, total in
                    guard let self, let execution, self.execution === execution,
                          self.generation == acceptedGeneration else { return }
                    self.progress = completed
                    execution.reportProgress(completed: completed, total: total)
                    execution.updateTitle(self.title, subtitle: "\(completed) / \(total)")
                }
                guard self.execution === execution, self.generation == acceptedGeneration else {
                    execution.complete(success: false)
                    return
                }
                execution.complete(success: true)
                self.execution = nil
                self.worker = nil
                self.resultCount += 1
                self.status = "完了 generation=\(acceptedGeneration)"
                self.recordContinued(self.status)
            } catch {
                guard self.execution === execution else { return }
                execution.complete(success: false)
                self.execution = nil
                self.worker = nil
                self.status = "cleanup完了: \(error)"
                self.recordContinued(self.status)
            }
        }
    }

    private func shutdown(runtime expected: MiniAppRuntime?) async {
        guard runtime === expected else { return }
        runtime = nil // close Feature admission before native cancellation/cleanup
        nativeComparison.cancel()
        pendingJobIdentifier = nil
        if let receipt { try? continued.cancelPendingRequest(identifier: receipt.identifier) }
        receipt = nil
        await cancelWorkerAndJoin(success: false, reason: "停止cleanup完了")
    }

    private func runOrdinary(workID: UUID, execution: MiniAppBackgroundTaskExecution) async {
        do {
            try Task.checkCancellation()
            guard !execution.isExpired else { throw CancellationError() }
            try await backgroundWork(); try Task.checkCancellation()
            execution.complete(success: true); ordinaryStatus = "OS仕事完了"
            observations.record("通常仕事完了")
        } catch {
            execution.complete(success: false); ordinaryStatus = "expiration/停止 cleanup完了"
            observations.record("通常仕事: 期限切れ/停止cleanup完了")
        }
        backgroundWorkers.removeValue(forKey: workID)
    }

    private func runShared(workID: UUID, execution: MiniAppSharedRefreshExecution) async {
        do {
            try Task.checkCancellation()
            guard !execution.isExpired else { throw CancellationError() }
            try await backgroundWork(); try Task.checkCancellation()
            _ = execution.complete(success: true); sharedStatus = "共有仕事完了"
            observations.record("共有仕事完了")
        } catch {
            _ = execution.complete(success: false); sharedStatus = "共有cleanup完了・再試行保持"
            observations.record("共有仕事: cleanup完了・再試行保持")
        }
        backgroundWorkers.removeValue(forKey: workID)
    }

    private func cancelWorkerAndJoin(success: Bool, reason: String) async {
        let ownedWorker = worker
        ownedWorker?.cancel()
        await ownedWorker?.value
        execution?.complete(success: success)
        execution = nil
        worker = nil
        status = reason
    }

    private func disable() async {
        lifetime.setStartAllowed(false)
        await lifetime.stop()
    }

    private static func productionWork(
        progress: @escaping @MainActor @Sendable (Int64, Int64) -> Void
    ) async throws {
        for unit in 1...60 {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
            progress(Int64(unit), 60)
        }
    }
}

@MainActor
private enum P2BackgroundServices {
    static let backgroundCenter = MiniAppBackgroundTaskCenter()
    static var sharedCenter: MiniAppSharedRefreshCenter?
    static var ordinary: [MiniAppID: MiniAppBackgroundTasks] = [:]
    static var shared: [MiniAppID: MiniAppSharedRefresh] = [:]
    static var urlConnections: [MiniAppID: P2BackgroundURLConnection] = [:]

    static func register(feature: P2BackgroundFeature) throws {
        let context = MiniAppContext(id: feature.id)
        let ordinaryTasks = backgroundCenter.tasks(for: context)
        let ordinaryIdentifier = "com.jibunkit.app.\(feature.id.rawValue).ordinary"
        let kind: MiniAppBackgroundTaskKind = feature.id == MiniAppID("p2-background-a")
            ? .appRefresh : .processing
        try ordinaryTasks.register(identifier: ordinaryIdentifier, kind: kind) { [weak feature] in
            guard let feature else { $0.complete(success: false); return }
            feature.admitOrdinary($0)
        }
        ordinary[feature.id] = ordinaryTasks

        let sharedCenter = try sharedRefreshCenter()
        let sharedTasks = sharedCenter.refreshes(for: context)
        try sharedTasks.register(identifier: "refresh") { [weak feature] in
            guard let feature else { _ = $0.complete(success: false); return }
            feature.admitShared($0)
        }
        shared[feature.id] = sharedTasks
        _ = sharedCenter.reconcile()
        feature.setSharedStatus(sharedStatus(owner: feature.id))

        let connection = P2BackgroundURLConnection(owner: feature.id, feature: feature) { [weak feature] in
            feature?.setTransferStatus($0)
        }
        do { try connection.register(context: context) }
        catch { throw error }
        urlConnections[feature.id] = connection
    }

    static func submitOrdinary(owner: MiniAppID) -> String {
        guard let tasks = ordinary[owner] else { return "受付拒否: ordinary未登録" }
        do {
            try tasks.submit(.init(
                identifier: "com.jibunkit.app.\(owner.rawValue).ordinary",
                requiresNetworkConnectivity: owner == MiniAppID("p2-background-b")))
            return "受付済み（OS起動待ち）"
        } catch { return "受付失敗: \(error)" }
    }

    static func bind(owner: MiniAppID, runtime: MiniAppRuntime, required: Bool) throws {
        guard let connection = urlConnections[owner] else {
            if required { throw P2BackgroundAdmissionFailure.servicesNotRegistered }
            return
        }
        try connection.bind(runtime: runtime)
    }

    static func deactivate(owner: MiniAppID) async {
        ordinary[owner]?.cancelAllPendingRequests()
        if let sharedTasks = shared[owner] { try? sharedTasks.cancelAllPendingRequests() }
        if let sharedCenter { _ = sharedCenter.reconcile() }
        await urlConnections[owner]?.deactivate()
    }

    static func submitShared(owner: MiniAppID) -> String {
        guard let tasks = shared[owner] else { return "受付拒否: shared refresh未登録" }
        do {
            let receipt = try tasks.submit(identifier: "refresh")
            let generation = String(receipt.generation.uuidString.prefix(8))
            return "journal受付 generation=\(generation)"
        } catch { return "journal受付失敗: \(error)" }
    }

    static func sharedStatus(owner: MiniAppID) -> String {
        let pending = shared[owner]?.pendingRequests ?? []
        return pending.isEmpty ? "journal空" : pending.map {
            "\($0.generation.uuidString.prefix(8)):recovery=\($0.isRecovery)"
        }.joined(separator: ",")
    }

    static func startDownload(owner: MiniAppID, urlText: String,
                              runtime: MiniAppRuntime) async -> String {
        guard let url = URL(string: urlText), let connection = urlConnections[owner] else {
            return "URL/connection不正"
        }
        return await connection.start(url: url, runtime: runtime)
    }

    static func terminateTransferProcessForDiagnostic(owner: MiniAppID) async -> String {
        guard let connection = urlConnections[owner] else { return "診断終了拒否: connection未登録" }
        return await connection.terminateProcessForDiagnostic()
    }

    static func transferEvidence(owner: MiniAppID) -> String {
        urlConnections[owner]?.evidenceSummary ?? "転送証拠: connection未登録"
    }

    private static func sharedRefreshCenter() throws -> MiniAppSharedRefreshCenter {
        if let sharedCenter { return sharedCenter }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("P2Background", isDirectory: true)
        let center = try MiniAppSharedRefreshCenter(
            identifier: "com.jibunkit.app.p2-background.shared-refresh",
            journalURL: support.appendingPathComponent("shared-refresh.json"))
        sharedCenter = center
        return center
    }
}

@MainActor
final class P2BackgroundURLConnection: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let owner: MiniAppID
    nonisolated let destinationDirectory: URL
    private let status: @MainActor (String) -> Void
    private weak var feature: P2BackgroundFeature?
    nonisolated private let delegateState = P2URLDelegateState()
    private var registration: MiniAppBackgroundURLSessionRegistration?
    private var session: URLSession?
    private var events: MiniAppBackgroundURLSessionEvents?
    private var eventsRun: UUID?
    private var evidence: P2BackgroundTransferEvidence?
    private weak var runtime: MiniAppRuntime?
    private var boundRuntimeID: ObjectIdentifier?
    private var isInvalidating = false
    private var invalidationWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingRecords: [Int: P2URLDelegateRecord] = [:]
    private var nextRecord = 1
    private(set) var sessionGeneration = 0
    var hasSession: Bool { session != nil }

    init(owner: MiniAppID, feature: P2BackgroundFeature,
         status: @escaping @MainActor (String) -> Void) {
        self.owner = owner
        self.feature = feature
        self.status = status
        destinationDirectory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                         in: .userDomainMask)[0]
            .appendingPathComponent("P2Background/Downloads/\(owner.storageNamespace)", isDirectory: true)
    }

    func register(context: MiniAppContext) throws {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        evidence = P2BackgroundTransferEvidence(owner: owner, files: try MiniAppFiles.shared(context: context))
        registration = try MiniAppBackgroundURLSessionReconnectRegistry.shared.register(
            context: context, profile: "diagnostic") { [weak self] identifier, events in
                guard let self else { throw P2BackgroundConnectionFailure.released }
                self.beginReconnect(identifier: identifier, events: events)
            }
    }

    func bind(runtime: MiniAppRuntime) throws {
        let id = ObjectIdentifier(runtime)
        if boundRuntimeID == id { return }
        try runtime.onShutdownAsync { [weak self, weak runtime] in
            await self?.deactivate(expected: runtime)
        }
        self.runtime = runtime
        boundRuntimeID = id
    }

    func start(url: URL, runtime expected: MiniAppRuntime) async -> String {
        guard let identifier = registration?.identifier else { return "未登録" }
        guard let evidence else { return "転送証拠未登録" }
        guard runtime === expected, !expected.isClosed else { return "受付拒否: runtime停止中" }
        guard evidence.canBegin() else { return "受付拒否: 未完了runまたは読込不能な診断証拠あり" }
        ensureSession(identifier: identifier)
        let task = session!.downloadTask(with: url)
        let run = UUID()
        do { task.taskDescription = try evidence.begin(
            sessionIdentifier: identifier, taskIdentifier: task.taskIdentifier, run: run)
        } catch {
            delegateState.ignore(taskID: task.taskIdentifier)
            task.cancel()
            return "受付拒否: 診断runを永続化できません"
        }
        feature?.observations.record("HTTP転送要求（OS再接続とは別）")
        task.resume()
        return "download開始 run=\(run.uuidString.prefix(8)) task=\(task.taskIdentifier) owner=\(owner.rawValue)"
    }

    func terminateProcessForDiagnostic() async -> String {
        guard let session, let evidence else { return "診断終了拒否: 転送未開始" }
        let tasks = await session.allTasks
        let pending = tasks.map { P2BackgroundTransferEvidence.PendingTask(
            identifier: $0.taskIdentifier, taskDescription: $0.taskDescription) }
        guard evidence.canTerminateForDiagnostic(pendingTasks: pending) else {
            return "診断終了拒否: pending task/永続runを確認できません"
        }
        guard evidence.noteTerminationRequested() else {
            return "診断終了拒否: 終了markerを永続化できません"
        }
        let confirmedTasks = (await session.allTasks).map { P2BackgroundTransferEvidence.PendingTask(
            identifier: $0.taskIdentifier, taskDescription: $0.taskDescription) }
        guard evidence.canExitAfterTerminationMarker(pendingTasks: confirmedTasks) else {
            return "診断終了拒否: 終了直前のpending task/marker一致を確認できません"
        }
        feature?.observations.record("診断process終了要求（pending task・永続run確認済み）")
        _ = UIApplication.shared.beginBackgroundTask(withName: "P2BackgroundColdRestorationDiagnostic")
        Darwin.exit(0)
    }

    var evidenceSummary: String { evidence?.summary ?? "転送証拠: 未開始" }

    func deactivate() async { await deactivate(expected: runtime) }

    private func deactivate(expected: MiniAppRuntime?) async {
        guard expected == nil || runtime === expected else { return }
        runtime = nil
        boundRuntimeID = nil
        guard let session else { return }
        await withCheckedContinuation { continuation in
            invalidationWaiters.append(continuation)
            if !isInvalidating {
                isInvalidating = true
                session.invalidateAndCancel()
            }
        }
    }

    private func ensureSession(identifier: String) {
        if let session { precondition(session.configuration.identifier == identifier); return }
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        sessionGeneration += 1
    }

    private func beginReconnect(identifier: String, events: MiniAppBackgroundURLSessionEvents) {
        feature?.observations.record("host URLSession callback受信")
        eventsRun = evidence?.noteHostCallback(sessionIdentifier: identifier)
        Task { @MainActor [weak self] in
            guard let self, let feature = self.feature else { events.finish(); return }
            do {
                try await feature.lifetime.start()
                guard let runtime = feature.lifetime.runtime, !runtime.isClosed else {
                    throw P2BackgroundAdmissionFailure.closed
                }
                try bind(runtime: runtime)
                self.events = events
                ensureSession(identifier: identifier)
                evidence?.noteOwnerReconnected(run: eventsRun)
                feature.observations.record("HTTP再接続受付・delegate待ち")
                status("OS callback再接続・delegate event待ち")
            } catch {
                feature.observations.record("HTTP再接続: runtime受付拒否")
                status("OS callback受付拒否: \(error)")
                // This is an owned session even when its Feature is disabled.
                // Cancel its OS tasks and join delegate invalidation before
                // releasing the host's completion callback.
                self.events = events
                ensureSession(identifier: identifier)
                await deactivate(expected: nil)
            }
        }
    }

    private func receive(_ record: P2URLDelegateRecord) {
        pendingRecords[record.sequence] = record
        while let record = pendingRecords.removeValue(forKey: nextRecord) {
            nextRecord += 1
            switch record.kind {
            case .ignored:
                continue
            case .completion(let message, let result):
                if let saved = result.saved {
                    evidence?.noteSaved(taskDescription: result.taskDescription,
                                        taskIdentifier: result.taskIdentifier,
                                        size: saved.size, sha256: saved.sha256)
                }
                evidence?.noteTaskCompletion(taskDescription: result.taskDescription,
                                             taskIdentifier: result.taskIdentifier,
                                             error: result.errorDescription.map(P2RecordedTransferError.init))
                feature?.observations.record(message.hasPrefix("download保存") ? "HTTP完了: ファイル保存" : "HTTP完了: 失敗/保存未確認")
                status(message)
            case .finishedEvents:
                let finished = events
                let finishedRun = eventsRun
                events = nil
                eventsRun = nil
                evidence?.noteFinishedEvents(run: finishedRun)
                let returned = finished?.finish() == true
                if returned { evidence?.noteHostCompletionReturned(run: finishedRun) }
                feature?.observations.record(returned ? "HTTP全delegate完了・host completion返却後" : "HTTP全delegate完了（host completion返却なし）")
                status(returned ? (evidence?.summary ?? "全delegate event完了・host completion返却後") : "全delegate event完了（host completion返却なし）")
            case .invalidated(let reason):
                session = nil
                isInvalidating = false
                feature?.observations.record("HTTP native session無効化完了")
                status("native session無効化完了" + (reason.map { ": \($0)" } ?? ""))
                let finished = events
                events = nil
                eventsRun = nil
                finished?.finish()
                let waiters = invalidationWaiters
                invalidationWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didFinishDownloadingTo location: URL) {
        let destination = destinationDirectory.appendingPathComponent(
            "\(downloadTask.taskIdentifier)-\(UUID().uuidString).download")
        delegateState.store(taskID: downloadTask.taskIdentifier,
                            taskDescription: downloadTask.taskDescription, location: location,
                            destination: destination)
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               didCompleteWithError error: Error?) {
        let record = delegateState.complete(taskID: task.taskIdentifier,
                                            taskDescription: task.taskDescription, error: error)
        Task { @MainActor [weak self] in self?.receive(record) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let record = delegateState.finishedEvents()
        Task { @MainActor [weak self] in self?.receive(record) }
    }

    nonisolated func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let record = delegateState.invalidated(error: error)
        Task { @MainActor [weak self] in self?.receive(record) }
    }
}

private struct P2URLDelegateRecord: Sendable {
    struct Saved: Sendable { let size: Int; let sha256: String }
    struct Completion: Sendable {
        let taskIdentifier: Int
        let taskDescription: String?
        let saved: Saved?
        let errorDescription: String?
    }
    enum Kind: Sendable { case ignored, completion(String, Completion), finishedEvents, invalidated(String?) }
    let sequence: Int
    let kind: Kind
}

private final class P2URLDelegateState: @unchecked Sendable {
    private let lock = NSLock()
    private var nextSequence = 1
    private struct Stored { let taskDescription: String?; let result: Result<P2URLDelegateRecord.Saved, Error> }
    private var locations: [Int: Stored] = [:]
    private var completionCount = 0
    private var ignoredTaskIDs: Set<Int> = []

    func ignore(taskID: Int) {
        lock.lock(); defer { lock.unlock() }
        ignoredTaskIDs.insert(taskID)
    }

    func store(taskID: Int, taskDescription: String?, location: URL, destination: URL) {
        lock.lock(); defer { lock.unlock() }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let (size, digest) = try hashFile(at: destination)
            locations[taskID] = Stored(taskDescription: taskDescription,
                                       result: .success(.init(size: size, sha256: digest)))
        } catch { locations[taskID] = Stored(taskDescription: taskDescription, result: .failure(error)) }
    }

    func complete(taskID: Int, taskDescription: String?, error: Error?) -> P2URLDelegateRecord {
        lock.lock(); defer { lock.unlock() }
        if ignoredTaskIDs.remove(taskID) != nil { return record(.ignored) }
        completionCount += 1
        let message: String
        let stored = locations.removeValue(forKey: taskID)
        let result = stored?.result
        if let error { message = "download失敗 events=\(completionCount): \(error)" }
        else if let result {
            switch result {
            case .success(let saved): message = "download保存 events=\(completionCount): size=\(saved.size) sha256=\(saved.sha256)"
            case .failure(let error): message = "保存失敗 events=\(completionCount): \(error)"
            }
        } else { message = "download完了だが保存先なし events=\(completionCount)" }
        let saved: P2URLDelegateRecord.Saved?
        let storedError: String?
        if let result {
            switch result {
            case .success(let value): saved = value; storedError = nil
            case .failure(let failure): saved = nil; storedError = String(describing: failure)
            }
        } else {
            saved = nil; storedError = nil
        }
        let completion = P2URLDelegateRecord.Completion(
            taskIdentifier: taskID, taskDescription: stored?.taskDescription ?? taskDescription,
            saved: saved, errorDescription: error.map { String(describing: $0) } ?? storedError)
        return record(.completion(message, completion))
    }

    func finishedEvents() -> P2URLDelegateRecord { lockedRecord(.finishedEvents) }
    func invalidated(error: Error?) -> P2URLDelegateRecord {
        lockedRecord(.invalidated(error.map { String(describing: $0) }))
    }
    private func lockedRecord(_ kind: P2URLDelegateRecord.Kind) -> P2URLDelegateRecord {
        lock.lock(); defer { lock.unlock() }; return record(kind)
    }
    private func record(_ kind: P2URLDelegateRecord.Kind) -> P2URLDelegateRecord {
        defer { nextSequence += 1 }
        return .init(sequence: nextSequence, kind: kind)
    }

    private func hashFile(at url: URL) throws -> (Int, String) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size = 0
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            size += chunk.count
            hasher.update(data: chunk)
        }
        return (size, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

private struct P2RecordedTransferError: Error { let description: String; init(_ description: String) { self.description = description } }

private enum P2BackgroundConnectionFailure: Error { case released }
private enum P2BackgroundAdmissionFailure: Error { case closed, servicesNotRegistered }

private struct P2BackgroundProbeView: View {
    @ObservedObject var feature: P2BackgroundFeature
    @State private var downloadURL = ""
    var body: some View {
        Form {
            Text(feature.status).accessibilityIdentifier("p2.background.\(feature.id.rawValue).status")
            Text("進捗 \(feature.progress)/60 成果 \(feature.resultCount) 世代 \(feature.generation)")
            Button("継続処理を即時開始") { feature.submitContinued(strategy: .fail) }
            Button("継続処理を待機可で受付") { feature.submitContinued(strategy: .queue) }
            Text("即時開始できない場合はエラーを表示します。待機可の受付成功だけでは処理開始を意味しません。")
            Button("継続処理を取消") { Task { await feature.cancelContinued() } }
            DisclosureGroup("継続処理の記録（この起動中・最新32件）") {
                Text(feature.continuedEvents.joined(separator: "\n"))
                    .font(.caption).textSelection(.enabled)
            }
            P2ContinuedNativeComparisonView(comparison: feature.nativeComparison, start: feature.compareNative)
            Divider()
            P2BackgroundObservationView(log: feature.observations)
            Text(feature.ordinaryStatus); Button("通常refresh/processingを受付") { feature.submitOrdinary() }
            Text(feature.sharedStatus); Button("共有refreshをjournal受付") { feature.submitSharedRefresh() }
            Button("journal状態を再読込") { feature.refreshSharedJournalStatus() }
            Divider()
            TextField("診断HTTP URL", text: $downloadURL).textInputAutocapitalization(.never)
            Text(feature.transferStatus).textSelection(.enabled)
            Button("background download開始") {
                Task { await feature.startDownload(urlText: downloadURL) }
            }
            Button("転送中のprocessを終了（診断）", role: .destructive) {
                Task { await feature.terminateTransferProcessForDiagnostic() }
            }
            Button("保存済みの転送証拠を表示") { feature.showSavedTransferEvidence() }
            Text("pending taskと永続runを確認できた場合だけ終了します。force quitや転送の再要求は行いません。")
        }
    }
}
#endif
