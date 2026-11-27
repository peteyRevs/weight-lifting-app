import LedgerDomain
import WatchFeatureWorkout
#if os(watchOS)
    import WatchKit
#endif

/// The watch's haptics (F18): each haptic the watch plays (`WatchHapticPattern`) as the Taptic Engine's pattern of
/// that name. `WatchWorkoutStore` spaces them; a simulator plays nothing.
struct WatchHaptics: HapticsClient {
    func play(_ haptic: Haptic) async {
        #if os(watchOS)
            guard let pattern = WatchHapticPattern(haptic) else {
                return
            }
            await MainActor.run {
                let type: WKHapticType = switch pattern {
                case .click: .click
                case .notification: .notification
                case .success: .success
                }
                WKInterfaceDevice.current().play(type)
            }
        #endif
    }
}
