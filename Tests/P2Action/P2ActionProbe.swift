#if os(iOS)
import JibunKitCore

enum P2ActionProbe {
    static let alpha = MiniAppIncomingDestination(id: MiniAppID("p2-action-alpha"), title: "Action Alpha", typeIdentifiers: ["public.text"])
    static let beta = MiniAppIncomingDestination(id: MiniAppID("p2-action-beta"), title: "Action Beta", typeIdentifiers: ["public.url"])
}
#endif
