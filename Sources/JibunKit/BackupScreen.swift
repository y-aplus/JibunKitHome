#if os(iOS)
import JibunKitCore
import JibunKitBackup
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct BackupScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exportIDs: Set<MiniAppID> = []
    @State private var restoreIDs: Set<MiniAppID> = []
    @State private var imported: ImportedMiniAppBackup?
    @State private var archive: BackupArchiveDocument?
    @State private var exportingArchive = false
    @State private var document: BackupDocument?
    @State private var exportFilename = "JibunKit-backup"
    @State private var importing = false
    @State private var exporting = false
    @State private var confirming = false
    @State private var pending: MiniAppRestorePlan?
    @State private var busy = false
    @State private var status: String?

    private let definitions: [MiniAppDefinition]
    private let lifecycleForDefinition: @MainActor (MiniAppDefinition) -> MiniAppRestoreLifecycle?

    init(definitions: [MiniAppDefinition], importedBackup: MiniAppBackup? = nil, importedArchive: ImportedMiniAppBackup? = nil,
         lifecycleForDefinition: @escaping @MainActor (MiniAppDefinition) -> MiniAppRestoreLifecycle? = { $0.effectiveRestoreLifecycle }) {
        self.definitions = definitions
        self.lifecycleForDefinition = lifecycleForDefinition
        _imported = State(initialValue: importedArchive ?? importedBackup.map { ImportedMiniAppBackup(legacy: $0) })
    }
    private var providers: [MiniAppBackupProvider] { definitions.compactMap(\.backup) }
    private var fileProviders: [MiniAppFileBackupProvider] { definitions.compactMap(\.fileBackup) }

    var body: some View {
        NavigationStack {
            Form {
                exportSection
                restoreSection

                if busy { ProgressView("処理中…") }
                if let status { Section { Text(status).accessibilityIdentifier("backup.status") } }
            }
            .disabled(busy)
            .navigationTitle("バックアップと復元")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .zip]) { result in
                #if DEBUG
                Self.importLogger.info("completion entered")
                #endif
                switch result {
                case .success(let url):
                    #if DEBUG
                    Self.importLogger.info("completion success extension=\(url.pathExtension, privacy: .public)")
                    #endif
                    load(url)
                case .failure(let error):
                    #if DEBUG
                    Self.importLogger.error("completion failure type=\(String(reflecting: type(of: error)), privacy: .public)")
                    #endif
                    status = "ファイルを読み込めませんでした。保存データは変更していません。"
                }
            }
            .onChange(of: importing) { _, presented in
                #if DEBUG
                Self.importLogger.info("presentation changed presented=\(presented, privacy: .public)")
                #endif
            }
            .background {
                Color.clear.fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: exportFilename, onCompletion: exportCompleted)
            }
            .onChange(of: exporting) { _, presented in
                if !presented { document = nil }
            }
            .background {
                Color.clear.fileExporter(isPresented: $exportingArchive, item: archive, contentTypes: [.zip],
                          defaultFilename: exportFilename, onCompletion: exportCompleted,
                          onCancellation: { archive = nil })
            }
            .alert("現在のデータを置き換えますか？", isPresented: $confirming) {
                Button("キャンセル", role: .cancel) { pending = nil }
                Button("置き換えて復元", role: .destructive) { restore() }
            } message: {
                Text((pending?.ids.map(title).joined(separator: "、") ?? "") +
                     "をバックアップの内容に戻します。実行中に失敗すると、一部だけ復元される場合があります。")
            }
        }
    }

    private var exportSection: some View {
        Section {
            ForEach(definitions) { definition in
                if definition.backup != nil || definition.fileBackup != nil {
                    Toggle(definition.title, isOn: selection(definition.id, in: $exportIDs))
                        .accessibilityIdentifier("backup.export.\(definition.id.rawValue)")
                } else {
                    LabeledContent(definition.title, value: "バックアップ未対応")
                }
            }
            Button("選択したアプリを書き出す") { exportSelected() }
                .disabled(exportIDs.isEmpty)
                .accessibilityIdentifier("backup.export")
        } header: { Text("バックアップ") }
        footer: { Text("選んだアプリのデータをファイルに保存します。ファイルは暗号化されません。") }
    }

    private var restoreSection: some View {
        Section {
            Button("バックアップを読み込む") {
                imported = nil
                restoreIDs = []
                pending = nil
                status = nil
                #if DEBUG
                Self.importLogger.info("presentation requested types=json,zip")
                #endif
                importing = true
            }
            .accessibilityIdentifier("backup.import")
            if let imported {
                LabeledContent("作成日時", value: imported.createdAt.formatted(date: .abbreviated, time: .shortened))
                ForEach(imported.entries, id: \.id) { entry in
                    restoreRow(entry)
                }
                Button("選択したアプリを復元") { prepareRestore(imported) }
                    .disabled(restoreIDs.isEmpty)
                    .accessibilityIdentifier("backup.restore")
            }
        } header: { Text("復元") }
        footer: { Text("選んだアプリの現在のデータを置き換えます。選ばなかったアプリは変更しません。") }
    }

    @ViewBuilder
    private func restoreRow(_ entry: ImportedMiniAppBackup.Entry) -> some View {
        if let definition = restoreDefinition(for: entry) {
            Toggle(definition.title, isOn: selection(entry.id, in: $restoreIDs))
                .accessibilityIdentifier("backup.restore.\(entry.id.rawValue)")
        } else {
            LabeledContent(title(entry.id), value: "この構成では復元できません")
        }
    }

    private func restoreDefinition(for entry: ImportedMiniAppBackup.Entry) -> MiniAppDefinition? {
        guard let definition = definitions.first(where: { $0.id == entry.id }) else { return nil }
        switch entry.storage {
        case .payload: return definition.backup == nil ? nil : definition
        case .files: return definition.fileBackup == nil ? nil : definition
        }
    }

    private func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success: status = "バックアップを書き出しました。"
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { status = "書き出せませんでした。" }
        }
        document = nil
        archive = nil
    }

    private func title(_ id: MiniAppID) -> String {
        definitions.first { $0.id == id }?.title ?? id.rawValue
    }

    private func selection(_ id: MiniAppID, in values: Binding<Set<MiniAppID>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { selected in
            if selected { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }

    private func exportSelected() {
        let ids = exportIDs
        let selected = providers.filter { ids.contains($0.id) }
        let selectedFiles = fileProviders.filter { ids.contains($0.id) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        exportFilename = "JibunKit-backup-\(formatter.string(from: Date()))"
        let archiveFilename = exportFilename + ".zip"
        busy = true
        status = nil
        Task {
            defer { busy = false }
            do {
                if selectedFiles.isEmpty {
                    let data = try await Task.detached {
                        var entries: [MiniAppBackupEntry] = []
                        for provider in selected { entries.append(try await provider.exportEntry()) }
                        return try MiniAppBackup(entries: entries).encoded()
                    }.value
                    document = BackupDocument(data: data)
                    exporting = true
                } else {
                    let file = try await Task.detached {
                        try await MiniAppBackupArchive.export(selected: ids, providers: selected, fileProviders: selectedFiles,
                                                              filename: archiveFilename)
                    }.value
                    archive = BackupArchiveDocument(file: file)
                    exportingArchive = true
                }
            } catch is MiniAppRestoreCoordinator.Conflict {
                status = "選択したアプリはデータを使用中です。処理が完了してからもう一度お試しください。ファイルは書き出していません。"
            } catch { status = "バックアップを作成できませんでした。ファイルは書き出していません。" }
        }
    }

    private func load(_ url: URL) {
        #if DEBUG
        Self.importLogger.info("load begin extension=\(url.pathExtension, privacy: .public)")
        #endif
        busy = true
        Task {
            defer { busy = false }
            do {
                imported = try await Task.detached {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try MiniAppBackupArchive.load(from: url)
                }.value
                #if DEBUG
                Self.importLogger.info("load success entries=\(imported?.entries.count ?? 0, privacy: .public)")
                #endif
                status = "復元するアプリを選んでください。まだ保存データは変更していません。"
            } catch {
                #if DEBUG
                Self.importLogger.error("load failure type=\(String(reflecting: type(of: error)), privacy: .public)")
                #endif
                status = "対応するバックアップを読み込めませんでした。保存データは変更していません。"
            }
        }
    }

    #if DEBUG
    private static let importLogger = Logger(subsystem: "com.jibunkit.app", category: "BackupImport")
    #endif

    private func prepareRestore(_ backup: ImportedMiniAppBackup) {
        let selected = restoreIDs
        let available = providers
        let availableFiles = fileProviders
        busy = true
        status = nil
        Task {
            defer { busy = false }
            do {
                pending = try await Task.detached {
                    try backup.prepareRestore(selected: selected, providers: available, fileProviders: availableFiles)
                }.value
                confirming = true
            } catch { status = "選んだデータを復元できません。内容や対応する版を確認してください。保存データは変更していません。" }
        }
    }

    private func restore() {
        guard let plan = pending else { return }
        pending = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                let lifecycles = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
                    lifecycleForDefinition(definition).map { (definition.id, $0) }
                })
                try await plan.apply(lifecycles: lifecycles)
                status = plan.ids.map(title).joined(separator: "、") + "を復元しました。"
                imported = nil
                restoreIDs = []
            } catch is CancellationError {
                status = "復元の開始前に中止しました。保存データは変更していません。"
            } catch let error as MiniAppRestoreCoordinator.Conflict {
                let names = error.owners.sorted { $0.rawValue < $1.rawValue }.map(title).joined(separator: "、")
                status = "\(names)はデータを使用中です。処理が完了してからもう一度選択してください。今回の復元では保存データを変更していません。"
            } catch let error as MiniAppRestoreFailure {
                let completed = error.completed.map(title).joined(separator: "、")
                let detail: String
                switch error.stage {
                case .cancelledBeforeStart:
                    detail = "このアプリの復元を始める前に中止しました。このアプリの保存データは変更していません。"
                case .stop:
                    detail = "実行中の処理を停止できなかったため、このアプリの保存データは復元していません。"
                case .stopAndRecovery:
                    detail = "保存データは復元していません。このアプリの停止に失敗し、利用できる状態へ戻すこともできませんでした。"
                case .apply:
                    detail = "保存データの復元に失敗しました。一部が変更されている可能性があります。"
                case .resume:
                    detail = "保存データは復元しましたが、このアプリの再開に失敗しました。"
                case .applyAndResume:
                    detail = "保存データの復元と、このアプリの再開に失敗しました。一部のデータが変更されている可能性があります。"
                }
                status = "復元を中断しました。完了済み: \(completed.isEmpty ? "なし" : completed)。\(title(error.failed)): \(detail) このアプリの状態を確認してください。後続のアプリは変更していません。"
            } catch { status = "復元に失敗しました。アプリの状態を確認してください。" }
        }
    }
}
#endif
