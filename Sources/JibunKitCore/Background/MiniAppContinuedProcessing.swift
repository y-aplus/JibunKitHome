import Foundation

public enum MiniAppContinuedProcessingStrategy: Equatable, Sendable { case queue, fail }

/// One user-initiated job. `baseIdentifier` is the Info.plist wildcard without
/// its trailing `.*`; `jobIdentifier` supplies the required unique suffix.
public struct MiniAppContinuedProcessingRequest: Equatable, Sendable {
    public let baseIdentifier: String
    public let jobIdentifier: UUID
    public let title: String
    public let subtitle: String
    public let strategy: MiniAppContinuedProcessingStrategy
    public var identifier: String { "\(baseIdentifier).\(jobIdentifier.uuidString.lowercased())" }
    public var permittedIdentifier: String { "\(baseIdentifier).*" }

    public init(baseIdentifier: String, jobIdentifier: UUID = UUID(), title: String,
                subtitle: String, strategy: MiniAppContinuedProcessingStrategy = .queue) {
        self.baseIdentifier = baseIdentifier
        self.jobIdentifier = jobIdentifier
        self.title = title
        self.subtitle = subtitle
        self.strategy = strategy
    }
}

public struct MiniAppContinuedProcessingReceipt: Equatable, Sendable {
    public let identifier: String
    public let jobIdentifier: UUID
}

@MainActor
protocol MiniAppContinuedProcessingNative: AnyObject {
    var expirationHandler: (@MainActor @Sendable () -> Void)? { get set }
    func updateProgress(completed: Int64, total: Int64)
    func updateTitle(_ title: String, subtitle: String)
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol MiniAppContinuedProcessingScheduling: AnyObject {
    func register(identifier: String,
                  launch: @escaping @MainActor (any MiniAppContinuedProcessingNative) -> Void) -> Bool
    func submit(_ request: MiniAppContinuedProcessingRequest) throws
    func cancel(identifier: String)
    func submitReportingResult(_ request: MiniAppContinuedProcessingRequest,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void)
}

extension MiniAppContinuedProcessingScheduling {
    func submitReportingResult(_ request: MiniAppContinuedProcessingRequest,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        do { try submit(request); completion(.success(())) }
        catch { completion(.failure(error)) }
    }
}

@MainActor
public final class MiniAppContinuedProcessingExecution {
    public let identifier: String
    public let jobIdentifier: UUID
    public private(set) var isExpired = false
    public private(set) var isCompleted = false
    public var onExpiration: (@MainActor () -> Void)? { didSet { deliverExpirationIfNeeded() } }
    private let native: any MiniAppContinuedProcessingNative
    private var deliveredExpiration = false
    private var releaseFromCenter: (@MainActor () -> Void)?

    fileprivate init(identifier: String, jobIdentifier: UUID,
                     native: any MiniAppContinuedProcessingNative,
                     releaseFromCenter: @escaping @MainActor () -> Void) {
        self.identifier = identifier
        self.jobIdentifier = jobIdentifier
        self.native = native
        self.releaseFromCenter = releaseFromCenter
        native.expirationHandler = { [weak self] in self?.expire() }
    }

    public func reportProgress(completed: Int64, total: Int64) {
        precondition(total > 0, "Continued-processing progress requires a positive total.")
        precondition((0...total).contains(completed), "Completed work must be within the total.")
        guard !isCompleted else { return }
        native.updateProgress(completed: completed, total: total)
    }

    public func updateTitle(_ title: String, subtitle: String) {
        guard !isCompleted else { return }
        native.updateTitle(title, subtitle: subtitle)
    }

    @discardableResult
    public func complete(success: Bool) -> Bool {
        guard !isCompleted else { return false }
        isCompleted = true
        native.expirationHandler = nil
        onExpiration = nil
        native.setTaskCompleted(success: success)
        let releaseFromCenter = releaseFromCenter
        self.releaseFromCenter = nil
        releaseFromCenter?()
        return true
    }

    private func expire() {
        guard !isCompleted, !isExpired else { return }
        isExpired = true
        deliverExpirationIfNeeded()
    }

    private func deliverExpirationIfNeeded() {
        guard isExpired, !isCompleted, !deliveredExpiration, let onExpiration else { return }
        deliveredExpiration = true
        onExpiration()
    }
}

/// Process-shared owner boundary. Continued-processing handlers are registered
/// dynamically for each fully composed identifier immediately before submission.
@MainActor
public final class MiniAppContinuedProcessingCenter {
    public enum Failure: Error, Equatable {
        case invalidBaseIdentifier, invalidPresentation, identifierAlreadyRegistered
        case nativeRegistrationRejected, identifierNotOwned
    }
    private struct Registration {
        let owner: String
        let jobIdentifier: UUID
        var awaitingLaunch = true
        var submissionResolved = false
        var cancelled = false
    }
    private let scheduler: any MiniAppContinuedProcessingScheduling
    private var registrations: [String: Registration] = [:]
    private var inFlight: [UUID: MiniAppContinuedProcessingExecution] = [:]

