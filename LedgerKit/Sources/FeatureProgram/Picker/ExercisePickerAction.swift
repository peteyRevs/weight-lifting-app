import LedgerDomain

/// What a tap on the exercise library means, as a value: the store applies it and decides nothing. Every
/// action says what becomes true, not what changes, so one drawn or applied twice gives what one
/// application gives.
nonisolated enum ExercisePickerAction: Hashable, Sendable {
    /// The search field holds this text, as the lifter typed it: the one action a view makes itself.
    case setQuery(String)
    /// The muscle chip chosen is this one; nil is "All".
    case setMuscle(ExerciseSearch.MuscleFilter?)
    /// The equipment chip chosen is this one; nil is "All".
    case setEquipment(Equipment?)
    /// The exercise is among the picks, at their end when it was not, or is not among them.
    case setPicked(Bool, exercise: ExerciseID)
    /// "Clear filters": the query is emptied and both chips go back to "All". The picks stay.
    case clearFilters
    /// "Add 3 exercises": for each id, in this order, draw a `SlotID` and build a slot with
    /// `DayEditing.newSlot`; queue the Day editor's `.slot(.add(slots), day:)`; empty the query and the picks,
    /// keep the two chips, and close the sheet.
    case add([ExerciseID])
    /// "Cancel": close the sheet and add nothing; empty the query and the picks and keep the two chips, as
    /// after "Add" (the prototype closes the sheet the same way for both).
    case cancel
}
