#if os(iOS)
import Foundation
import JibunKitCore
import SwiftUI
import UIKit

/// Diagnostic-only fixed event labels; never persist URLs, payloads or NSError userInfo.
/// A callback's app state is observed when received; a process ID alone is not
/// proof that the OS launched the app because of that callback.
@MainActor
final class P2BackgroundObservationLog: ObservableObject {
    struct Entry: Codable, Equatable {
        let receivedAt: Date
        let process: UUID
        let appState: String
        let event: String
    }
    static let processID = UUID()
    static let filename = "p2-background-observations.json"
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var error: String?
    private var files: MiniAppFiles?
    private var writable = false
    private let process: UUID
    private let appState: @MainActor () -> String

    init(owner: MiniAppID, files: MiniAppFiles? = nil, persist: Bool = true,
         process: UUID = P2BackgroundObservationLog.processID,
         appState: @escaping @MainActor () -> String = {
             switch UIApplication.shared.applicationState {
             case .active: return "active"
             case .inactive: return "inactive"
             case .background: return "background"
             @unknown default: return "unknown"
             }
         }) {
        self.process = process
        self.appState = appState
        guard persist else { return }
        do {
            let storage = try files ?? MiniAppFiles.shared(context: MiniAppContext(id: owner))
            self.files = storage
            let url = try storage.fileURL(named: Self.filename)
            if FileManager.default.fileExists(atPath: url.path) {
                entries = Array(try JSONDecoder().decode([Entry].self, from: storage.read(named: Self.filename)).suffix(64))
            }
            writable = true
        } catch {
            self.error = "記録読込失敗（既存ファイルを保持）: \(error)"
        }
    }

    func record(_ event: String, at date: Date = Date()) {
        entries.append(.init(receivedAt: date, process: process, appState: appState(), event: event))
        entries = Array(entries.suffix(64))
        guard writable, let files else { return }
        do {
            try files.write(JSONEncoder().encode(entries), named: Self.filename)
            error = nil
        } catch { self.error = "記録保存失敗: \(error)" }
    }
}

struct P2BackgroundObservationView: View {
    @ObservedObject var log: P2BackgroundObservationLog
    var body: some View {
        DisclosureGroup("背景配送記録（再起動後も保持・最新64件）") {
            if let error = log.error { Text(error) }
            Text(log.entries.map {
                "\($0.receivedAt.ISO8601Format()) [\($0.appState)] 起動\($0.process.uuidString.prefix(8)) \($0.event)"
            }.joined(separator: "\n"))
                .font(.caption).textSelection(.enabled)
        }
    }
}
#endif
