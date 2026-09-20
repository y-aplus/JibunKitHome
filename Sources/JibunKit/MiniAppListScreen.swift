#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI
import UIKit

struct MiniAppListScreen: View {
    @Bindable var navigation: AppNavigation
    @State private var searchText = ""
    @State private var windowError: String?

    private var matchingApps: [MiniAppDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return MiniAppRegistry.enabled }
        return MiniAppRegistry.enabled.filter {
            $0.title.localizedStandardContains(query)
                || $0.id.rawValue.localizedStandardContains(query)
        }
    }

    var body: some View {
        let owner = navigation.activeID
        NavigationStack(path: navigation.pathBinding) {
            // A disabled owner's presenting root stays mounted until the
            // departure acknowledgement; it is no longer an admitted entry.
            if let owner, let miniApp = MiniAppRegistry.all.first(where: { $0.id == owner }) {
                Group {
                    if let failure = MiniAppRegistry.launchState.errors[owner] {
                        ContentUnavailableView("起動時の準備に失敗しました", systemImage: "exclamationmark.triangle",
                            description: Text(failure + "\n登録条件を修正した後、アプリを起動し直してください。"))
                            .accessibilityIdentifier("miniapp.launch.error.\(owner.rawValue)")
                    } else {
                        miniApp.makeDestination()
                    }
                }
                    .disabled(!MiniAppRegistry.management.isEnabled(owner))
                    .navigationTitle(miniApp.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if navigation.path.isEmpty {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { navigation.showList() } label: {
                                    Label("ミニアプリ", systemImage: "chevron.left")
                                }
                                .accessibilityLabel("ミニアプリ")
                                .accessibilityIdentifier("miniapp.back-to-list")
                            }
                        }
                    }
            } else {
                launcher
            }
        }
        // Feature-local destination types may be identical in different apps.
        // Rebuild the stack for its owner while retaining that owner's path.
        .id(navigation.stackID)
        .onChange(of: MiniAppRegistry.registeredIDs) { _, _ in navigation.discardUnavailableOwners() }
        .alert("ウインドウを開けませんでした", isPresented: Binding(
            get: { windowError != nil }, set: { if !$0 { windowError = nil } }
        )) {
            Button("閉じる", role: .cancel) { windowError = nil }
        } message: { Text(windowError ?? "") }
        .sheet(item: $navigation.hostSheet, onDismiss: navigation.hostSheetDidDismiss) { sheet in
            switch sheet {
            case .backup: BackupScreen(definitions: MiniAppRegistry.enabled,
                                      lifecycleForDefinition: { MiniAppWindowOwnership.restoreLifecycle(for: $0) })
            case .management: MiniAppManagementScreen()
            case .incoming: MiniAppIncomingScreen(navigation: navigation)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if owner != nil {
                HStack {
                    Spacer()
                    Menu {
                        Button("ミニアプリ一覧", systemImage: "square.grid.2x2") { navigation.showList() }
                            .accessibilityIdentifier("miniapp.switch.list")
                        ForEach(MiniAppRegistry.enabled) { miniApp in
                            Button { navigation.open(miniApp.id) } label: {
                                Label(miniApp.title, systemImage: miniApp.systemImage)
                            }
                            .accessibilityIdentifier("miniapp.switch.\(miniApp.id.rawValue)")
                        }
                        Divider()
                        Button("このアプリの最初の画面へ", systemImage: "arrow.uturn.backward") {
                            navigation.resetCurrentPath()
                        }
                        .accessibilityIdentifier("miniapp.switch.reset")
                    } label: {
                        Label("ミニアプリを切り替え", systemImage: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("miniapp.switch.open")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private var launcher: some View {
        List {
            if let failure = MiniAppRegistry.launchState.hostError {
                Text("起動時の設定に失敗しました: \(failure)").foregroundStyle(.red)
            }
            ForEach(matchingApps) { miniApp in
                Button { navigation.open(miniApp.id) } label: {
                    VStack(alignment: .leading) {
                        Label(miniApp.title, systemImage: miniApp.systemImage)
                        if let failure = MiniAppRegistry.launchState.errors[miniApp.id] {
                            Text("準備失敗: \(failure)").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                .accessibilityIdentifier("miniapp.\(miniApp.id.rawValue)")
            }
        }
        .navigationTitle("ミニアプリ")
        .searchable(text: $searchText, prompt: "アプリ名・IDで検索")
        .overlay {
            if matchingApps.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("管理", systemImage: "slider.horizontal.3") { navigation.requestHostSheet(.management) }
                    .accessibilityIdentifier("management.open")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("バックアップ", systemImage: "externaldrive") { navigation.requestHostSheet(.backup) }
                    .accessibilityIdentifier("backup.open")
            }
            ToolbarItem(placement: .bottomBar) {
                Button("受信", systemImage: "tray.and.arrow.down") { navigation.requestHostSheet(.incoming) }
                    .accessibilityIdentifier("incoming.open")
            }
            if UIApplication.shared.supportsMultipleScenes {
                ToolbarItem(placement: .bottomBar) {
                    Button("新しいウインドウ", systemImage: "rectangle.badge.plus") {
                        MiniAppUIKitWindowSceneRequester().requestWindow(userActivity: nil) {
                            windowError = $0.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("window.new")
                }
            }
        }
    }
}
#endif
