import LedgerDomain

/// Where the History tab asks the app to go. A route is an intent, never a navigation call: `LedgerAppKit` resolves
/// it (architecture §4).
public nonisolated enum HistoryRoute: Hashable, Sendable {
    /// A workout's detail (F13), pushed on the stack of the tab that asked for it (F13 question 1, built to A).
    case workout(WorkoutID)
    /// The Today tab: the empty list's "Go to Today" (F13 question 7, built to A).
    case today
}
