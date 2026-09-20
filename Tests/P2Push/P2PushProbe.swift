#if os(iOS)
import JibunKitCore
import SwiftUI

@MainActor
enum P2PushProbe {
    static let coordinator = MiniAppRemotePushCoordinator.shared
    static let alpha = P2PushFeature(id: MiniAppID("p2-push-alpha"), server: "alpha.example.invalid")
    static let beta = P2PushFeature(id: MiniAppID("p2-push-beta"), server: "beta.example.invalid")
    static var definitions: [MiniAppDefinition] { [alpha.definition, beta.definition] }
}

@MainActor
final class P2PushFeature: ObservableObject {
    let id: MiniAppID
    @Published var status = "未接続"
    @Published var deliveries = 0
    private let server: String
    lazy var service = MiniAppRemotePushService(
        owner: id,
        identity: try! MiniAppRemotePushIdentity(server: server, account: "same-local-account"),
        coordinator: P2PushProbe.coordinator,
        onRegistration: { [weak self] event in self?.record(event) },
        onDelivery: { [weak self] message in
            guard let self else { return .noData }
            deliveries += 1
            status = "owner配送: \(message.destination ?? "root")"
            return .newData
        },
        onUnregister: { [weak self] _ in self?.status = "server登録解除済み" }
    )
    lazy var lifetime = MiniAppFeatureLifetime(id: id) { [weak self] runtime in
        guard let self else { return }
        try service.connect(to: runtime)
        status = "runtime接続済み"
    }

    init(id: MiniAppID, server: String) { self.id = id; self.server = server }

    var definition: MiniAppDefinition {
        MiniAppDefinition(id: id, title: "Push \(id.rawValue)", systemImage: "bell.badge",
                          lifetime: lifetime, onUnregister: { [weak self] in
                              guard let self else { return }
                              await service.unregister()
                          }, onHostLaunch: { [weak self] in
                              guard let self else { return }
                              service.prepareColdStart(lifetime: lifetime)
                          }) {
            [self] _ in P2PushView(feature: self)
        }
    }

    private func record(_ event: MiniAppRemotePushRegistrationEvent) {
        switch event {
        case .tokenChanged(_, let identity, _): status = "token登録: \(identity.server)"
        case .registrationFailed(let message, _): status = "APNs登録失敗: \(message)"
        case .ownerUnregistered: status = "server登録解除済み"
        }
    }
}

private struct P2PushView: View {
    @ObservedObject var feature: P2PushFeature
    var body: some View {
        Form {
            Text(feature.status).accessibilityIdentifier("p2.push.\(feature.id.rawValue).status")
            Text("配送 \(feature.deliveries)件")
            Text("APNs登録要求とdelegate callbackはhostが一度だけ接続します。")
        }
    }
}
#endif
