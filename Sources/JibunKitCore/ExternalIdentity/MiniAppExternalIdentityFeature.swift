import Foundation

/// Standard Feature wiring: runtime stop closes external admission and management
/// removal deletes only this owner's CloudKit zone.
@MainActor
public final class MiniAppExternalIdentityFeature {
    public let id: MiniAppID
    public let coordinator: MiniAppExternalIdentityCoordinator
    public let lifetime: MiniAppFeatureLifetime
    public lazy var removal = MiniAppRemovalProvider(
        id: id,
        dataDescription: "このFeatureが所有する外部account data",
        removeData: { [coordinator] in try await coordinator.removeOwnedData() }
    )
    public lazy var externalAccess = MiniAppExternalAccess(
        id: id,
        prepare: { _ in },
        close: { [coordinator] in await coordinator.deactivate() },
        open: {},
        restoreLifecycle: { [coordinator] inner in
            MiniAppRestoreLifecycle(
                stop: {
                    await coordinator.deactivate()
                    try await inner?.stop()
                },
                resume: { try await inner?.resume() },
                recoverAfterFailedStop: inner?.recoverAfterFailedStop
            )
        }
    )

    public init(id: MiniAppID, container: MiniAppExternalContainer,
                backend: any MiniAppExternalIdentityBackend) {
        self.id = id
        let coordinator = MiniAppExternalIdentityCoordinator(owner: id, container: container, backend: backend)
        self.coordinator = coordinator
        lifetime = MiniAppFeatureLifetime(id: id) { @MainActor [coordinator] runtime in
            try await coordinator.connect(to: runtime)
        }
    }
}
