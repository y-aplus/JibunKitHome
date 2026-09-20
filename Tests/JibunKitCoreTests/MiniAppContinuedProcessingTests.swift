import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppContinuedProcessingTests: XCTestCase {
    func testSubmissionRegistersUniqueComposedIdentifierAndPreservesPresentation() throws {
        let scheduler = ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let tasks = center.tasks(for: context("continued-a"))
        let job = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let request = MiniAppContinuedProcessingRequest(
            baseIdentifier: "com.example.app.export", jobIdentifier: job,
            title: "Export", subtitle: "Preparing", strategy: .fail)

        let receipt = try tasks.submit(request) { _ in }

        XCTAssertEqual(request.permittedIdentifier, "com.example.app.export.*")
        XCTAssertEqual(receipt.identifier, "com.example.app.export.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertEqual(scheduler.registrationAttempts, [receipt.identifier])
        XCTAssertEqual(scheduler.submissions, [request])
    }

    func testTwoOwnersReceiveOnlyTheirUniqueLaunchAndProgress() throws {
        let scheduler = ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let a = center.tasks(for: context("continued-a"))
        let b = center.tasks(for: context("continued-b"))
        var launches: [String] = []
        let aReceipt = try a.submit(request("com.example.app.a")) { execution in
            launches.append("a")
            execution.reportProgress(completed: 2, total: 5)
            execution.updateTitle("Export A", subtitle: "2 of 5")
        }
        let bReceipt = try b.submit(request("com.example.app.b")) { execution in
            launches.append("b")
            execution.reportProgress(completed: 1, total: 3)
        }

        let nativeB = scheduler.launch(bReceipt.identifier)
        let nativeA = scheduler.launch(aReceipt.identifier)
        XCTAssertEqual(launches, ["b", "a"])
        XCTAssertEqual(nativeB.progress, [.init(completed: 1, total: 3)])
        XCTAssertEqual(nativeA.titles, [.init(title: "Export A", subtitle: "2 of 5")])
    }

    func testExpirationAndCompletionAreDeliveredOnce() throws {
        let scheduler = ContinuedSchedulerSpy()
        let tasks = MiniAppContinuedProcessingCenter(scheduler: scheduler).tasks(for: context("continued-a"))
        var expirationCount = 0
        var launched: MiniAppContinuedProcessingExecution?
        let receipt = try tasks.submit(request("com.example.app.export")) { execution in
            launched = execution
            execution.onExpiration = { expirationCount += 1 }
        }
        let native = scheduler.launch(receipt.identifier)
        native.expire(); native.expire()
        XCTAssertEqual(expirationCount, 1)
        XCTAssertTrue(launched?.complete(success: false) == true)
        XCTAssertTrue(launched?.complete(success: true) == false)
        XCTAssertEqual(native.completions, [false])
    }

    func testOwnerCancellationAndDuplicateJobRemainScoped() throws {
        let scheduler = ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let a = center.tasks(for: context("continued-a"))
        let b = center.tasks(for: context("continued-b"))
        let request = request("com.example.app.export")
        let receipt = try a.submit(request) { _ in }

        XCTAssertThrowsError(try a.submit(request) { _ in }) {
            XCTAssertEqual($0 as? MiniAppContinuedProcessingCenter.Failure, .identifierAlreadyRegistered)
        }
        XCTAssertThrowsError(try b.cancelPendingRequest(identifier: receipt.identifier)) {
            XCTAssertEqual($0 as? MiniAppContinuedProcessingCenter.Failure, .identifierNotOwned)
        }
        try a.cancelPendingRequest(identifier: receipt.identifier)
        XCTAssertEqual(scheduler.cancellations, [receipt.identifier])
    }

    func testCancelledAndDuplicateLaunchCannotRestartWorkOrAffectOtherOwner() throws {
        let scheduler = ContinuedSchedulerSpy()
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let a = center.tasks(for: context("continued-a"))
        let b = center.tasks(for: context("continued-b"))
        var aCalls = 0
        var bCalls = 0
        var bExecution: MiniAppContinuedProcessingExecution?
        let cancelled = try a.submit(request("com.example.app.a")) { _ in aCalls += 1 }
        let other = try b.submit(request("com.example.app.b")) { bCalls += 1; bExecution = $0 }
        try a.cancelPendingRequest(identifier: cancelled.identifier)
        let late = scheduler.launch(cancelled.identifier)
        XCTAssertEqual(late.completions, [false])
        XCTAssertEqual(aCalls, 0)
        let replacement = try a.submit(request("com.example.app.a")) { execution in
            aCalls += 1; execution.complete(success: true)
        }
        let current = scheduler.launch(replacement.identifier)
        XCTAssertEqual(current.completions, [true])
        let duplicate = scheduler.launch(replacement.identifier)
        XCTAssertEqual(duplicate.completions, [false])
        XCTAssertEqual(aCalls, 1)
        let nativeB = scheduler.launch(other.identifier)
        XCTAssertEqual(bCalls, 1)
        try a.cancelPendingRequest(identifier: cancelled.identifier)
        XCTAssertEqual(nativeB.completions, [])
        bExecution?.complete(success: true)
        XCTAssertEqual(nativeB.completions, [true])
    }

    func testRejectedSubmissionClosesLaunchAdmissionButNewJobCanRun() throws {
        let scheduler = ContinuedSchedulerSpy()
        let tasks = MiniAppContinuedProcessingCenter(scheduler: scheduler).tasks(for: context("continued-a"))
        scheduler.submissionError = NSError(domain: "BGTaskSchedulerErrorDomain", code: 4)
        let rejected = request("com.example.app.a")
        XCTAssertThrowsError(try tasks.submit(rejected) { _ in XCTFail("Rejected job started") })
        XCTAssertEqual(scheduler.launch(rejected.identifier).completions, [false])
        scheduler.submissionError = nil
        let retry = try tasks.submit(request("com.example.app.a")) { $0.complete(success: true) }
        XCTAssertEqual(scheduler.launch(retry.identifier).completions, [true])
    }

    func testAsynchronousSubmissionFailureRejectsLateLaunchAndKeepsOtherOwner() throws {
        let scheduler = ContinuedSchedulerSpy()
        scheduler.deferSubmissionResult = true
        let center = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        let a = center.tasks(for: context("async-a")), b = center.tasks(for: context("async-b"))
        let results = ContinuedSubmissionResults()
        let aReceipt = try a.submitReportingResult(request("com.example.app.a"), completion: { results.record($0) }) {
            _ in XCTFail("Failed submission launched")
        }
        let bReceipt = try b.submitReportingResult(request("com.example.app.b"), completion: { results.record($0) }) {
            $0.complete(success: true)
        }
        XCTAssertEqual(results.count, 0)
        let error = NSError(domain: "BGTaskSchedulerErrorDomain", code: 4)
        scheduler.completions[aReceipt.identifier]?(.failure(error))
        scheduler.completions[aReceipt.identifier]?(.success(()))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.lastError?.domain, error.domain)
        XCTAssertEqual(results.lastError?.code, 4)
        XCTAssertEqual(scheduler.launch(aReceipt.identifier).completions, [false])
        scheduler.completions[bReceipt.identifier]?(.success(()))
        XCTAssertEqual(scheduler.launch(bReceipt.identifier).completions, [true])
        XCTAssertEqual(results.count, 2)
    }

    func testCancellationBeforeSubmissionResponseRemovesLateAcceptedRequest() throws {
        let scheduler = ContinuedSchedulerSpy()
        scheduler.deferSubmissionResult = true
        let tasks = MiniAppContinuedProcessingCenter(scheduler: scheduler).tasks(for: context("async-cancel"))
        let results = ContinuedSubmissionResults()
        let receipt = try tasks.submitReportingResult(request("com.example.app.a"), completion: { results.record($0) }) {
            _ in XCTFail("Cancelled submission launched")
        }
        try tasks.cancelPendingRequest(identifier: receipt.identifier)
        scheduler.completions[receipt.identifier]?(.success(()))
        scheduler.completions[receipt.identifier]?(.success(()))
        XCTAssertEqual(scheduler.cancellations, [receipt.identifier, receipt.identifier])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(scheduler.launch(receipt.identifier).completions, [false])
    }

    func testRejectedRegistrationDoesNotSubmitAndInvalidInputsFailEarly() throws {
        let scheduler = ContinuedSchedulerSpy(rejectNextRegistration: true)
        let tasks = MiniAppContinuedProcessingCenter(scheduler: scheduler).tasks(for: context("continued-a"))
        XCTAssertThrowsError(try tasks.submit(request("com.example.app.export")) { _ in }) {
            XCTAssertEqual($0 as? MiniAppContinuedProcessingCenter.Failure, .nativeRegistrationRejected)
        }
        XCTAssertTrue(scheduler.submissions.isEmpty)
        XCTAssertThrowsError(try tasks.submit(.init(
            baseIdentifier: "com.example.app.*", title: "Export", subtitle: "Preparing"
        )) { _ in }) {
            XCTAssertEqual($0 as? MiniAppContinuedProcessingCenter.Failure, .invalidBaseIdentifier)
        }
    }

    func testCenterReleaseFailsLateNativeLaunchInsteadOfLeavingItOpen() throws {
        let scheduler = ContinuedSchedulerSpy()
        var center: MiniAppContinuedProcessingCenter? = MiniAppContinuedProcessingCenter(scheduler: scheduler)
        var tasks: MiniAppContinuedProcessingTasks? = center!.tasks(for: context("continued-a"))
        let receipt = try tasks!.submit(request("com.example.app.export")) { _ in
            XCTFail("Released center must reject launch")
        }
        center = nil
        tasks = nil
        let native = scheduler.launch(receipt.identifier)
        XCTAssertEqual(native.completions, [false])
    }

    private func request(_ base: String) -> MiniAppContinuedProcessingRequest {
        .init(baseIdentifier: base, title: "Export", subtitle: "Preparing")
    }
    private func context(_ id: String) -> MiniAppContext { MiniAppContext(id: MiniAppID(id)) }
}

