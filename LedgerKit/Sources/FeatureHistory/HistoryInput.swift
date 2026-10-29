import Foundation
import LedgerDomain

/// What `HistoryPresentation.make(_:)` reads, once each time a source changes. The store fills it; the presentation
/// reaches for nothing else, so the same input always gives the same model.
nonisolated struct HistoryInput: Sendable {
    /// `WorkoutRepository.historyEntries()`: newest first.
    var entries: [HistoryEntry]
    var units: Units
    /// The lifter's first day of the week (decision #15): where the list's weeks begin.
    var weekStart: Weekday
    /// Says which year is the current one: a week in another year names its year.
    var now: Date
    /// Its time zone says which day and week a workout started in.
    var calendar: Calendar
    var locale: Locale
}
