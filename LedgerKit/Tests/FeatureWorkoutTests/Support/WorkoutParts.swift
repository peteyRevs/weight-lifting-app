#if DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import SwiftUI

    /// The cover's pinned header at its own height, on the screen's ground and inside its insets, with time
    /// standing still at the state's moment: what the header's references are taken from. The cover itself
    /// fills the screen, and has no height of its own for a reference. S5 stacks the page under it here
    /// (testing-strategy §2.6: the pinned parts and the page, in the screen's reading order).
    struct WorkoutParts: View {
        let preview: WorkoutPreview
        var send: (WorkoutAction) -> Void = { _ in }

        var body: some View {
            Group {
                if case let .workout(workout) = preview.model {
                    WorkoutHeader(model: workout.header, send: send)
                }
            }
            .padding(.horizontal, LedgerSpacing.screen)
            .padding(.vertical, LedgerSpacing.l)
            .background(LedgerColor.ground)
            .environment(\.workoutTimeline, .fixed(at: preview.now))
        }
    }
#endif
