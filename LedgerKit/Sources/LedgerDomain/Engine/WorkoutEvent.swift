import Foundation

/// One thing that happened to a live workout (ADR-004). `WorkoutEngine` folds these into a
/// `WorkoutState`.
///
/// Events address an exercise by its index in the `started` snapshot and a set by its `SetID`.
/// A live workout never adds, removes or reorders exercises (it only gains sets), so both mean the
/// same thing on every device.
///
/// **Clock rule (ADR-004 amendment).** A payload time (`doneAt`, `tappedAt`, `restStarted.endsAt`,
/// `endedAt`) is the originating device's clock at the action. The envelope's `wallClock` is only the
/// hybrid-logical-clock ordering stamp: the reducer never reads it as the time of an action, and
/// compares a payload time with it only to reject an absurd one (`EventEnvelope.isWellFormed`).
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
    /// Rule 9 / decision #7: "+30s" adds `amount`, as the lifter meant it. The originating device, which
    /// knows what its screen showed, decides:
    /// - `extendsShownRest` is `true` when it showed a rest running (`RestTimer.remaining(at: now)` above
    ///   zero); the engine then extends the state's rest, whatever any timestamp says;
    /// - otherwise, or when the state has no rest, the engine starts a fresh rest of `amount` at
    ///   `tappedAt`, the device's clock at the tap ("+30s" at zero restarts a 30 s rest).
    case restExtended(amount: Duration, extendsShownRest: Bool, tappedAt: Date)
    /// Rule 9: "Skip".
    case restSkipped
    /// Rule 10: terminal; the workout is saved.
    case finished(endedAt: Date)
    /// Rule 10: terminal; the workout is dropped.
    case discarded(endedAt: Date)
}
