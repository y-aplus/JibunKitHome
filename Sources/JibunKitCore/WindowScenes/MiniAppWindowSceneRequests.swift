import Foundation

/// Narrowly models host window creation and destruction without pretending a
/// request means iPadOS actually created or closed a window.
@MainActor
public protocol MiniAppWindowSceneRequesting: AnyObject {
    func requestWindow(userActivity: NSUserActivity?, onFailure: @escaping @MainActor @Sendable (Error) -> Void)
    func destroyWindow(sessionID: MiniAppWindowSessionID, onFailure: @escaping @MainActor @Sendable (Error) -> Void) -> Bool
}

#if canImport(UIKit) && os(iOS)
import UIKit

@MainActor
public final class MiniAppUIKitWindowSceneRequester: MiniAppWindowSceneRequesting {
    private let application: UIApplication

    public init(application: UIApplication = .shared) { self.application = application }

    public func requestWindow(
        userActivity: NSUserActivity?,
        onFailure: @escaping @MainActor @Sendable (Error) -> Void
    ) {
        // A nil session explicitly requests a new session. The newer role-based
        // activation API may select an existing matching session instead.
        application.requestSceneSessionActivation(
            nil, userActivity: userActivity, options: nil, errorHandler: onFailure
        )
    }

    public func destroyWindow(
        sessionID: MiniAppWindowSessionID,
        onFailure: @escaping @MainActor @Sendable (Error) -> Void
    ) -> Bool {
        guard let session = application.openSessions.first(where: {
            $0.persistentIdentifier == sessionID.rawValue
        }) else { return false }
        application.requestSceneSessionDestruction(session, options: nil, errorHandler: onFailure)
        return true
    }
}
#endif
