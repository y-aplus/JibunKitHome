import SwiftUI
import UIKit
import JibunKitCore

struct MiniAppIncomingExtensionPresentation: Equatable, Sendable {
    let navigationTitle: String
    let destinationTitle: String
    let emptyMessage: String
    let explanation: String
    let accessibilityPrefix: String

    static let share = Self(navigationTitle: "JibunKitへ共有", destinationTitle: "受信先を選択", emptyMessage: "この入力を受け取れるミニアプリがありません。JibunKitで受信先を登録・有効化してから共有してください。", explanation: "共有データを保存します。JibunKitを開き、「受信」から取り込めます。", accessibilityPrefix: "share")
    static let action = Self(navigationTitle: "JibunKitに保存", destinationTitle: "保存先を選択", emptyMessage: "この入力を保存できるミニアプリがありません。JibunKitで受信先を登録・有効化してからもう一度実行してください。", explanation: "入力のコピーをJibunKitの受信箱へ保存します。元の内容は変更せず、Action Extensionから出力項目は返しません。", accessibilityPrefix: "action")
}

@MainActor
class MiniAppIncomingExtensionViewController: UIViewController {
    var incomingPresentation: MiniAppIncomingExtensionPresentation { .share }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let context = extensionContext else { return }
        let providers = context.inputItems.compactMap { $0 as? NSExtensionItem }.flatMap { $0.attachments ?? [] }
        let controller = UIHostingController(rootView: MiniAppIncomingScreen(context: context, providers: providers, presentation: incomingPresentation))
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        controller.didMove(toParent: self)
    }
}

private struct MiniAppIncomingScreen: View {
    let context: NSExtensionContext
    let providers: [NSItemProvider]
    let presentation: MiniAppIncomingExtensionPresentation
    @State private var destinations: [MiniAppIncomingDestination] = []
    @State private var prepared: MiniAppPreparedIncoming?
    @State private var errorMessage: String?
    @State private var job: Task<Void, Never>?
    @State private var started = false
    @State private var ending = false
    @State private var finished = false

    var body: some View {
        NavigationStack {
            List {
                if job != nil { ProgressView("処理しています") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("\(presentation.accessibilityPrefix).error") }
                if let prepared {
                    Section("\(presentation.destinationTitle)（\(prepared.inputs.count)件）") {
                        ForEach(destinations) { destination in
                            Button(destination.title) { save(to: destination) }
                                .disabled(job != nil || ending)
                                .accessibilityIdentifier("\(presentation.accessibilityPrefix).destination.\(destination.id)")
                        }
                        if destinations.isEmpty { Text(presentation.emptyMessage) }
                    }
                    Text(presentation.explanation).font(.footnote)
                }
            }
            .navigationTitle(presentation.navigationTitle)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { cancel() }.disabled(ending) } }
        }
        .onAppear { load() }
        .onDisappear { job?.cancel() }
    }

    private func load() {
        guard !started else { return }
        started = true
        job = Task { @MainActor in
            defer { job = nil }
            var phase = "provider-load"
            do {
                let result = try await MiniAppIncomingProviderLoader.load(providers)
                var retained = false
                defer { if !retained { try? result.removeTemporaryFiles() } }
                phase = "open-inbox"
                let inbox = try MiniAppIncomingStore.shared()
                phase = "read-catalog"
                let catalog = try await Task.detached { try inbox.destinations() }.value
                try Task.checkCancellation()
                destinations = catalog.filter { destination in result.inputs.allSatisfy { destination.accepts($0.typeIdentifier) } }
                prepared = result
                retained = true
            } catch is CancellationError { }
            catch {
                #if DEBUG
                let types = providers.map { $0.registeredTypeIdentifiers.joined(separator: ",") }.joined(separator: " | ")
                errorMessage = "phase=\(phase) providers=\(providers.count) types=\(types) \(error.localizedDescription)"
                #else
                errorMessage = error.localizedDescription
                #endif
            }
        }
    }

    private func save(to destination: MiniAppIncomingDestination) {
        guard job == nil, let prepared, !ending else { return }
        errorMessage = nil
        job = Task { @MainActor in
            defer { job = nil }
            do {
                let inbox = try MiniAppIncomingStore.shared()
                let task = Task.detached { try inbox.enqueue(for: MiniAppID(destination.id), inputs: prepared.inputs) }
                _ = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                // enqueue rechecks owner admission and completes only after its durable rename.
                try? prepared.removeTemporaryFiles()
                self.prepared = nil
                ending = true
                finished = true
                // This is a save-only action: no transformed output item is produced.
                context.completeRequest(returningItems: [])
            } catch is CancellationError { }
            catch { errorMessage = "保存できませんでした。\(error.localizedDescription)" }
        }
    }

    private func cancel() {
        guard !ending else { return }
        ending = true
        let pending = job
        pending?.cancel()
        Task { @MainActor in
            // Join callback-owned file work before releasing temporary inputs.
            await pending?.value
            guard !finished else { return }
            if let prepared { try? prepared.removeTemporaryFiles() }
            self.prepared = nil
            finished = true
            context.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
    }
}
