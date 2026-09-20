#if os(iOS)
import JibunKitCore

@MainActor
enum MiniAppWindowOwnership {
    static func externalAccess(for definition: MiniAppDefinition) -> MiniAppExternalAccess {
        let owner = definition.id
        let registry = AppSceneRouting.windows
        let inner = definition.effectiveExternalAccess
        return MiniAppExternalAccess(id: owner, prepare: { enabled in
            try inner?.prepare(enabled)
        }, close: {
            await registry.suspendAndRelease(owner: owner)
            try await inner?.close()
        }, open: {
            try await inner?.open()
            _ = await registry.resume(owner: owner)
        }, restoreLifecycle: { lifecycle in
            let session = WindowRestoreSession(owner: owner, registry: registry,
                inner: inner?.restoreLifecycle(lifecycle) ?? lifecycle,
                canResume: { MiniAppRegistry.management.isEnabled(owner) })
            return .init(stop: { try await session.stop() }, resume: { try await session.resume() },
                         recoverAfterFailedStop: { try await session.recover() })
        })
    }

    static func restoreLifecycle(for definition: MiniAppDefinition) -> MiniAppRestoreLifecycle {
        let owner = definition.id
        let session = WindowRestoreSession(owner: owner, registry: AppSceneRouting.windows,
            inner: definition.effectiveRestoreLifecycle,
            canResume: { MiniAppRegistry.management.isEnabled(owner) })
        return .init(stop: { try await session.stop() }, resume: { try await session.resume() },
                     recoverAfterFailedStop: { try await session.recover() })
    }
}

/// One instance per prepared restore, preserving an independently disabled
/// owner's admission rather than unconditionally reopening it on recovery.
actor WindowRestoreSession {
    private let owner: MiniAppID
    private let registry: MiniAppWindowSceneRegistry
    private let inner: MiniAppRestoreLifecycle?
    private let canResume: @MainActor @Sendable () -> Bool
    private var wasSuspended = false

    init(owner: MiniAppID, registry: MiniAppWindowSceneRegistry,
         inner: MiniAppRestoreLifecycle?, canResume: @escaping @MainActor @Sendable () -> Bool) {
        self.owner = owner; self.registry = registry; self.inner = inner; self.canResume = canResume
    }

    func stop() async throws {
        wasSuspended = await registry.isSuspended(owner: owner)
        await registry.suspendAndRelease(owner: owner)
        try await inner?.stop()
    }

    func resume() async throws {
        try await inner?.resume()
        let allowed = await canResume()
        if !wasSuspended && allowed { await registry.resume(owner: owner) }
    }

    func recover() async throws {
        try await inner?.recoverAfterFailedStop?()
        let allowed = await canResume()
        if !wasSuspended && allowed { await registry.resume(owner: owner) }
    }
}
#endif
