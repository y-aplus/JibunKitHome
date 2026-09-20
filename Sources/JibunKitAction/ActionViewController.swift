import UIKit

@MainActor
final class ActionViewController: MiniAppIncomingExtensionViewController {
    override var incomingPresentation: MiniAppIncomingExtensionPresentation { .action }
}
