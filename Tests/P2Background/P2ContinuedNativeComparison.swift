#if os(iOS)
@preconcurrency import BackgroundTasks
import Foundation
import SwiftUI
import UIKit

/// A diagnostic control: directly calls Apple's scheduler, without JibunKit's
/// continued center, identifier resolver, execution adapter or worker path.
@MainActor
final class P2ContinuedNativeComparison: ObservableObject {
    typealias Register = @MainActor (String, @escaping @MainActor () -> Bool) -> Bool
    typealias Submit = @MainActor (String, @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) -> Void
    @Published private(set) var events: [String] = []
    private(set) var pendingIdentifier: String?
    private let owner: String
    private let register: Register
    private let submit: Submit
    private let cancelRequest: @MainActor (String) -> Void

    init(owner: String, register: @escaping Register = P2ContinuedNativeComparison.systemRegister,
         submit: @escaping Submit = P2ContinuedNativeComparison.systemSubmit,
         cancel: @escaping @MainActor (String) -> Void = { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: $0) }) {
        self.owner = owner; self.register = register; self.submit = submit; self.cancelRequest = cancel
    }

    static func identifier(owner: String, info: [String: Any], job: UUID = UUID()) -> String? {
        guard ["p2-background-a", "p2-background-b"].contains(owner),
              let bundle = info["CFBundleIdentifier"] as? String, !bundle.isEmpty,
              let permitted = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] else { return nil }
        let base = bundle + "." + owner + ".export"
        guard permitted.contains(base + ".*") else { return nil }
        return base + "." + job.uuidString.lowercased()
    }

    func start(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        guard pendingIdentifier == nil else { record("直接比較: 既存要求あり"); return }
        guard let identifier = Self.identifier(owner: owner, info: info) else {
            record("直接比較: 実bundle prefixと許可wildcardが不一致（未送信）")
            return
        }
        record("直接比較: 実bundle prefix/許可wildcard一致")
        record("appState=\(UIApplication.shared.applicationState.rawValue) refresh=\(UIApplication.shared.backgroundRefreshStatus.rawValue) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
        pendingIdentifier = identifier
        let accepted = register(identifier) { [weak self] in
            guard let self else { return false }
            record("OS直接callback")
            guard pendingIdentifier == identifier else { record("直接比較: 遅着を拒否"); return false }
            pendingIdentifier = nil
            record("直接比較: OS開始を確認・試験仕事を即完了")
            return true
        }
        guard accepted else {
            pendingIdentifier = nil; record("直接比較: native登録拒否"); return
        }
        record("直接比較: native登録成功・即時受付要求")
        submit(identifier) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: record("直接比較: OS受付応答成功")
            case .failure(let error):
                let native = error as NSError
                record("直接比較: \(native.domain) code=\(native.code) \(native.localizedDescription) \(native.userInfo[NSDebugDescriptionErrorKey] ?? "")")
            }
            if pendingIdentifier != identifier {
                // Cancellation/another job or an already-completed launch must
                // not be revived by a delayed admission response.
                cancelRequest(identifier)
            } else if case .failure = result { pendingIdentifier = nil }
        }
    }

    func cancel() {
        guard let identifier = pendingIdentifier else { return }
        pendingIdentifier = nil
        cancelRequest(identifier)
        record("直接比較: 取消")
    }

    private func record(_ value: String) {
        events.append("\(Date().ISO8601Format()) \(value)")
        if events.count > 32 { events.removeFirst(events.count - 32) }
    }

    private static func systemRegister(_ identifier: String, launch: @escaping @MainActor () -> Bool) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard task is BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                task.setTaskCompleted(success: launch())
            }
        }
    }

    private static func systemSubmit(_ identifier: String,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            DispatchQueue.global(qos: .userInitiated).async {
                let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                    title: "Native comparison", subtitle: "Admission control")
                request.strategy = .fail
                BGTaskScheduler.shared.submitTaskRequest(request) { error in
                    Task { @MainActor in
                        if let error { completion(.failure(error)) }
                        else { completion(.success(())) }
                    }
                }
            }
            return
        }
        #endif
        completion(.failure(NSError(domain: "P2NativeComparisonRequiresSDKAndOS27", code: 1)))
    }
}

struct P2ContinuedNativeComparisonView: View {
    @ObservedObject var comparison: P2ContinuedNativeComparison
    let start: @MainActor () -> Void
    var body: some View {
        Section("OS直接比較") {
            Button("OS直接比較を一度実行") { start() }
            Text("共通処理を通さず要求し、OS開始通知が届けば試験仕事を即完了します。")
            Text(comparison.events.joined(separator: "\n")).font(.caption).textSelection(.enabled)
        }
    }
}
#endif
