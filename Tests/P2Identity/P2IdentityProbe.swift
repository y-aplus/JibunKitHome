#if os(iOS)
import JibunKitCore
import SwiftUI

@MainActor
enum P2IdentityProbe {
    // The parent host replaces this factory with CloudKitExternalIdentityBackend
    // only after it has created an entitled CKContainer explicitly.
    private static let scope = try! MiniAppExternalContainer(identifier: "iCloud.com.example.JibunKit")
    static let ownerA = P2IdentityFeature(id: MiniAppID("p2-identity-a"), scope: scope)
    static let ownerB = P2IdentityFeature(id: MiniAppID("p2-identity-b"), scope: scope)
    static let definitions: [MiniAppDefinition] = [ownerA.definition, ownerB.definition]

    /// Signed diagnostic hosts use this factory after explicitly creating their CKContainer.
    static func features(backend: any MiniAppExternalIdentityBackend) -> [P2IdentityFeature] {
        [P2IdentityFeature(id: MiniAppID("p2-identity-a"), scope: scope, backend: backend),
         P2IdentityFeature(id: MiniAppID("p2-identity-b"), scope: scope, backend: backend)]
    }
    static func definitions(backend: any MiniAppExternalIdentityBackend) -> [MiniAppDefinition] {
        features(backend: backend).map(\.definition)
    }
}

@MainActor
final class P2IdentityFeature: ObservableObject {
    let id: MiniAppID
    let service: MiniAppExternalIdentityFeature
    @Published private(set) var status = "未接続（CloudKit container未注入）"
    private var identity: MiniAppExternalRecordIdentity?

    init(id: MiniAppID, scope: MiniAppExternalContainer,
         backend: any MiniAppExternalIdentityBackend = UnavailableExternalIdentityBackend(
            reason: "署名済みhostからCKContainerが注入されていません")) {
        self.id = id
        service = MiniAppExternalIdentityFeature(id: id, container: scope, backend: backend)
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(id: id, title: id.rawValue, systemImage: "externaldrive.connected.to.line.below",
                          lifetime: service.lifetime, removal: service.removal,
                          externalAccess: service.externalAccess) { [self] _ in
            P2IdentityView(feature: self)
        }
    }

    func save() { run { [self] in
        let identity = try await service.coordinator.identity(localID: "same-local-id")
        try await service.coordinator.save(identity, fields: ["value": id.rawValue])
        self.identity = identity; status = "native backend保存完了"
    } }
    func load() { run { [self] in
        let identity = try await service.coordinator.identity(localID: "same-local-id")
        let value = try await service.coordinator.load(identity)?.fields["value"] ?? "なし"
        self.identity = identity; status = "native backend読込: \(value)"
    } }
    func accountChanged() { run { [self] in
        let value = try await service.coordinator.accountDidChange()
        identity = nil; status = "account変更反映 generation=\(value.generation)"
    } }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await operation() }
            catch { status = "未接続/失敗: \(error)" }
        }
    }
}

private struct P2IdentityView: View {
    @ObservedObject var feature: P2IdentityFeature
    var body: some View {
        Form {
            Text(feature.status).accessibilityIdentifier("p2.identity.\(feature.id.rawValue).status")
            Text("注入backendの成功はCloudKit実通信成功とは扱いません。")
            Button("同名recordを保存") { feature.save() }
            Button("同名recordを読込") { feature.load() }
            Button("account変更を再照合") { feature.accountChanged() }
        }
    }
}
#endif
