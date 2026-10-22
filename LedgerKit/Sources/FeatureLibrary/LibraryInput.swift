import Foundation
import LedgerDomain

/// What `LibraryPresentation.rows(_:)` reads, once each time a source changes. The store fills it; the
/// presentation reaches for nothing else, so the same input always gives the same rows.
nonisolated struct LibraryInput: Sendable {
    /// The live exercises, the catalog's and the lifter's own, in any order: the list is put in order by
    /// `ExerciseSearch`.
    var exercises: [Exercise]
    /// `StatsQueries.recentlyLogged(limit:)`'s exercises, the latest first. One that is not live is left out.
    var recent: [ExerciseID] = []
    /// How many sessions hold each recent exercise (`sessionCount(exerciseID:)`).
    var sessions: [ExerciseID: Int] = [:]
    /// Each exercise's best set (`bestSets()`); one with no entry has no PR.
    var bestSets: [ExerciseID: BestSet] = [:]
    var units: Units
    var locale: Locale
}

/// What `LibraryPresentation.make(_:filter:)` reads on each keystroke and each tap of a chip: the search field's
/// text as typed and the two chips, nil for "All".
nonisolated struct LibraryFilter: Equatable, Sendable {
    var query = ""
    var muscle: ExerciseSearch.MuscleFilter?
    /// A kind of equipment that has no chip is read as "All".
    var equipment: Equipment?
}
