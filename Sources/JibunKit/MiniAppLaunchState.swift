#if os(iOS)
import JibunKitCore
import Observation

@MainActor @Observable
final class MiniAppLaunchState {
    private(set) var errors: [MiniAppID: String] = [:]
    var hostError: String?
    private var attempted: Set<MiniAppID> = []

    /// OS launch registrations cannot safely be repeated after partial success.
    /// A failed owner stays unavailable for this process; other owners proceed.
    func register(_ definitions: [MiniAppDefinition]) {
        for definition in definitions where attempted.insert(definition.id).inserted {
            do { try definition.onHostLaunch?() }
            catch {
                errors[definition.id] = String(describing: error)
                definition.lifetime?.recordLaunchRegistrationFailure(error)
            }
        }
    }
}
#endif
