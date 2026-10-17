import Foundation
import LedgerDomain

/// The rest notification (F10 S6; the type's comment says when it runs and why the host runs it). In a
/// file of its own for the host's length.
extension LocalWorkoutSessionActor {
    /// The rest notification's effects of one change, in the engine's order. The client cannot fail.
    func notify(_ effects: [Effect]) async {
        guard let notifications else {
            return
        }
        for effect in effects {
            switch effect {
            case let .scheduleRestNotification(endsAt):
                await notifications.scheduleRestOver(at: endsAt)
            case .cancelRestNotification:
                await notifications.cancelRestOver()
            case .haptic, .updateLiveActivity, .persist, .transmit, .materialize, .discardLog:
                break
            }
        }
    }
}
