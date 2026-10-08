import Foundation
import LedgerDomain

/// Everything `ExercisePickerPresentation.make(_:)` reads. The store fills it; the presentation reaches for
/// nothing else, so the same input always gives the same model.
nonisolated struct ExercisePickerInput: Sendable {
    /// The stored exercises, the catalog's and the lifter's own, in any order: the list is put in order by
    /// `ExerciseSearch`.
    var exercises: [Exercise]
    /// The exercises the day being edited already holds. Such an exercise is marked and can still be picked:
    /// a day may hold an exercise twice.
    var dayExercises: Set<ExerciseID> = []
    /// The search field's text as the lifter typed it. A blank one matches every exercise.
    var query: String = ""
    /// The muscle chip chosen, or nil for "All".
    var muscle: ExerciseSearch.MuscleFilter?
    /// The equipment chip chosen, or nil for "All". A kind of equipment that has no chip is read as "All".
    var equipment: Equipment?
    /// The exercises picked, in the order picked. One that is no longer stored is ignored, and one that
    /// comes twice counts once, at its first place.
    var picks: [ExerciseID] = []
    var locale: Locale
}
