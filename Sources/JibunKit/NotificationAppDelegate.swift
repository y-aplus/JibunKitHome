#if os(iOS)
import JibunKitCore
import OSLog
import UIKit
import UserNotifications

@MainActor
final class NotificationAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Apply persisted admission before passive cold-launch registrations.
        // Registration rejection must not turn a fallible OS operation into an
        // app-wide trap. Keep the failed owner visible with its launch error.
        _ = MiniAppRegistry.management
        MiniAppRegistry.launchState.register(MiniAppRegistry.all)
        do {
            let registrations = Dictionary(uniqueKeysWithValues:
                MiniAppRegistry.all.map { ($0.id,
                    MiniAppRegistry.management.isEnabled($0.id) && MiniAppRegistry.launchState.errors[$0.id] == nil
                        ? $0.notificationCategories : []) })
            try MiniAppNotificationCategoryRegistry.shared.configure(registrations)
        } catch {
            MiniAppRegistry.launchState.hostError = String(describing: error)
            Logger(subsystem: "com.jibunkit.app", category: "Launch")
                .error("Notification registration failed: \(String(describing: error))")
        }
        MiniAppRegistry.reconcileContinuingSurfaces()
        // Explicit build-time opt-in. It does not replace a valid aps-environment
        // entitlement/profile. Registration failures still reach the coordinator.
        if Bundle.main.object(forInfoDictionaryKey: "JibunKitRemotePushEnabled") as? Bool == true {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MiniAppRemotePushCoordinator.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MiniAppRemotePushCoordinator.shared.didFailToRegisterForRemoteNotifications(error)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            guard let route = MiniAppNotificationRoute.candidateRoute(userInfo: userInfo),
                  MiniAppRegistry.management.isEnabled(route.id),
                  MiniAppRegistry.launchState.errors[route.id] == nil else {
                completionHandler(.noData)
                return
            }
            let result = await MiniAppRemotePushCoordinator.shared.deliver(userInfo: userInfo)
            switch result {
            case .newData: completionHandler(.newData)
            case .noData: completionHandler(.noData)
            case .failed: completionHandler(.failed)
            }
        }
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        MiniAppBackgroundURLSessionReconnectRegistry.shared.handleEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let route = MiniAppNotificationRoute.candidateRoute(userInfo: notification.request.content.userInfo)
        let event = MiniAppForegroundNotification(requestIdentifier: notification.request.identifier,
            categoryIdentifier: notification.request.content.categoryIdentifier, destination: route?.destination,
            requestSnapshot: Self.snapshot(notification.request))
        Task { @MainActor in
            if let route, !MiniAppRegistry.management.isEnabled(route.id) {
                completionHandler([])
                return
            }
            completionHandler(MiniAppNotificationPresentation.options(for: event, route: route,
                policyForOwner: { MiniAppRegistry.definition(for: $0)?.notificationPresentation }))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        Logger(subsystem: "com.jibunkit.app", category: "NotificationRouting")
            .notice("Notification response received")
        let candidate = MiniAppNotificationRoute.candidateRoute(
            userInfo: response.notification.request.content.userInfo
        )
        let kind: MiniAppNotificationAction.Kind
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: kind = .open
        case UNNotificationDismissActionIdentifier: kind = .dismiss
        default: kind = .custom(response.actionIdentifier)
        }
        let action = MiniAppNotificationAction(
            kind: kind,
            requestIdentifier: response.notification.request.identifier,
            destination: candidate?.destination,
            userText: (response as? UNTextInputNotificationResponse)?.userText,
            requestSnapshot: Self.snapshot(response.notification.request)
        )
        // UIKit performs snapshot/state restoration work from this callback.
        // The synthesized async delegate thunk can complete on a cooperative
        // executor, causing UIKit's main-thread assertion on notification taps.
        Task { @MainActor in
            defer { completionHandler() }
            if let candidate, !MiniAppRegistry.management.isEnabled(candidate.id) { return }
            // Opening preserves the legacy route behavior. Dismiss/custom actions
            // must not navigate or disturb another Feature's visible screen.
            await MiniAppNotificationActionDelivery.deliver(action, route: candidate,
                handlerForOwner: { MiniAppRegistry.definition(for: $0)?.onNotificationAction },
                open: { AppSceneRouting.shared.open($0) })
            Logger(subsystem: "com.jibunkit.app", category: "NotificationRouting")
                .notice("Notification route dispatched; parsed route: \(candidate != nil)")
        }
    }

    nonisolated private static func snapshot(_ request: UNNotificationRequest) -> MiniAppNotificationRequestSnapshot? {
        do { return try MiniAppNotificationRequestSnapshot(request: request) }
        catch {
            // A snapshot failure must not suppress legacy navigation or completion.
            Logger(subsystem: "com.jibunkit.app", category: "NotificationRouting")
                .error("Unable to snapshot native notification request: \(String(describing: error))")
            return nil
        }
    }
}
#endif
