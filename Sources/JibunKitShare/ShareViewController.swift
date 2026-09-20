import UIKit

@MainActor
final class ShareViewController: MiniAppIncomingExtensionViewController {
    override var incomingPresentation: MiniAppIncomingExtensionPresentation { .share }
}
