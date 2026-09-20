#if os(iOS)
import Combine
import Foundation
import JibunKitCore

@MainActor
final class P2BackgroundTransferEvidence: ObservableObject {
    struct Record: Codable, Equatable {
        let run: UUID
        let owner: String
        let sessionIdentifier: String
        let originProcess: UUID
        let originTaskIdentifier: Int
        let taskDescription: String
        let submittedAt: Date
        var hostCallbackProcess: UUID?
        var ownerReconnectedProcess: UUID?
        var delegateProcess: UUID?
        var delegateTaskIdentifier: Int?
        var savedSize: Int?
        var savedSHA256: String?
        var savedProcess: UUID?
        var taskCompletionObserved = false
        var taskCompletedWithoutError = false
        var finishedEventsProcess: UUID?
        var hostCompletionReturnedProcess: UUID?
        var terminationRequestedProcess: UUID?
        var rejection: String?

        var blocksNewRun: Bool {
            !taskCompletionObserved || (hostCallbackProcess != nil && hostCompletionReturnedProcess == nil)
        }

        var satisfiesColdChain: Bool {
            guard rejection == nil,
                  let callback = hostCallbackProcess,
                  callback != originProcess,
                  terminationRequestedProcess == originProcess,
                  ownerReconnectedProcess == callback,
                  delegateProcess == callback,
                  delegateTaskIdentifier == originTaskIdentifier,
                  savedProcess == callback,
                  savedSize != nil,
                  savedSHA256 != nil,
                  taskCompletionObserved,
                  taskCompletedWithoutError,
                  finishedEventsProcess == callback,
                  hostCompletionReturnedProcess == callback else { return false }
            return true
        }
    }

    struct PendingTask: Equatable {
        let identifier: Int
        let taskDescription: String?
    }

    static let filename = "p2-background-transfer-evidence.json"
    static let taskDescriptionPrefix = "jibunkit-p2-background:"

    @Published private(set) var record: Record?
    @Published private(set) var error: String?
    private let files: MiniAppFiles
    private let owner: MiniAppID
    private let process: UUID
    private let writeData: @MainActor (Data, String) throws -> Void
    private var persistedRecord: Record?
    private var loadFailed = false

    init(owner: MiniAppID, files: MiniAppFiles,
         process: UUID = P2BackgroundObservationLog.processID,
         write: (@MainActor (Data, String) throws -> Void)? = nil) {
        self.owner = owner
        self.files = files
        self.process = process
        self.writeData = write ?? { data, name in try files.write(data, named: name) }
        do {
            let url = try files.fileURL(named: Self.filename)
            if FileManager.default.fileExists(atPath: url.path) {
                let decoded = try JSONDecoder().decode(Record.self, from: files.read(named: Self.filename))
                record = decoded
                persistedRecord = decoded
            }
        } catch {
            loadFailed = true
            self.error = "転送証拠読込失敗（既存ファイルを保持）: \(error)"
        }
    }

    var summary: String {
        guard let record else { return error ?? "cold復元証拠: 未開始" }
        let run = record.run.uuidString.prefix(8)
        let isDurable = persistedRecord == record && diskRecord() == record
        if record.satisfiesColdChain, isDurable {
            return "cold復元chain: 成立（OSの起動契機は未判定） run=\(run) task=\(record.originTaskIdentifier) size=\(record.savedSize!) sha256=\(record.savedSHA256!)"
        }
        if let rejection = record.rejection { return "cold復元chain: 不成立 run=\(run) 理由=\(rejection)" }
        if !isDurable { return "cold復元chain: 不成立 run=\(run) 理由=証拠未永続化" }
        return "cold復元chain: 未成立（OSの起動契機は未判定） run=\(run) origin=\(record.originProcess.uuidString.prefix(8))"
    }

    func canBegin() -> Bool { !loadFailed && record?.blocksNewRun != true }

    func begin(sessionIdentifier: String, taskIdentifier: Int, run: UUID) throws -> String {
        guard canBegin() else { throw loadFailed ? Failure.unreadableEvidence : Failure.pendingRun }
        let oldRecord = record
        let oldPersisted = persistedRecord
        let description = Self.taskDescriptionPrefix + run.uuidString.lowercased()
        record = Record(run: run, owner: owner.rawValue, sessionIdentifier: sessionIdentifier,
                        originProcess: process, originTaskIdentifier: taskIdentifier,
                        taskDescription: description, submittedAt: Date())
        do { try persistCurrent() }
        catch {
            record = oldRecord
            persistedRecord = oldPersisted
            self.error = "転送証拠保存失敗: \(error)"
            throw error
        }
        return description
    }

