#if os(iOS)
import CounterIntegration
import JibunKitCore
import ReminderIntegration
import ZaikoIntegration
import SpotAliasIntegration
import Foundation
import CoreSpotlight
import WidgetKit
import OSLog
import Observation

@MainActor @Observable
final class ContinuingSurfaceStatus {
    var errors: [MiniAppID: String] = [:]
    var pending: Set<MiniAppID> = []
}

@MainActor
enum MiniAppRegistry {
    static let all = makeRegistry([
        CounterMiniApp.definition,
        ReminderMiniApp.definition,
        ZaikoMiniApp.definition,
        SpotAliasMiniApp.definition,
    ])

    static let consents = MiniAppConsentStore(defaults: .standard)
    // With no usable shared-group configuration, local management still works.
    // The Widget independently reports unavailable storage in that configuration.
    private static let managementDefaults = (try? MiniAppStorage.sharedDefaults()) ?? .standard
    static let incomingStore = Result { try MiniAppIncomingStore.shared() }
    private(set) static var incomingCatalogError: String?
    static let management = makeManagement()
    private static var continuingTasks: [MiniAppID: Task<Void, Never>] = [:]
    static let continuingStatus = ContinuingSurfaceStatus()
    static let launchState = MiniAppLaunchState()

    /// App-scoped work: leaving a Feature screen must not cancel OS activities.
    /// A cold launch or foreground transition rechecks daemon state. Per-owner
    /// tasks avoid duplicate subscriptions and do not make A wait for B.
    static func reconcileContinuingSurfaces(for owner: MiniAppID? = nil) {
        for definition in all where !definition.continuingSurfaces.isEmpty
            && (owner == nil || definition.id == owner) && management.isEnabled(definition.id)
            && launchState.errors[definition.id] == nil {
            let id = definition.id
            guard continuingTasks[id] == nil else { continue }
            let group = definition.continuingSurfaceGroup
            continuingStatus.pending.insert(id)
            continuingTasks[id] = Task {
                defer {
                    continuingTasks[id] = nil
                    continuingStatus.pending.remove(id)
                }
                do {
                    try await group.reconcile()
                    continuingStatus.errors[id] = nil
                } catch {
                    continuingStatus.errors[id] = error.localizedDescription
                    Logger(subsystem: "com.jibunkit.app", category: "ContinuingSurfaces")
                        .error("Reconciliation failed for \(id.rawValue, privacy: .public): \(error.localizedDescription)")
                }
            }
        }
    }

