#if DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import SwiftUI

    /// The cover's pinned header over its page, without the scroll view the screen puts the page in, on the
    /// screen's ground, with time standing still at the state's moment: what the VoiceOver trees and the
    /// references are taken from (testing-strategy §2.6: the pinned parts and the page, in the screen's
    /// reading order). The header is inset as `WorkoutScreen` insets it. A state that shows no workout
    /// (loading, failed) has no parts: its tree is read from the screen, which holds no scroll view then.
    ///
    /// `headerOnly` leaves the page out: the header at its own height, for its own references (S4).
    struct WorkoutParts: View {
        let preview: WorkoutPreview
        var headerOnly = false
        var send: (WorkoutAction) -> Void = { _ in }

        var body: some View {
            VStack(spacing: 0) {
                if case let .workout(workout) = preview.model {
                    WorkoutHeader(model: workout.header, send: send)
                        .padding(.horizontal, LedgerSpacing.screen)
                        .padding(.vertical, LedgerSpacing.l)
                    if !headerOnly {
                        WorkoutPage(model: workout.page, send: send)
                    }
                }
            }
            .background(LedgerColor.ground)
            .environment(\.workoutTimeline, .fixed(at: preview.now))
        }
    }
#endif
