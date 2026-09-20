#if canImport(SwiftUI) && os(iOS)
import Foundation
import SwiftUI

private struct MiniAppSceneActivityIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

public extension EnvironmentValues {
    /// Matches MiniAppSceneActivity.sceneID for this mounted root. Use it to
    /// bind a foreground operation to the window that started it, even when
    /// another window is showing the same Feature. Nil means not connected.
    var miniAppSceneActivityID: UUID? {
        get { self[MiniAppSceneActivityIDKey.self] }
        set { self[MiniAppSceneActivityIDKey.self] = newValue }
    }
}
#endif
