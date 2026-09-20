#if os(iOS)
import JibunKitCore
import SwiftUI
import UIKit

/// Two ordinary Feature definitions used by the P2 scene host. The host must
/// include these in its normal registry; the probe does not create a parallel
/// navigation implementation.
@MainActor
enum P2ScenesProbe {
    static let firstID = MiniAppID("p2-scene-a")
    static let secondID = MiniAppID("p2-scene-b")

    static var definitions: [MiniAppDefinition] {
        let values = [definition(id: firstID, title: "Scene A"), definition(id: secondID, title: "Scene B")]
        guard ProcessInfo.processInfo.arguments.contains("--p2-scenes-omit-a-at-launch") else { return values }
        return values.filter { $0.id != firstID }
    }

    private static func definition(id: MiniAppID, title: String) -> MiniAppDefinition {
        MiniAppDefinition(id: id, title: title, systemImage: "rectangle.on.rectangle") { _ in
            P2SceneOwnerView(owner: id)
        }
    }
}

private struct P2SceneOwnerView: View {
    let owner: MiniAppID
    @Environment(\.miniAppWindowConnection) private var windowConnection
    @State private var windowError: String?
    /// SceneStorage supplies a value that the OS may restore for this scene. Its
    /// presence alone is not restoration evidence; the OS reconnect is observed.
    @SceneStorage private var count: Int

    init(owner: MiniAppID) {
        self.owner = owner
        _count = SceneStorage(wrappedValue: 0, owner.storageKey("p2-scene-count"))
    }

    var body: some View {
        VStack {
            Text(owner.rawValue).accessibilityIdentifier("p2.scene.owner")
            Text("\(count)").accessibilityIdentifier("p2.scene.count")
            if let windowConnection {
                Text(windowConnection.sessionID.rawValue)
                    .accessibilityIdentifier("p2.scene.session")
                Text(UIApplication.shared.openSessions.map(\.persistentIdentifier).sorted().joined(separator: "\n"))
                    .accessibilityIdentifier("p2.scene.open-sessions")
            }
            Button("increment") { count += 1 }.accessibilityIdentifier("p2.scene.increment")
            Button("new window") {
                MiniAppUIKitWindowSceneRequester().requestWindow(userActivity: nil) {
                    windowError = $0.localizedDescription
                }
            }
            .accessibilityIdentifier("p2.scene.new-window")
            if let windowConnection {
                Button("activate other window") {
                    let others = UIApplication.shared.openSessions.filter {
                        $0.persistentIdentifier != windowConnection.sessionID.rawValue
                    }
                    guard others.count == 1, let other = others.first else {
                        windowError = "expected one other session"
                        return
                    }
                    UIApplication.shared.requestSceneSessionActivation(
                        other, userActivity: nil, options: nil,
                        errorHandler: { windowError = $0.localizedDescription })
                }
                .accessibilityIdentifier("p2.scene.activate-other")
                Button("close this window") {
                    guard MiniAppUIKitWindowSceneRequester().destroyWindow(
                        sessionID: windowConnection.sessionID,
                        onFailure: { windowError = $0.localizedDescription }
                    ) else {
                        windowError = "session not found"
                        return
                    }
                }
                .accessibilityIdentifier("p2.scene.close-window")
            }
        }
        .alert("window operation failed", isPresented: Binding(
            get: { windowError != nil }, set: { if !$0 { windowError = nil } }
        )) { Button("close", role: .cancel) { windowError = nil } }
        message: { Text(windowError ?? "") }
    }
}

@MainActor
enum P2ScenesOSDiagnostic {
    static var connectedWindowSessions: [String] {
        UIApplication.shared.connectedScenes.compactMap { scene in
            (scene as? UIWindowScene)?.session.persistentIdentifier
        }.sorted()
    }
}
#endif
