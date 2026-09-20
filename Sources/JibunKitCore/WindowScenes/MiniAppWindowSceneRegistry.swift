import Foundation

/// The stable identity supplied by `UISceneSession.persistentIdentifier`.
/// It survives a scene connection being discarded and later restored.
public struct MiniAppWindowSessionID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A window session identifier cannot be empty.")
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) { self.init(rawValue: rawValue) }
}

/// Identifies one live connection of an OS window session. A restored session
/// keeps `sessionID` and receives a new `generation`.
public struct MiniAppWindowConnection: Hashable, Sendable {
    public let sessionID: MiniAppWindowSessionID
    public let generation: UUID

    public init(sessionID: MiniAppWindowSessionID, generation: UUID = UUID()) {
        self.sessionID = sessionID
        self.generation = generation
    }
}

public struct MiniAppWindowSceneSnapshot: Equatable, Sendable {
    public let connection: MiniAppWindowConnection
    public let phase: MiniAppSceneActivity.Phase
    public let selectedID: MiniAppID?

    public init(
        connection: MiniAppWindowConnection,
        phase: MiniAppSceneActivity.Phase,
        selectedID: MiniAppID?
    ) {
        self.connection = connection
        self.phase = phase
        self.selectedID = selectedID
    }
}

/// Process registry for OS window connections. Navigation values and Feature
/// view state stay in each WindowGroup root; the registry only targets it.
@MainActor
public final class MiniAppWindowSceneRegistry {
    public enum Delivery: Equatable, Sendable {
        case delivered(MiniAppWindowConnection)
        case notConnected
        case staleConnection(current: MiniAppWindowConnection?)
    }

    public typealias RouteHandler = @MainActor (MiniAppRoute?) -> Void

    private struct Scene {
        var snapshot: MiniAppWindowSceneSnapshot
        let route: RouteHandler
        var resources: [MiniAppID: [@MainActor () async -> Void]] = [:]
    }

    private struct PendingRelease {
        let id: UUID
        let owners: Set<MiniAppID>
        let task: Task<Void, Never>
    }

    private struct PendingOwnerRelease {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var scenes: [MiniAppWindowSessionID: Scene] = [:]
    private var pendingReleases: [MiniAppWindowSessionID: [PendingRelease]] = [:]
    private var suspendedOwners: Set<MiniAppID> = []
    private var pendingOwnerReleases: [MiniAppID: PendingOwnerRelease] = [:]

    public init() {}

    /// Initialization-only admission state for owners persisted as disabled.
    /// Call once on the MainActor before any scene connects; management prepare
    /// closures remain nonisolated and do not need to synchronously enter it.
    public func bootstrapSuspendedOwners<S: Sequence>(_ owners: S) where S.Element == MiniAppID {
        precondition(scenes.isEmpty && pendingReleases.isEmpty && pendingOwnerReleases.isEmpty)
        let ownerList = Array(owners)
        precondition(ownerList.allSatisfy(\.isValid))
        suspendedOwners.formUnion(ownerList)
    }

    /// Connects (or reconnects) one OS session. The new generation is published
    /// before old cleanup can suspend, so a reentrant transition can never be
    /// overwritten by the older call when its cleanup resumes.
    public func connect(
        sessionID: MiniAppWindowSessionID,
        phase: MiniAppSceneActivity.Phase,
        selectedID: MiniAppID?,
        route: @escaping RouteHandler
    ) async -> MiniAppWindowConnection {
        let inheritedReleases = pendingReleases[sessionID] ?? []
        let previous = scenes[sessionID]
        let connection = MiniAppWindowConnection(sessionID: sessionID)
        scenes[sessionID] = Scene(
            snapshot: .init(connection: connection, phase: phase, selectedID: selectedID),
            route: route
        )
        if let previous {
            await scheduleAndJoin(previous.resources, for: sessionID)
        }
        for release in inheritedReleases { await release.task.value }
        return connection
    }

    /// Rejects updates from an earlier connection of the same OS session.
    @discardableResult
    public func update(
        _ connection: MiniAppWindowConnection,
        phase: MiniAppSceneActivity.Phase,
        selectedID: MiniAppID?
    ) -> Bool {
        guard var scene = scenes[connection.sessionID], scene.snapshot.connection == connection else {
            return false
        }
        scene.snapshot = .init(connection: connection, phase: phase, selectedID: selectedID)
        scenes[connection.sessionID] = scene
        return true
    }

    public func snapshot(for sessionID: MiniAppWindowSessionID) -> MiniAppWindowSceneSnapshot? {
        scenes[sessionID]?.snapshot
    }

    public var connectedScenes: [MiniAppWindowSceneSnapshot] {
        scenes.values.map(\.snapshot)
    }

