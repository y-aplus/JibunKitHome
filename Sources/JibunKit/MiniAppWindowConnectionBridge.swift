#if os(iOS)
import JibunKitCore
import Observation
import UIKit

/// One bridge per mounted window root. A delayed cleanup cannot reconnect a
/// root that has since disconnected or moved to another OS session.
@MainActor @Observable
final class MiniAppWindowConnectionBridge {
    private(set) var connection: MiniAppWindowConnection?
    private let registry: MiniAppWindowSceneRegistry
    private var revision = UUID()
    private var sessionID: MiniAppWindowSessionID?
    private var phase: MiniAppSceneActivity.Phase = .inactive
    private var selectedID: MiniAppID?

    init(registry: MiniAppWindowSceneRegistry) { self.registry = registry }

    func connect(scene: UIWindowScene, navigation: AppNavigation,
                 phase: MiniAppSceneActivity.Phase, selectedID: MiniAppID?) {
        connect(sessionID: .init(scene.session.persistentIdentifier),
                phase: phase, selectedID: selectedID) { [weak navigation] route in
            navigation?.openNotificationRoute(route)
        }
    }

    func connect(sessionID: MiniAppWindowSessionID, phase: MiniAppSceneActivity.Phase,
                 selectedID: MiniAppID?, route: @escaping MiniAppWindowSceneRegistry.RouteHandler) {
        update(phase: phase, selectedID: selectedID)
        guard self.sessionID != sessionID else { return }
        disconnect()
        self.sessionID = sessionID
        let expected = UUID()
        revision = expected
        Task { @MainActor [self] in
            guard revision == expected else { return }
            let created = await registry.connect(sessionID: sessionID, phase: phase,
                selectedID: selectedID, route: route)
            guard revision == expected,
                  registry.snapshot(for: sessionID)?.connection == created else {
                _ = await registry.disconnect(created)
                return
            }
            connection = created
            registry.update(created, phase: self.phase, selectedID: self.selectedID)
        }
    }

    func update(phase: MiniAppSceneActivity.Phase, selectedID: MiniAppID?) {
        self.phase = phase; self.selectedID = selectedID
        if let connection { registry.update(connection, phase: phase, selectedID: selectedID) }
    }

    func disconnect() {
        revision = UUID(); sessionID = nil
        let old = connection
        connection = nil
        if let old {
            Task { @MainActor [registry] in _ = await registry.disconnect(old) }
        }
    }
}
#endif
