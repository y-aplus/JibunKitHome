#if canImport(SwiftUI) && os(iOS)
import SwiftUI

private struct MiniAppWindowConnectionEnvironmentKey: EnvironmentKey {
    static let defaultValue: MiniAppWindowConnection? = nil
}

private struct MiniAppWindowRegistryEnvironmentKey: EnvironmentKey {
    static let defaultValue: MiniAppWindowSceneRegistry? = nil
}

public extension EnvironmentValues {
    /// The current root's ephemeral connection. Capture it with callbacks that
    /// may arrive late so explicit delivery can reject a stale generation.
    var miniAppWindowConnection: MiniAppWindowConnection? {
        get { self[MiniAppWindowConnectionEnvironmentKey.self] }
        set { self[MiniAppWindowConnectionEnvironmentKey.self] = newValue }
    }

    /// The process-shared registry injected by the host into every scene root.
    /// It is optional so Feature previews and single-window hosts need no fake.
    var miniAppWindowRegistry: MiniAppWindowSceneRegistry? {
        get { self[MiniAppWindowRegistryEnvironmentKey.self] }
        set { self[MiniAppWindowRegistryEnvironmentKey.self] = newValue }
    }
}
#endif
