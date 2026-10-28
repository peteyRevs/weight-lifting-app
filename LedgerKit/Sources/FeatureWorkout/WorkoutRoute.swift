import LedgerDomain

/// Why the workout's cover closed, for the app to follow (architecture §4): the cover closes itself, and the
/// app decides what the tabs under it show. The live workout is not carried: Today follows the session for
/// that, as the cover does.
public nonisolated enum WorkoutRoute: Hashable, Sendable {
    /// "Minimize": the workout is still live, and its time keeps counting (product decision #8).
    case minimized
    /// The workout is in history. Until S7 gives the cover its own save, only a workout finished somewhere
    /// else while the cover showed it ends this way.
    case saved(WorkoutID)
    /// The workout was discarded: nothing is live and nothing reached history.
    case discarded
    /// A row of the saved workout's receipt (F12 S3, N18; Pete's question 2, A): the workout is in history, as for
    /// `saved`, and the lifter asked for this exercise's history.
    case exercise(ExerciseID)
}
