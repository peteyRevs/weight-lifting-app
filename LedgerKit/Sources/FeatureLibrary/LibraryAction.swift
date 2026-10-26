import LedgerDomain

/// What a tap on the Library means, as a value: the store applies it and decides nothing. Every action says what
/// becomes true, not what changes, so one drawn or applied twice gives what one application gives.
nonisolated enum LibraryAction: Hashable, Sendable {
    /// The search field holds this text, as the lifter typed it: the one action a view makes itself.
    case setQuery(String)
    /// The muscle chip chosen is this one; nil is "All".
    case setMuscle(ExerciseSearch.MuscleFilter?)
    /// The equipment chip chosen is this one; nil is "All".
    case setEquipment(Equipment?)
    /// "Clear filters": the query is emptied and both chips go back to "All".
    case clearFilters
    /// "New exercise": the sheet that creates one is up (F12 S3).
    case newExercise
    /// The sheet "New exercise" opened is down: cancelled, saved, or taken down by the system.
    case newExerciseClosed
    /// A tap that asks the app to go somewhere: an exercise's row.
    case route(LibraryRoute)
}
