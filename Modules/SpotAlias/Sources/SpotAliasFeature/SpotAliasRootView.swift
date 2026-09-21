#if os(iOS)
import SwiftUI

public struct SpotAliasRootView: View {
    @ObservedObject var store: SpotAliasStore
    @Environment(\.openURL) private var openURL
    @State private var editingItem: AppAliasItem?
    @State private var isAddingNew = false
    @State private var isShowingPresets = false

    public init(store: SpotAliasStore) {
        self.store = store
    }

    public var body: some View {
        List {
            // Pending launch feedback
            if let pending = store.pendingLaunchItem {
                Section {
                    HStack {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("「\(pending.title)」を起動中...")
                                .font(.headline)
                            Text("自動で開かない場合は右のボタンをタップ")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("開く") {
                            launch(pending)
                            store.clearPendingLaunchItem()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Spotlight Diagnostics section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.accentColor)
                            .font(.headline)
                        Text("Spotlight 疎通診断")
                            .font(.headline)
                        Spacer()
                        if store.isIndexing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let result = store.lastSyncResult {
                        Text(result)
                            .font(.subheadline.bold())
                            .foregroundColor(result.hasPrefix("✓") ? .green : .red)
                    } else {
                        Text("未診断（下のボタンを押してテストしてください）")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let date = store.lastSyncDate {
                        Text("最終登録: \(date.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    HStack(spacing: 12) {
                        Button {
                            store.testSpotlightSync()
                        } label: {
                            Label("疎通テスト実行", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isIndexing)

                        Button {
                            store.resyncAllSpotlight()
                        } label: {
                            Label("全再登録", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isIndexing)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("インデックス診断")
            } footer: {
                Text("「疎通テスト実行」を押すと「JibunKit 疎通テスト」項目が登録されます。登録後にホーム画面の Spotlight で「jibunkit」と検索して確認してください。")
            }

            // Search in-app section
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("アプリ内絞り込み (例: paypay, マック)", text: $store.searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !store.searchQuery.isEmpty {
                        Button {
                            store.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("登録アプリの絞り込み")
            }

            // Registered aliases section
            Section {
                if store.filteredItems.isEmpty {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(store.searchQuery.isEmpty ? "登録されたアプリはありません" : "一致するアプリがありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if store.searchQuery.isEmpty {
                            Button("プリセットから追加する") {
                                isShowingPresets = true
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(store.filteredItems) { item in
                        AppAliasRow(
                            item: item,
                            onToggle: { store.toggleEnabled(for: item) },
                            onLaunch: { launch(item) },
                            onEdit: { editingItem = item }
                        )
                    }
                    .onDelete(perform: store.remove)
                }
            } header: {
                HStack {
                    Text("登録アプリ (\(store.items.count))")
                    Spacer()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isShowingPresets = true
                } label: {
                    Label("プリセット", systemImage: "sparkles")
                }

                Button {
                    isAddingNew = true
                } label: {
                    Label("新規追加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingNew) {
            NavigationStack {
                AppAliasEditView(
                    title: "アプリの追加",
                    item: AppAliasItem(title: "", aliases: [], urlScheme: ""),
                    onSave: { newItem in
                        store.add(newItem)
                        isAddingNew = false
                    },
                    onCancel: { isAddingNew = false }
                )
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                AppAliasEditView(
                    title: "アプリの編集",
                    item: item,
                    onSave: { updated in
                        store.update(updated)
                        editingItem = nil
                    },
                    onCancel: { editingItem = nil }
                )
            }
        }
        .sheet(isPresented: $isShowingPresets) {
            NavigationStack {
                AppAliasPresetsView(
                    onSelect: { preset in
                        store.addPreset(preset)
                    },
                    onDismiss: { isShowingPresets = false }
                )
            }
        }
    }

    private func launch(_ item: AppAliasItem) {
        guard let url = URL(string: item.urlScheme) else { return }
        openURL(url)
    }
}

// MARK: - Row View

struct AppAliasRow: View {
    let item: AppAliasItem
    let onToggle: () -> Void
    let onLaunch: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: item.symbolName.isEmpty ? "app.fill" : item.symbolName)
                        .font(.title2)
                        .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title)
                                .font(.headline)
                                .foregroundColor(item.isEnabled ? .primary : .secondary)
                            if !item.isEnabled {
                                Text("無効")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }

                        if !item.aliases.isEmpty {
                            Text(item.aliases.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Text(item.urlScheme)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Launch test button
            Button(action: onLaunch) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)

            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { item.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
    }
}

// MARK: - Edit View

struct AppAliasEditView: View {
    let title: String
    @State private var item: AppAliasItem
    @State private var aliasesText: String
    @Environment(\.openURL) private var openURL
    let onSave: (AppAliasItem) -> Void
    let onCancel: () -> Void

    private let symbolCandidates = [
        "cart.fill", "takeoutbag.and.cup.and.straw.fill", "cup.and.saucer.fill",
        "qrcode.viewfinder", "bubble.left.and.bubble.right.fill", "shippingbox.fill",
        "tag.fill", "play.rectangle.fill", "message.fill", "map.fill",
        "tram.fill", "music.note", "headphones", "app.fill", "link",
    ]

    init(
        title: String,
        item: AppAliasItem,
        onSave: @escaping (AppAliasItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self._item = State(initialValue: item)
        self._aliasesText = State(initialValue: item.aliases.joined(separator: ", "))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isValid: Bool {
        !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !item.urlScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("アプリ基本情報") {
                TextField("アプリ名 (例: ロピア)", text: $item.title)
                TextField("URL Scheme (例: lopia://)", text: $item.urlScheme)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }

            Section {
                TextField("エイリアス (カンマ区切りで複数入力)", text: $aliasesText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("検索キーワード (エイリアス)")
            } footer: {
                Text("例: lopia, ropia, ろぴあ, スーパー\nSpotlightでこれらのキーワードを入力した時にヒットします。")
            }

            Section("アイコン") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(symbolCandidates, id: \.self) { symbol in
                            Button {
                                item.symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title2)
                                    .foregroundColor(item.symbolName == symbol ? .white : .primary)
                                    .frame(width: 44, height: 44)
                                    .background(item.symbolName == symbol ? Color.accentColor : Color.secondary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("メモ・詳細") {
                TextField("メモ (任意)", text: $item.note)
                Toggle("Spotlightに登録する", isOn: $item.isEnabled)
            }

            if !item.urlScheme.isEmpty, let url = URL(string: item.urlScheme) {
                Section {
                    Button {
                        openURL(url)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.forward.app")
                            Text("起動テスト (\(item.urlScheme))")
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    var finalItem = item
                    let split = aliasesText
                        .components(separatedBy: CharacterSet(charactersIn: ",\n、"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    finalItem.aliases = Array(Set(split))
                    onSave(finalItem)
                }
                .disabled(!isValid)
            }
        }
    }
}

// MARK: - Presets View

struct AppAliasPresetsView: View {
    let onSelect: (AppAliasPreset) -> Void
    let onDismiss: () -> Void
    @State private var addedTitles: Set<String> = []

    var body: some View {
        List {
            Section {
                Text("日本の定番アプリのエイリアスとURLスキームのプリセットです。「追加」を押すとユーザー辞書に登録されます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(SpotAliasPresets.builtin) { preset in
                HStack(spacing: 12) {
                    Image(systemName: preset.symbolName)
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(preset.aliases.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if addedTitles.contains(preset.title) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                            .font(.caption.bold())
                    } else {
                        Button("追加") {
                            onSelect(preset)
                            addedTitles.insert(preset.title)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("定番アプリ プリセット")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了", action: onDismiss)
            }
        }
    }
}
#endif