    /// Registers a scene-scoped resource. Feature-global work belongs to
    /// `MiniAppRuntime` and must not be registered here.
    @discardableResult
    public func onDisconnect(
        owner: MiniAppID,
        connection: MiniAppWindowConnection,
        _ cleanup: @escaping @MainActor () async -> Void
    ) -> Bool {
        guard owner.isValid, !suspendedOwners.contains(owner),
              var scene = scenes[connection.sessionID],
              scene.snapshot.connection == connection
        else { return false }
        scene.resources[owner, default: []].append(cleanup)
        scenes[connection.sessionID] = scene
        return true
    }

    /// Targets exactly one live connection. Passing an expected generation is
    /// required for callbacks which may outlive the connection that created them.
    @discardableResult
    public func open(
        _ route: MiniAppRoute?,
        in sessionID: MiniAppWindowSessionID,
        expected connection: MiniAppWindowConnection? = nil
    ) -> Delivery {
        guard let scene = scenes[sessionID] else {
            return connection == nil ? .notConnected : .staleConnection(current: nil)
        }
        guard connection == nil || connection == scene.snapshot.connection else {
            return .staleConnection(current: scene.snapshot.connection)
        }
        scene.route(route)
        return .delivered(scene.snapshot.connection)
    }

    /// Ends only this generation. Cleanup is owner-grouped but closing a window
    /// releases all resources in that window and never shuts down global runtimes.
    @discardableResult
    public func disconnect(_ connection: MiniAppWindowConnection) async -> Bool {
        guard let scene = scenes[connection.sessionID], scene.snapshot.connection == connection else {
            return false
        }
        scenes[connection.sessionID] = nil
        await scheduleAndJoin(scene.resources, for: connection.sessionID)
        return true
    }

    /// Closes admission for one Feature across every live window, atomically
    /// detaches its scene resources, and joins their cleanup. Keep the owner
    /// suspended through global lifetime shutdown and state deletion/restore.
    public func suspendAndRelease(owner: MiniAppID) async {
        precondition(owner.isValid)
        if let pending = pendingOwnerReleases[owner] {
            await pending.task.value
            return
        }
        suspendedOwners.insert(owner)
        let inheritedReleases = pendingReleases.values
            .flatMap { $0 }
            .filter { $0.owners.contains(owner) }
        var releases: [(MiniAppWindowSessionID, [MiniAppID: [@MainActor () async -> Void]])] = []
        for sessionID in scenes.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var scene = scenes[sessionID], let resources = scene.resources.removeValue(forKey: owner) else {
                continue
            }
            scenes[sessionID] = scene
            releases.append((sessionID, [owner: resources]))
        }
        let id = UUID()
        let task = Task { @MainActor [self] in
            for release in inheritedReleases { await release.task.value }
            for (sessionID, resources) in releases {
                await scheduleAndJoin(resources, for: sessionID)
            }
        }
        pendingOwnerReleases[owner] = .init(id: id, task: task)
        await task.value
        if pendingOwnerReleases[owner]?.id == id { pendingOwnerReleases[owner] = nil }
    }

    /// Reopens scene-resource admission after the existing management layer has
    /// restarted the Feature. It does not recreate resources automatically.
    @discardableResult
    public func resume(owner: MiniAppID) -> Bool {
        guard pendingOwnerReleases[owner] == nil else { return false }
        return suspendedOwners.remove(owner) != nil
    }

    public func isSuspended(owner: MiniAppID) -> Bool {
        suspendedOwners.contains(owner)
    }

    /// Joins cleanup already captured by connect/disconnect/owner suspension.
    /// Do not call this from one of the registered cleanup closures itself.
    public func waitForPendingCleanup(in sessionID: MiniAppWindowSessionID) async {
        let releases = pendingReleases[sessionID] ?? []
        for release in releases { await release.task.value }
    }

    private func scheduleAndJoin(
        _ resources: [MiniAppID: [@MainActor () async -> Void]],
        for sessionID: MiniAppWindowSessionID
    ) async {
        guard !resources.isEmpty else { return }
        let id = UUID()
        let task = Task { @MainActor in await Self.release(resources) }
        pendingReleases[sessionID, default: []].append(
            .init(id: id, owners: Set(resources.keys), task: task)
        )
        await task.value
        pendingReleases[sessionID]?.removeAll { $0.id == id }
        if pendingReleases[sessionID]?.isEmpty == true { pendingReleases[sessionID] = nil }
    }

    private static func release(_ resources: [MiniAppID: [@MainActor () async -> Void]]) async {
        for owner in resources.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            for cleanup in (resources[owner] ?? []).reversed() { await cleanup() }
        }
    }
}