@MainActor
private final class ContinuedSchedulerSpy: MiniAppContinuedProcessingScheduling {
    var registrationAttempts: [String] = []
    var registrations: [String: @MainActor (any MiniAppContinuedProcessingNative) -> Void] = [:]
    var submissions: [MiniAppContinuedProcessingRequest] = []
    var cancellations: [String] = []
    var submissionError: Error?
    var deferSubmissionResult = false
    var completions: [String: @MainActor @Sendable (Result<Void, Error>) -> Void] = [:]
    var rejectNextRegistration: Bool
    init(rejectNextRegistration: Bool = false) { self.rejectNextRegistration = rejectNextRegistration }
    func register(identifier: String,
                  launch: @escaping @MainActor (any MiniAppContinuedProcessingNative) -> Void) -> Bool {
        registrationAttempts.append(identifier)
        if rejectNextRegistration { rejectNextRegistration = false; return false }
        registrations[identifier] = launch
        return true
    }
    func submit(_ request: MiniAppContinuedProcessingRequest) throws {
        submissions.append(request)
        if let submissionError { throw submissionError }
    }
    func submitReportingResult(_ request: MiniAppContinuedProcessingRequest,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        if deferSubmissionResult { submissions.append(request); completions[request.identifier] = completion }
        else {
            do { try submit(request); completion(.success(())) }
            catch { completion(.failure(error)) }
        }
    }
    func cancel(identifier: String) { cancellations.append(identifier) }
    func launch(_ identifier: String) -> ContinuedNativeSpy {
        let native = ContinuedNativeSpy(); registrations[identifier]?(native); return native
    }
}

@MainActor
private final class ContinuedNativeSpy: MiniAppContinuedProcessingNative {
    struct ProgressUpdate: Equatable { let completed: Int64; let total: Int64 }
    struct TitleUpdate: Equatable { let title: String; let subtitle: String }
    var expirationHandler: (@MainActor @Sendable () -> Void)?
    var progress: [ProgressUpdate] = []
    var titles: [TitleUpdate] = []
    var completions: [Bool] = []
    func updateProgress(completed: Int64, total: Int64) { progress.append(.init(completed: completed, total: total)) }
    func updateTitle(_ title: String, subtitle: String) { titles.append(.init(title: title, subtitle: subtitle)) }
    func setTaskCompleted(success: Bool) { completions.append(success) }
    func expire() { let callback = expirationHandler; expirationHandler = nil; callback?() }
}

@MainActor
private final class ContinuedSubmissionResults {
    var count = 0
    var lastError: NSError?
    func record(_ result: Result<Void, Error>) {
        count += 1
        if case .failure(let error) = result { lastError = error as NSError }
    }
}