    // Keep closure isolation and defaults out of a nested static initializer.
    // These factories also leave one activity dispatcher per App/scene owner.
    private static func makeManagement() -> MiniAppManagement {
        let registrations: [MiniAppManagement.Registration] = all.map { definition in
            MiniAppManagement.Registration(
                id: definition.id, lifetime: definition.lifetime, removal: incomingRemoval(for: definition),
                externalAccess: MiniAppWindowOwnership.externalAccess(for: definition),
                unregister: {
                    #if DEBUG
                    let started = Date()
                    print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) begin")
                    defer { print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) returned seconds=\(Date().timeIntervalSince(started))") }
                    #endif
                    if let destination = incomingDestination(for: definition) {
                        let store = try incomingStore.get()
                        try await Task.detached { try store.setAdmission(destination, enabled: false) }.value
                    }
                    try await definition.continuingSurfaceGroup.endOwned()
                    continuingStatus.errors[definition.id] = nil
                    try await definition.onUnregister?()
                    #if DEBUG
                    print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) feature-hook-complete")
                    #endif
                    let context = MiniAppContext(id: definition.id)
                    await context.removeAllOwnedNotifications()
                    try context.replaceNotificationCategories(with: [])
                    #if DEBUG
                    print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) notifications-complete spotlight-begin")
                    #endif
                    try await MiniAppSpotlightNamespace(context: context).deleteAll(from: .default())
                    #if DEBUG
                    print("MINIAPP_UNREGISTER owner=\(definition.id.rawValue) spotlight-complete")
                    #endif
                },
                enable: {
                    try MiniAppContext(id: definition.id).replaceNotificationCategories(with: definition.notificationCategories)
                    if let destination = incomingDestination(for: definition) {
                        let store = try incomingStore.get()
                        try await Task.detached { try store.setAdmission(destination, enabled: true) }.value
                    }
                }
            )
        }
        let result = MiniAppManagement(
            registrations: registrations, defaults: managementDefaults, consents: consents,
            coordinator: MiniAppRestoreCoordinator.shared,
            storageKey: MiniAppManagement.defaultStorageKey,
            onStatusChange: { _, _ in
                WidgetCenter.shared.reloadAllTimelines()
                ControlCenter.shared.reloadAllControls()
            }
        )
        AppSceneRouting.windows.bootstrapSuspendedOwners(all.filter { !result.isEnabled($0.id) }.map(\.id))
        do {
            try incomingStore.get().publish(all.filter { result.isEnabled($0.id) }.compactMap(incomingDestination))
        } catch { incomingCatalogError = error.localizedDescription }
        return result
    }

    static func incomingDestination(for definition: MiniAppDefinition) -> MiniAppIncomingDestination? {
        guard let provider = definition.incoming else { return nil }
        return .init(id: definition.id, title: definition.title, typeIdentifiers: provider.typeIdentifiers)
    }

    private static func incomingRemoval(for definition: MiniAppDefinition) -> MiniAppRemovalProvider? {
        guard definition.incoming != nil else { return definition.removal }
        let store = incomingStore
        let owner = definition.id
        let original = definition.removal
        return MiniAppRemovalProvider(id: owner,
            dataDescription: [original?.dataDescription, "未取込みの共有データ"].compactMap { $0 }.joined(separator: "、")) {
                try await original?.removeData()
                let inbox = try store.get()
                try await Task.detached { try inbox.removeOwnedData(for: owner) }.value
            }
    }

    static func makeLifecycleDispatcher() -> MiniAppLifecycleDispatcher {
        var handlers: [@MainActor (MiniAppHostPhase) -> Void] = [{ phase in
            if phase == .active { reconcileContinuingSurfaces() }
        }]
        for definition in all {
            guard let handler = definition.onHostPhaseChange else { continue }
            let gated: @MainActor (MiniAppHostPhase) -> Void = { phase in
                if management.isEnabled(definition.id), launchState.errors[definition.id] == nil { handler(phase) }
            }
            handlers.append(gated)
        }
        return MiniAppLifecycleDispatcher(handlers: handlers)
    }

    static func makeSceneActivityDispatcher() -> MiniAppSceneActivityDispatcher {
        var handlers: [MiniAppSceneActivityDispatcher.Registration] = []
        for definition in all {
            guard let handler = definition.onSceneActivityChange else { continue }
            handlers.append(.init(id: definition.id) { activity in
                if management.isEnabled(definition.id), launchState.errors[definition.id] == nil { handler(activity) }
            })
        }
        return MiniAppSceneActivityDispatcher(handlers: handlers)
    }

    static var enabled: [MiniAppDefinition] { all.filter { management.isEnabled($0.id) } }
    static var registeredIDs: Set<MiniAppID> { Set(enabled.map(\.id)) }

    static func definition(for id: MiniAppID) -> MiniAppDefinition? {
        guard management.isEnabled(id), launchState.errors[id] == nil else { return nil }
        return all.first { $0.id == id }
    }

    private static func makeRegistry(
        _ miniApps: [MiniAppDefinition]
    ) -> [MiniAppDefinition] {
        precondition(
            Set(miniApps.map(\.id)).count == miniApps.count,
            "Mini-app IDs must be unique."
        )
        return miniApps
    }
}
#endif
