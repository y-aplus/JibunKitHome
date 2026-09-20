import OSLog
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct FilePickerComparisonApp: App {
    var body: some Scene { WindowGroup { FilePickerComparisonView() } }
}

@MainActor
private struct FilePickerComparisonView: View {
    @State private var swiftUIImport = false
    @State private var nativeRequest: NativePickerRequest?
    @State private var status = "ready"

    var body: some View {
        VStack(spacing: 18) {
            Text("File picker comparison")
                .font(.headline)
            Text(status)
                .accessibilityIdentifier("picker.status")
                .textSelection(.enabled)
            Button("1. Export fixture with UIKit") { exportFixture() }
                .accessibilityIdentifier("picker.export-native")
            Button("2A. Import with SwiftUI") {
                record("swiftui.presented")
                swiftUIImport = true
            }
            .accessibilityIdentifier("picker.import-swiftui")
            Button("2B. Import with UIKit") {
                record("uikit.presented")
                nativeRequest = .open
            }
            .accessibilityIdentifier("picker.import-native")
            Button("2C. Import a copy with UIKit") {
                record("uikit-copy.presented")
                nativeRequest = .copy
            }
            .accessibilityIdentifier("picker.import-native-copy")
        }
        .padding()
        .fileImporter(isPresented: $swiftUIImport, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                record("swiftui.callback name=\(url.lastPathComponent)")
                inspect(url, route: "swiftui")
            case .failure(let error): record("swiftui.failure \(errorCode(error))")
            }
        }
        .sheet(item: $nativeRequest) { request in
            NativeDocumentPicker(request: request) { result in
                nativeRequest = nil
                switch result {
                case .success(let url):
                    record("\(request.route).callback name=\(url.lastPathComponent)")
                    if !request.isExport { inspect(url, route: request.route) }
                case .failure(let error): record("\(request.route).failure \(errorCode(error))")
                }
            }
        }
    }

    private func exportFixture() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("JibunKit-picker-comparison.json")
            try Self.fixtureData.write(to: url, options: .atomic)
            record("uikit.export.presented")
            nativeRequest = .export(url)
        } catch { record("fixture.write.failure \(errorCode(error))") }
    }

    private func inspect(_ url: URL, route: String) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data == Self.fixtureData else {
                record("\(route).content-mismatch bytes=\(data.count) scoped=\(access)")
                return
            }
            record("\(route).content-match bytes=\(data.count) scoped=\(access)")
        } catch { record("\(route).read.failure \(errorCode(error)) scoped=\(access)") }
    }

    private func record(_ message: String) {
        status = message
        Self.logger.info("\(message, privacy: .public)")
    }

    private func errorCode(_ error: Error) -> String {
        let value = error as NSError
        return "domain=\(value.domain) code=\(value.code)"
    }

    private static let logger = Logger(subsystem: "com.jibunkit.file-picker-comparison", category: "Picker")
    private static let fixtureData = Data(#"{"fixture":"jibunkit-file-picker","value":42}"#.utf8)
}

private struct NativePickerRequest: Identifiable {
    enum Kind { case open, copy, export(URL) }
    let id = UUID()
    let kind: Kind
    static var open: Self { .init(kind: .open) }
    static var copy: Self { .init(kind: .copy) }
    static func export(_ url: URL) -> Self { .init(kind: .export(url)) }
    var isExport: Bool { if case .export = kind { true } else { false } }
    var route: String {
        switch kind {
        case .open: "uikit-open"
        case .copy: "uikit-copy"
        case .export: "uikit-export"
        }
    }
}

@MainActor
private struct NativeDocumentPicker: UIViewControllerRepresentable {
    let request: NativePickerRequest
    let completion: @MainActor (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        switch request.kind {
        case .open:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: false)
        case .copy:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        case .export(let url):
            picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        }
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: @MainActor (Result<URL, Error>) -> Void
        init(completion: @escaping @MainActor (Result<URL, Error>) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                completion(.failure(CocoaError(.fileNoSuchFile)))
                return
            }
            completion(.success(url))
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        }
    }
}
