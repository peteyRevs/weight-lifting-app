import LedgerDomain
#if canImport(UIKit) && os(iOS)
    import UIKit
#endif

/// The iPhone's haptics (F10 S6): each of the engine's haptics as one of the system's feedback patterns.
/// A logged set is a firm tap; the end of a rest is the warning pattern, which is felt as two; a finished
/// workout and a new record are the success pattern. A device that has no Taptic Engine plays nothing.
///
/// The generators are made when a haptic is played and not kept ready: a set is logged minutes apart, and
/// a generator kept prepared holds the Taptic Engine awake.
struct LiveHaptics: HapticsClient {
    func play(_ haptic: Haptic) async {
        #if canImport(UIKit) && os(iOS)
            await MainActor.run {
                switch haptic {
                case .setLogged:
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                case .restOver:
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                case .personalRecord, .workoutFinished:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        #endif
    }
}
