import LedgerDesign
import SwiftUI

/// A past workout's detail, drawn from its model: a scroll view around `WorkoutDetailPage`, on the ground, under the
/// pushed screen's navigation bar and its back button. The whole screen scrolls, its heading too, as an exercise's
/// history does; it has no pinned part of its own. That is its one layout at every text size.
struct WorkoutDetailScreen: View {
    let model: WorkoutDetailModel
    let send: (HistoryRoute) -> Void
    /// The alert's "Delete".
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            WorkoutDetailPage(model: model, send: send, onDelete: onDelete)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LedgerColor.ground)
    }
}

/// N10: a workout this app can't read, in place of its detail: a scroll view around `UnreadableWorkoutPage`, on the
/// ground, with "Delete workout" still offered.
struct UnreadableWorkout: View {
    let model: WorkoutDetailModel.Unreadable
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            UnreadableWorkoutPage(model: model, onDelete: onDelete)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LedgerColor.ground)
    }
}
