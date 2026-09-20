#if os(iOS)
import SwiftUI
import JibunKitCore
import CoreSpotlight

@main
struct JibunKitApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self)
    private var notificationAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var lifecycle = MiniAppRegistry.makeLifecycleDispatcher()

    var body: some Scene {
        WindowGroup {
            MiniAppSceneRoot()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: lifecycle.update(.active)
            case .inactive: lifecycle.update(.inactive)
            case .background: lifecycle.update(.background)
            @unknown default: break
            }
        }
    }
}

/// State is instantiated inside WindowGroup's view hierarchy, once per window.
private struct MiniAppSceneRoot: View {
    @State private var navigation = AppNavigation()
    @SceneStorage("jibunkit.selected-mini-app") private var restoredOwner: String?
    @State private var registration: UUID?
    @State private var activity = MiniAppRegistry.makeSceneActivityDispatcher()
    @State private var activityConnectionID: UUID?
    @State private var windowConnection = MiniAppWindowConnectionBridge(registry: AppSceneRouting.windows)
    @Environment(\.scenePhase) private var scenePhase

    private var activityPhase: MiniAppSceneActivity.Phase {
        switch scenePhase {
        case .active: .active
        case .background: .background
        default: .inactive
        }
    }

    var body: some View {
        MiniAppListScreen(navigation: navigation)
            .environment(\.miniAppConsentStore, MiniAppRegistry.consents)
            .environment(\.miniAppSceneActivityID, activityConnectionID)
            .environment(\.miniAppWindowRegistry, AppSceneRouting.windows)
            .environment(\.miniAppWindowConnection, windowConnection.connection)
            // SwiftUI delivers this URL to a particular scene; keep that target.
            .onOpenURL { navigation.openURL($0) }
            .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                // SwiftUI selected this scene; do not broadcast or select a
                // different window through the process notification router.
                if let route = MiniAppSpotlightRoute.resolve(userActivity, registeredIDs: MiniAppRegistry.registeredIDs) {
                    navigation.open(route)
                }
            }
            .background(MiniAppSceneConnection(connect: {
                activity.connect(phase: activityPhase, selectedID: navigation.activeID)
                activityConnectionID = activity.connectionID
                guard registration == nil else { return }
                registration = AppSceneRouting.shared.register(isActive: scenePhase == .active) { [weak navigation] route in
                    navigation?.openNotificationRoute(route)
                }
            }, disconnect: {
                activity.disconnect()
                activityConnectionID = nil
                windowConnection.disconnect()
                if let registration { AppSceneRouting.shared.unregister(registration) }
                registration = nil
            }, connectScene: { scene in
                windowConnection.connect(scene: scene, navigation: navigation,
                    phase: activityPhase, selectedID: navigation.activeID)
            }))
            .onChange(of: scenePhase) { _, phase in
                activity.update(phase: activityPhase, selectedID: navigation.activeID)
                windowConnection.update(phase: activityPhase, selectedID: navigation.activeID)
                if let registration { AppSceneRouting.shared.update(registration, isActive: phase == .active) }
            }
            .onChange(of: navigation.activeID) { _, selectedID in
                restoredOwner = selectedID?.rawValue
                activity.update(phase: activityPhase, selectedID: selectedID)
                windowConnection.update(phase: activityPhase, selectedID: selectedID)
            }
            .onChange(of: restoredOwner, initial: true) { _, restoredOwner in
                guard navigation.activeID == nil, let restoredOwner else { return }
                let candidate = MiniAppID(restoredOwner)
                guard MiniAppRegistry.registeredIDs.contains(candidate) else {
                    // A rejected selection must not survive until this owner
                    // is enabled or introduced again in a later process.
                    self.restoredOwner = nil
                    return
                }
                navigation.open(candidate)
            }
    }
}
#endif
