import Foundation

/// One thing that happened to a live workout (ADR-004). `WorkoutEngine` folds these into a
/// `WorkoutState`.
///
/// Events address an exercise by its index in the `started` snapshot and a set by its `SetID`.
/// A live workout never adds, removes or reorders exercises (it only gains sets), so both mean the
/// same thing on every device. Events that need a time carry it; every other event happens at its
/// envelope's `wallClock`.
///
/// Labels name the state field they write (`doneAt`, `exerciseID`, `endedAt`) rather than ADR-004's
/// `at:`/`to:`/`by:`, which SwiftLint's `identifier_name` rejects as too short.
public enum WorkoutEvent: Hashable, Codable, Sendable {
    /// Rule 1: the initial snapshot from `SessionBuilder` (phase `.live`).
    case started(WorkoutState)
    /// Rule 11: move the cursor to this row if it exists and is not done.
    case exerciseSelected(exerciseIndex: Int, setIndex: Int)
    /// Rule 3: the set was ticked done at `doneAt` with this weight and these reps.
    case setLogged(exerciseIndex: Int, setID: SetID, weight: Weight, reps: Reps, doneAt: Date)
    /// Rule 4: the set was un-ticked.
    case setUnlogged(exerciseIndex: Int, setID: SetID)
    /// Rule 5: a stepper edit; a `nil` field is unchanged.
    case setTargetChanged(exerciseIndex: Int, setID: SetID, weight: Weight?, reps: Reps?)
    /// Rule 6: "+ Add set". The originating device generates `set.id`.
    case setAdded(exerciseIndex: Int, set: LoggedSet)
    /// Rule 7: "Repeat last" writes this weight and these reps into every set of the exercise.
    case allSetsRepeated(exerciseIndex: Int, weight: Weight, reps: Reps)
    /// Rule 8 / decision #13: the exercise is replaced by `exerciseID` (named `name`) for this workout,
    /// and also in the program when `alsoUpdateProgram` is on.
    case exerciseSwapped(exerciseIndex: Int, exerciseID: ExerciseID, name: String, alsoUpdateProgram: Bool)
    /// Rule 9: a rest that ends at the absolute time `endsAt`, so every device shows the same countdown.
    case restStarted(endsAt: Date, total: Duration)
    /// Rule 9 / decision #7: "+30s" adds `amount`.
    case restExtended(amount: Duration)
    /// Rule 9: "Skip".
    case restSkipped
    /// Rule 10: terminal; the workout is saved.
    case finished(endedAt: Date)
    /// Rule 10: terminal; the workout is dropped.
    case discarded(endedAt: Date)
}
