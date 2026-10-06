import LedgerDomain

/// Where the Program screens ask the app to go. A route is an intent, never a navigation call: `LedgerAppKit`
/// resolves it (architecture §4).
public nonisolated enum ProgramRoute: Hashable, Sendable {
    /// The Day editor on `day`, showing program week `weekIndex` (0 is the block's first): the week selected
    /// in the builder, which a pushed screen with a store of its own cannot read.
    case day(DayTemplateID, weekIndex: Int)
    /// Back from the Day editor: "Done", or its day is gone.
    case closeDay
}
