#if os(iOS)
import SwiftUI
import UIKit

/// A full-screen Feature presentation can hide the host without disconnecting
/// its scene. Tie registration to the mounted root and its actual UIWindowScene,
/// not SwiftUI onDisappear or a temporary removal from the window hierarchy.
struct MiniAppSceneConnection: UIViewRepresentable {
    let connect: @MainActor () -> Void
    let disconnect: @MainActor () -> Void
    var connectScene: (@MainActor (UIWindowScene) -> Void)? = nil

    func makeUIView(context: Context) -> ConnectionView {
        ConnectionView(connect: connect, disconnect: disconnect, connectScene: connectScene)
    }

    func updateUIView(_ view: ConnectionView, context: Context) {
        view.connect = connect
        view.disconnect = disconnect
        view.connectScene = connectScene
    }

    static func dismantleUIView(_ view: ConnectionView, coordinator: ()) {
        view.detach()
    }

    @MainActor
    final class ConnectionView: UIView {
        var connect: @MainActor () -> Void
        var disconnect: @MainActor () -> Void
        var connectScene: (@MainActor (UIWindowScene) -> Void)?
        private weak var observedScene: UIWindowScene?
        private var connected = false
        private let notifications: NotificationCenter

        init(connect: @escaping @MainActor () -> Void,
             disconnect: @escaping @MainActor () -> Void,
             notifications: NotificationCenter = .default,
             connectScene: (@MainActor (UIWindowScene) -> Void)? = nil) {
            self.connect = connect
            self.disconnect = disconnect
            self.notifications = notifications
            self.connectScene = connectScene
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // UIKit removes the presenting view during a fullScreen modal.
            // nil here does not imply scene disconnection or root destruction.
            guard let scene = window?.windowScene else { return }
            if observedScene !== scene {
                detach()
                observedScene = scene
                notifications.addObserver(self, selector: #selector(sceneDisconnected),
                    name: UIScene.didDisconnectNotification, object: scene)
                notifications.addObserver(self, selector: #selector(sceneActivated),
                    name: UIScene.didActivateNotification, object: scene)
            }
            establishConnection()
        }

        func detach() {
            notifications.removeObserver(self)
            observedScene = nil
            endConnection()
        }

        @objc private func sceneDisconnected(_ notification: Notification) {
            endConnection()
        }

        @objc private func sceneActivated(_ notification: Notification) {
            establishConnection()
        }

        private func establishConnection() {
            guard !connected, observedScene != nil else { return }
            connected = true
            connect()
            if let observedScene { connectScene?(observedScene) }
        }

        private func endConnection() {
            guard connected else { return }
            connected = false
            disconnect()
        }
    }
}
#endif