    var currentRun: UUID? { record?.run }

    func noteHostCallback(sessionIdentifier: String) -> UUID? {
        guard record?.blocksNewRun == true, matches(sessionIdentifier: sessionIdentifier) else { return nil }
        guard mutateAndPersist({ $0.hostCallbackProcess = process }) else { return nil }
        return record?.run
    }

    func noteOwnerReconnected(run: UUID?) {
        guard record?.run == run, record?.rejection == nil, record?.hostCallbackProcess == process else { return }
        mutateAndPersist { $0.ownerReconnectedProcess = process }
    }

    func noteSaved(taskDescription: String?, taskIdentifier: Int, size: Int, sha256: String) {
        guard matches(taskDescription: taskDescription, taskIdentifier: taskIdentifier) else { return }
        mutateAndPersist {
            $0.delegateProcess = process
            $0.delegateTaskIdentifier = taskIdentifier
            $0.savedSize = size
            $0.savedSHA256 = sha256
            $0.savedProcess = process
        }
    }

    func noteTaskCompletion(taskDescription: String?, taskIdentifier: Int, error: Error?) {
        guard matches(taskDescription: taskDescription, taskIdentifier: taskIdentifier) else { return }
        mutateAndPersist {
            $0.delegateProcess = process
            $0.delegateTaskIdentifier = taskIdentifier
            $0.taskCompletionObserved = true
            $0.taskCompletedWithoutError = error == nil
            if let error { $0.rejection = "task失敗: \(type(of: error))" }
        }
    }

    func noteFinishedEvents(run: UUID?) {
        guard record?.run == run else { return }
        mutateAndPersist { $0.finishedEventsProcess = process }
    }

    func noteHostCompletionReturned(run: UUID?) {
        guard record?.run == run else { return }
        mutateAndPersist { $0.hostCompletionReturnedProcess = process }
    }

    func canTerminateForDiagnostic(pendingTasks: [PendingTask]) -> Bool {
        guard let record, record.blocksNewRun,
              record.originProcess == process,
              pendingTasks.contains(.init(identifier: record.originTaskIdentifier,
                                          taskDescription: record.taskDescription)) else { return false }
        return diskRecord() == record
    }

    func noteTerminationRequested() -> Bool {
        guard record?.originProcess == process else { return false }
        let saved = mutateAndPersist { $0.terminationRequestedProcess = process }
        return saved && record != nil && persistedRecord == record && diskRecord() == record
    }

    func canExitAfterTerminationMarker(pendingTasks: [PendingTask]) -> Bool {
        guard record?.terminationRequestedProcess == process else { return false }
        return canTerminateForDiagnostic(pendingTasks: pendingTasks)
    }

    private func matches(sessionIdentifier: String) -> Bool {
        guard let record else { return false }
        guard record.owner == owner.rawValue, record.sessionIdentifier == sessionIdentifier else {
            reject("owner/session混在"); return false
        }
        return true
    }

    private func matches(taskDescription: String?, taskIdentifier: Int) -> Bool {
        guard let record else { return false }
        guard record.owner == owner.rawValue,
              taskDescription == record.taskDescription,
              taskIdentifier == record.originTaskIdentifier else {
            reject("run/owner/task混在"); return false
        }
        return true
    }

    private func reject(_ reason: String) { mutateAndPersist { $0.rejection = reason } }

    @discardableResult
    private func mutateAndPersist(_ mutation: (inout Record) -> Void) -> Bool {
        guard var next = record else { return false }
        mutation(&next)
        record = next
        do { try persistCurrent(); error = nil; return true }
        catch { self.error = "転送証拠保存失敗: \(error)"; return false }
    }

    private func persistCurrent() throws {
        guard let record else { return }
        try writeData(JSONEncoder().encode(record), Self.filename)
        persistedRecord = record
    }

    private func diskRecord() -> Record? {
        (try? files.read(named: Self.filename)).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    enum Failure: Error { case pendingRun, unreadableEvidence }
}
#endif