    init(scheduler: any MiniAppContinuedProcessingScheduling) { self.scheduler = scheduler }

    public func tasks(for context: MiniAppContext) -> MiniAppContinuedProcessingTasks {
        MiniAppContinuedProcessingTasks(owner: context.id.storageNamespace, center: self)
    }

    fileprivate func submit(owner: String, request: MiniAppContinuedProcessingRequest,
                            submissionResult: (@MainActor @Sendable (Result<Void, Error>) -> Void)? = nil,
                            handler: @escaping @MainActor (MiniAppContinuedProcessingExecution) -> Void)
        throws -> MiniAppContinuedProcessingReceipt {
        guard Self.isValidBaseIdentifier(request.baseIdentifier) else {
            throw Failure.invalidBaseIdentifier
        }
        guard !request.title.isEmpty, !request.subtitle.isEmpty else {
            throw Failure.invalidPresentation
        }
        let identifier = request.identifier
        guard registrations[identifier] == nil else { throw Failure.identifierAlreadyRegistered }
        let accepted = scheduler.register(identifier: identifier) { [weak self] native in
            guard let self else {
                native.setTaskCompleted(success: false)
                return
            }
            guard let registration = registrations[identifier], registration.owner == owner,
                  registration.awaitingLaunch else {
                native.setTaskCompleted(success: false)
                return
            }
            registrations[identifier]?.awaitingLaunch = false
            let executionID = UUID()
            let execution = MiniAppContinuedProcessingExecution(
                identifier: identifier, jobIdentifier: registration.jobIdentifier, native: native,
                releaseFromCenter: { [weak self] in self?.inFlight.removeValue(forKey: executionID) })
            inFlight[executionID] = execution
            handler(execution)
        }
        guard accepted else { throw Failure.nativeRegistrationRejected }
        registrations[identifier] = Registration(owner: owner, jobIdentifier: request.jobIdentifier)
        if let submissionResult {
            scheduler.submitReportingResult(request) { [weak self] result in
                guard let self, registrations[identifier]?.submissionResolved == false else { return }
                registrations[identifier]?.submissionResolved = true
                // The off-main native submission may finish after an earlier
                // cancellation. Remove that newly admitted request as well.
                if registrations[identifier]?.cancelled == true {
                    scheduler.cancel(identifier: identifier)
                }
                if case .failure = result { registrations[identifier]?.awaitingLaunch = false }
                submissionResult(result)
            }
        } else {
            do { try scheduler.submit(request) }
            catch {
                registrations[identifier]?.awaitingLaunch = false
                throw error
            }
        }
        return .init(identifier: identifier, jobIdentifier: request.jobIdentifier)
    }

    fileprivate func cancel(owner: String, identifier: String) throws {
        guard registrations[identifier]?.owner == owner else { throw Failure.identifierNotOwned }
        registrations[identifier]?.awaitingLaunch = false
        registrations[identifier]?.cancelled = true
        scheduler.cancel(identifier: identifier)
    }

    private static func isValidBaseIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, !identifier.hasSuffix("."), !identifier.contains("*"),
              identifier.split(separator: ".").count >= 3 else { return false }
        return identifier.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || CharacterSet(charactersIn: ".-").contains($0)
        }
    }
}

@MainActor
public final class MiniAppContinuedProcessingTasks {
    public let ownerIdentifier: String
    private let center: MiniAppContinuedProcessingCenter
    fileprivate init(owner: String, center: MiniAppContinuedProcessingCenter) {
        ownerIdentifier = owner; self.center = center
    }

    /// Dynamically registers the unique identifier and submits it. Call only
    /// from the foreground action which starts this exact job.
    @discardableResult
    public func submit(_ request: MiniAppContinuedProcessingRequest,
                       launch: @escaping @MainActor (MiniAppContinuedProcessingExecution) -> Void)
        throws -> MiniAppContinuedProcessingReceipt {
        try center.submit(owner: ownerIdentifier, request: request, handler: launch)
    }

    /// Reports asynchronous submission errors on SDK/OS 27+, keeping the receipt
    /// available for cancellation while the OS response is pending. Success is
    /// admission only; `launch` separately reports execution. SDK/OS 26 uses the
    /// legacy synchronous error coverage. The callback is delivered at most once.
    @discardableResult
    public func submitReportingResult(_ request: MiniAppContinuedProcessingRequest,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void,
        launch: @escaping @MainActor (MiniAppContinuedProcessingExecution) -> Void)
        throws -> MiniAppContinuedProcessingReceipt {
        try center.submit(owner: ownerIdentifier, request: request,
                          submissionResult: completion, handler: launch)
    }

    public func cancelPendingRequest(identifier: String) throws {
        try center.cancel(owner: ownerIdentifier, identifier: identifier)
    }
}
