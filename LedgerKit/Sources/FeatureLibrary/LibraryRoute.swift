import LedgerDomain

/// Where the Library asks the app to go. A route is an intent, never a navigation call: `LedgerAppKit` resolves it
/// (architecture §4).
public nonisolated enum LibraryRoute: Hashable, Sendable {
    /// The exercise's history (F12 S2), pushed on the stack of the tab that asked for it.
    case exercise(ExerciseID)
}
