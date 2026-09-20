#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
import Foundation

@MainActor
private final class SystemBackgroundTask: MiniAppBackgroundTaskNative {
    private let task: BGTask
    private var bridgedExpirationHandler: (@MainActor @Sendable () -> Void)?

    init(_ task: BGTask) { self.task = task }

    var expirationHandler: (@MainActor @Sendable () -> Void)? {
        get { bridgedExpirationHandler }
        set {
            bridgedExpirationHandler = newValue
            task.expirationHandler = newValue.map { handler in
                { MiniAppBackgroundTaskActorBridge.deliverExpiration(handler) }
            }
        }
    }

    func setTaskCompleted(success: Bool) { task.setTaskCompleted(success: success) }
}

@MainActor
private final class SystemBackgroundTaskScheduler: MiniAppBackgroundTaskScheduling {
    private let scheduler: BGTaskScheduler

    init(_ scheduler: BGTaskScheduler) { self.scheduler = scheduler }

    func register(
        identifier: String,
        kind: MiniAppBackgroundTaskKind,
        launch: @escaping @MainActor (any MiniAppBackgroundTaskNative) -> Void
    ) -> Bool {
        scheduler.register(forTaskWithIdentifier: MiniAppBackgroundTaskIdentifier.resolve(identifier), using: .main) { task in
            Task { @MainActor in launch(SystemBackgroundTask(task)) }
        }
    }

    func submit(_ request: MiniAppBackgroundTaskRequest, kind: MiniAppBackgroundTaskKind) throws {
        let identifier = MiniAppBackgroundTaskIdentifier.resolve(request.identifier)
        let native: BGTaskRequest
        switch kind {
        case .appRefresh:
            native = BGAppRefreshTaskRequest(identifier: identifier)
        case .processing:
            let processing = BGProcessingTaskRequest(identifier: identifier)
            processing.requiresNetworkConnectivity = request.requiresNetworkConnectivity
            processing.requiresExternalPower = request.requiresExternalPower
            native = processing
        }
        native.earliestBeginDate = request.earliestBeginDate
        try scheduler.submit(native)
    }

    func cancel(identifier: String) {
        scheduler.cancel(taskRequestWithIdentifier: MiniAppBackgroundTaskIdentifier.resolve(identifier))
    }
}

public extension MiniAppBackgroundTaskCenter {
    convenience init(scheduler: BGTaskScheduler = .shared) {
        self.init(scheduler: SystemBackgroundTaskScheduler(scheduler))
    }
}

public extension MiniAppSharedRefreshCenter {
    /// The journal URL is host-owned and must not be shared with another center
    /// or process writing the same file. Register handlers before reconciling.
    convenience init(identifier: String, journalURL: URL, scheduler: BGTaskScheduler = .shared) throws {
        try self.init(identifier: identifier, journal: FileSharedRefreshJournal(url: journalURL),
                      scheduler: SystemBackgroundTaskScheduler(scheduler))
    }
}
#endif
