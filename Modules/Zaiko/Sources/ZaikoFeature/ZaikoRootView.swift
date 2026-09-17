#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct ZaikoRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store: ZaikoStore
    @State private var itemEditorContext: ItemEditorContext?
    @State private var restockItem: InventoryItem?
    @State private var pendingDeleteItem: InventoryItem?
    @State private var isSettingsPresented = false
    @State private var backupError: String?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument = InventoryBackupDocument(text: "")
    @State private var pendingSettingsAction: SettingsAction?

    private enum SettingsAction {
        case enableNotifications, requestPermission
    }

    /// The host integration owns the store instance (it also serves backup and
    /// removal), so this view observes that instance instead of creating one.
    public init(store: ZaikoStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    public var body: some View {
        // The host (or a standalone App Shell) owns the navigation stack.
        Group {
            ZStack {
                Color(.systemGroupedBackground)
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if store.appState.globalPause.active {
                            statusBanner(
                                title: "全体停止中",
                                body: "残日数の進行を止めています。再開すると停止期間ぶんを自動で補正します。",
                                tint: Color.orange
                            )
                        }

                        if store.appState.notificationsEnabled && !store.notificationsAuthorized {
                            statusBanner(
                                title: "通知はまだ有効ではありません",
                                body: "設定から通知を許可すると、残日数がしきい値に入ったタイミングでローカル通知を出せます。",
                                tint: Color.red
                            )
                        }

                        categorySection
                        inventorySection
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("在庫管理")
            .tint(.black)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("設定", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("zaiko.settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        itemEditorContext = ItemEditorContext.create()
                    } label: {
                        Label("追加", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("zaiko.add")
                }
            }
        }
        .sheet(item: $itemEditorContext) { context in
            ItemEditorSheet(context: context) { draft in
                do {
                    if let id = context.itemID {
                        try store.updateItem(id: id, with: draft)
                    } else {
                        try store.addItem(from: draft)
                    }
                    itemEditorContext = nil
                } catch {
                    store.present(error: error)
                }
            }
        }
        .sheet(item: $restockItem) { item in
            RestockSheet(item: item) { remaining, added in
                do {
                    try store.applyRestock(to: item.id, remaining: remaining, added: added)
                    restockItem = nil
                } catch {
                    store.present(error: error)
                }
            }
        }
        .sheet(isPresented: $isSettingsPresented, onDismiss: { completeSettingsAction() }) {
            SettingsSheet(
                isPresented: $isSettingsPresented,
                onImport: { isImporting = true },
                onExport: {
                    exportDocument = InventoryBackupDocument(text: store.exportBackupJSON())
                    isExporting = true
                },
                onNotificationToggle: { isEnabled in
                    if isEnabled {
                        dismissSettingsThen(.enableNotifications)
                    } else {
                        Task {
                            await store.setNotificationsEnabled(false)
                        }
                    }
                },
                onNotificationRequest: {
                    dismissSettingsThen(.requestPermission)
                }
            )
            .environmentObject(store)
            .alert("バックアップ", isPresented: Binding(
                get: { backupError != nil },
                set: { if !$0 { backupError = nil } }
            )) {
                Button("OK") { backupError = nil }
            } message: {
                Text(backupError ?? "")
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        return
                    }

                    do {
                        let accessGranted = url.startAccessingSecurityScopedResource()
                        defer {
                            if accessGranted {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }

                        let data = try Data(contentsOf: url)
                        try store.importBackup(data: data)
                    } catch {
                        backupError = error.localizedDescription
                    }
                case .failure(let error):
                    backupError = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: store.exportFilename
            ) { result in
                if case .failure(let error) = result {
                    backupError = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "このアイテムを削除しますか？",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { shouldShow in
                    if !shouldShow {
                        pendingDeleteItem = nil
                    }
                }
            ),
            presenting: pendingDeleteItem
        ) { item in
            Button("削除", role: .destructive) {
                store.deleteItem(id: item.id)
                pendingDeleteItem = nil
            }

            Button("キャンセル", role: .cancel) {
                pendingDeleteItem = nil
            }
        } message: { item in
            Text("「\(item.name)」を削除します。")
        }
        .alert("お知らせ", isPresented: Binding(
            get: { store.transientMessage != nil },
            set: { shouldShow in
                if !shouldShow {
                    store.transientMessage = nil
                }
            }
        )) {
            Button("OK") {
                store.transientMessage = nil
            }
        } message: {
            Text(store.transientMessage ?? "")
        }
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.rescheduleNotifications() }
        }
    }

    private func statusBanner(title: String, body: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("カテゴリー")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.availableCategories, id: \.self) { category in
                        Button {
                            store.currentCategory = category
                        } label: {
                            Text(category == InventoryDomain.allCategories ? "すべて" : category)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(store.currentCategory == category ? Color.black : Color.white)
                                )
                                .foregroundStyle(store.currentCategory == category ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var inventorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("在庫一覧")
                    .font(.headline)

                Spacer()

                if !store.filteredItems.isEmpty {
                    Button(store.isEditMode ? "補充モードへ" : "編集モードへ") {
                        store.isEditMode.toggle()
                    }
                    .font(.footnote.weight(.semibold))
                }
            }

            if store.filteredItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("まだ在庫がありません")
                        .font(.headline)
                    Text("右上の追加ボタンからアイテムを登録すると、残日数の計算と通知スケジュールが始まります。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(store.filteredItems) { item in
                        InventoryCard(
                            item: item,
                            isEditMode: store.isEditMode,
                            displayMode: store.displayMode(for: item),
                            remainingStock: store.remainingStock(for: item),
                            remainingDays: store.remainingDays(for: item),
                            isAlert: store.isAlertItem(item),
                            onEdit: {
                                itemEditorContext = .edit(
                                    item: item,
                                    mode: store.displayMode(for: item),
                                    pauseState: store.appState.globalPause
                                )
                            },
                            onDelete: {
                                pendingDeleteItem = item
                            },
                            onRestock: {
                                restockItem = item
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct InventoryCard: View {
    let item: InventoryItem
    let isEditMode: Bool
    let displayMode: DisplayMode
    let remainingStock: Double?
    let remainingDays: Double?
    let isAlert: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRestock: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(2)

                    if !item.category.isEmpty {
                        Text(item.category)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.06))
                            )
                    }

                    if isAlert {
                        Image(systemName: "bell.and.waves.left.and.right.fill")
                            .foregroundStyle(.red)
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 100), spacing: 10),
                        GridItem(.flexible(minimum: 100), spacing: 10)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    compactInfoBlock(title: "残量", value: stockLine)

                    if item.needsConsumptionSetup {
                        compactInfoBlock(title: "状態", value: "消費速度を設定")
                    } else if let remainingDays {
                        compactInfoBlock(
                            title: "残日数",
                            value: "約 \(max(0, remainingDays.rounded(.up)).formattedNumber(maximumFractionDigits: 0)) 日",
                            accent: isAlert ? .red : .primary
                        )
                    }

                    if let speedSummary = item.speedSummary(mode: displayMode) {
                        compactInfoBlock(title: "消費速度", value: speedSummary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                Button(action: item.needsConsumptionSetup || isEditMode ? onEdit : onRestock) {
                    Label(item.needsConsumptionSetup || isEditMode ? "編集" : "補充", systemImage: item.needsConsumptionSetup || isEditMode ? "pencil" : "shippingbox")
                        .frame(width: 84)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)

                Button(role: .destructive, action: onDelete) {
                    Label("削除", systemImage: "trash")
                        .frame(width: 84)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isAlert ? Color.red.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var stockLine: String {
        let stock = max(0, remainingStock ?? item.currentStock)
        let amount = stock.formattedNumber
        guard !item.unit.isEmpty else {
            return amount
        }
        return "\(amount) \(item.unit)"
    }

    private func compactInfoBlock(title: String, value: String, accent: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var store: ZaikoStore
    @Environment(\.openURL) private var openURL

    @Binding var isPresented: Bool
    let onImport: () -> Void
    let onExport: () -> Void
    let onNotificationToggle: @MainActor @Sendable (Bool) -> Void
    let onNotificationRequest: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("操作") {
                    Toggle("編集モード", isOn: $store.isEditMode)

                    Toggle("全体停止", isOn: Binding(
                        get: { store.appState.globalPause.active },
                        set: { newValue in
                            if newValue != store.appState.globalPause.active {
                                store.togglePause()
                            }
                        }
                    ))

                    Button("JSONバックアップを書き出す", action: onExport)
                    Button("JSONバックアップを読み込む", action: onImport)
                }

                Section("通知") {
                    Stepper(value: Binding(
                        get: { Int(store.appState.alertThresholdDays) },
                        set: { store.setAlertThresholdDays(Double($0)) }
                    ), in: 1...30) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("アラートしきい値")
                            Text("\(Int(store.appState.alertThresholdDays))日以内")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("ローカル通知を有効にする", isOn: Binding(
                        get: { store.appState.notificationsEnabled },
                        set: { value in onNotificationToggle(value) }
                    ))

                    Text(store.notificationStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if store.authorizationStatus == .denied {
                        Button("iPhoneの設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    } else if !store.notificationsAuthorized {
                        Button("通知権限をリクエスト", action: onNotificationRequest)
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

private extension ZaikoRootView {
    private func dismissSettingsThen(_ action: SettingsAction) {
        pendingSettingsAction = action
        isSettingsPresented = false
    }

    func completeSettingsAction() {
        let action = pendingSettingsAction
        pendingSettingsAction = nil
        switch action {
        case .enableNotifications:
            Task { await store.setNotificationsEnabled(true) }
        case .requestPermission:
            Task { await store.requestNotificationPermission() }
        case nil:
            break
        }
    }
}

private struct ItemEditorSheet: View {
    let context: ItemEditorContext
    let onSave: (ItemDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ItemDraft
    @State private var errorMessage: String?

    init(context: ItemEditorContext, onSave: @escaping (ItemDraft) -> Void) {
        self.context = context
        self.onSave = onSave
        _draft = State(initialValue: context.draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("名前", text: $draft.name)
                        .accessibilityIdentifier("zaiko.editor.name")
                    TextField("カテゴリー", text: $draft.category)
                        .accessibilityIdentifier("zaiko.editor.category")
                    TextField("単位", text: $draft.unit)
                        .accessibilityIdentifier("zaiko.editor.unit")
                }

                Section("在庫と消費速度") {
                    TextField("現在の在庫量", text: $draft.stock)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("zaiko.editor.stock")

                    Picker("入力モード", selection: $draft.displayMode) {
                        Text("日/単位").tag(DisplayMode.perUnitTime)
                        Text("単位/日").tag(DisplayMode.perDayAmount)
                    }
                    .pickerStyle(.segmented)

                    TextField(draft.displayMode.placeholderText, text: $draft.speed)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("zaiko.editor.speed")

                    Text(draft.displayMode.helpText(for: draft.unit))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(context.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(context.commitLabel) {
                        do {
                            try draft.validate()
                            onSave(draft)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}

private struct RestockSheet: View {
    let item: InventoryItem
    let onSave: (Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var remaining = ""
    @State private var added = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("対象") {
                    Text(item.name)
                    if !item.unit.isEmpty {
                        Text("単位: \(item.unit)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("補充内容") {
                    TextField("補充前残量", text: $remaining)
                        .keyboardType(.decimalPad)
                    TextField("補充量", text: $added)
                        .keyboardType(.decimalPad)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("補充")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        do {
                            let remainingValue = try InventoryDomain.parseNonNegativeNumber(remaining, fieldName: "補充前残量")
                            let addedValue = try InventoryDomain.parseNonNegativeNumber(added, fieldName: "補充量")
                            onSave(remainingValue, addedValue)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}

struct ItemEditorContext: Identifiable {
    let id = UUID()
    let itemID: Int64?
    let title: String
    let commitLabel: String
    let draft: ItemDraft

    static func create() -> ItemEditorContext {
        ItemEditorContext(
            itemID: nil,
            title: "新しいアイテム",
            commitLabel: "保存",
            draft: ItemDraft.empty()
        )
    }

    static func edit(item: InventoryItem, mode: DisplayMode, pauseState: GlobalPauseState, now: Date = .now) -> ItemEditorContext {
        ItemEditorContext(
            itemID: item.id,
            title: "アイテム編集",
            commitLabel: "更新",
            draft: ItemDraft(item: item, mode: mode, pauseState: pauseState, now: now)
        )
    }
}

#endif
