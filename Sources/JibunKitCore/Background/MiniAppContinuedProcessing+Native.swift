#if canImport(BackgroundTasks) && os(iOS)
@preconcurrency import BackgroundTasks
import Foundation

@available(iOS 26.0, *)
@MainActor
private final class SystemContinuedProcessingTask: MiniAppContinuedProcessingNative {
    private let task: BGContinuedProcessingTask
    private var bridgedExpirationHandler: (@MainActor @Sendable () -> Void)?

    init(_ task: BGContinuedProcessingTask) { self.task = task }

    var expirationHandler: (@MainActor @Sendable () -> Void)? {
        get { bridgedExpirationHandler }
        set {
            bridgedExpirationHandler = newValue
            task.expirationHandler = newValue.map { handler in
                { MiniAppBackgroundTaskActorBridge.deliverExpiration(handler) }
            }
        }
    }

    func updateProgress(completed: Int64, total: Int64) {
        task.progress.totalUnitCount = total
        task.progress.completedUnitCount = completed
    }

    func updateTitle(_ title: String, subtitle: String) {
        task.updateTitle(title, subtitle: subtitle)
    }

    func setTaskCompleted(success: Bool) { task.setTaskCompleted(success: success) }
}

@available(iOS 26.0, *)
@MainActor
private final class SystemContinuedProcessingScheduler: MiniAppContinuedProcessingScheduling {
    private let scheduler: BGTaskScheduler

    init(_ scheduler: BGTaskScheduler) { self.scheduler = scheduler }

    func register(
        identifier: String,
        launch: @escaping @MainActor (any MiniAppContinuedProcessingNative) -> Void
    ) -> Bool {
        scheduler.register(forTaskWithIdentifier: MiniAppBackgroundTaskIdentifier.resolve(identifier), using: .main) { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in launch(SystemContinuedProcessingTask(continued)) }
        }
    }

    func submit(_ request: MiniAppContinuedProcessingRequest) throws {
        let native = BGContinuedProcessingTaskRequest(
            identifier: MiniAppBackgroundTaskIdentifier.resolve(request.identifier),
            title: request.title,
            subtitle: request.subtitle
        )
        native.strategy = request.strategy == .queue ? .queue : .fail
        try scheduler.submit(native)
    }

    func submitReportingResult(_ request: MiniAppContinuedProcessingRequest,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        // Xcode 27 supplies Swift 6.4 and the new declaration; retain SDK 26 builds.
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let identifier = MiniAppBackgroundTaskIdentifier.resolve(request.identifier)
            let systemScheduler = scheduler
            // Apple requires this API off the main thread. Construct the request
            // on that queue and return its result to the owner's MainActor.
            DispatchQueue.global(qos: .userInitiated).async {
                let native = BGContinuedProcessingTaskRequest(identifier: identifier,
                    title: request.title, subtitle: request.subtitle)
                native.strategy = request.strategy == .queue ? .queue : .fail
                systemScheduler.submitTaskRequest(native) { error in
                    Task { @MainActor in
                        if let error { completion(.failure(error)) }
                        else { completion(.success(())) }
                    }
                }
            }
            return
        }
        #endif
        do { try submit(request); completion(.success(())) }
        catch { completion(.failure(error)) }
    }

    func cancel(identifier: String) {
        scheduler.cancel(taskRequestWithIdentifier: MiniAppBackgroundTaskIdentifier.resolve(identifier))
    }
}

@available(iOS 26.0, *)
public extension MiniAppContinuedProcessingCenter {
    convenience init(scheduler: BGTaskScheduler = .shared) {
        self.init(scheduler: SystemContinuedProcessingScheduler(scheduler))
    }
}
#endif
