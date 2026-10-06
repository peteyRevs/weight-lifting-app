import Foundation

/// Why a `Program` could not be constructed (spec §6.1, rule 4).
public enum ProgramValidationError: Error, Equatable, Sendable {
    /// Rule 4: a block has at least 2 weeks.
    case tooFewWeeks(count: Int)
    /// Week indices must be exactly 0, 1, … n − 1 (no gaps, no duplicates).
    case nonContiguousWeeks(indices: [Int])
    /// A week schedules a day template that is not in `Program.days`.
    case danglingSchedule(weekIndex: Int, dayTemplateID: DayTemplateID)
}

/// Why a `Slot` could not be constructed: one case per violated range in rules 1–3 and 6.
public enum SlotValidationError: Error, Equatable, Sendable {
    /// Rule 3: sets per slot 1…12.
    case setsOutOfRange(Int)
    /// Rule 2: template reps 1…30.
    case repsOutOfRange(Int)
    /// Rule 2: `repsHi` 2…40.
    case repsHiOutOfRange(Int)
    /// Rule 2: `repsHi` is always greater than `reps`.
    case repsHiNotAboveReps(reps: Int, repsHi: Int)
    /// Rule 3: RPE 5…10 in 0.5 steps.
    case rpeOutOfRange(Decimal)
    /// Rule 3: rest 30…300 s in 15 s steps.
    case restOutOfRange(seconds: Int)
    /// Spec §6.1: `drop` is 0 or 1.
    case dropSetsOutOfRange(Int)
    /// Rule 6: start load minimum 0.
    case negativeStartLoad(Weight)
    /// A weight step must be positive.
    case nonPositiveStep(Weight)
}

/// Why `SessionBuilder.build` could not build a session (spec §7.3).
public enum SessionBuilderError: Error, Equatable, Sendable {
    /// `weekIndex` is not one of the program's weeks (the block has ended or not started).
    case weekOutOfRange(Int)
    /// The day template is not one of the program's days.
    case dayNotInProgram(DayTemplateID)
    /// A slot references an exercise missing from the `exercises` lookup.
    case unknownExercise(ExerciseID)
}

/// Why the bundled exercise catalog could not be loaded (F03 criterion 1). `ExerciseCatalog.seed()`
/// throws on the first malformed entry; it never skips one.
public enum CatalogError: Error, Equatable, Sendable {
    /// The resource is not in the module bundle.
    case missingResource(String)
    /// The JSON is malformed, or an entry is missing a key or has a value of the wrong type or an
    /// unknown enum case. Carries the decoder's description, which names the entry's index.
    case unreadable(String)
    /// Two entries share an id.
    case duplicateID(ExerciseID)
    /// A name or alias repeats another entry's name or alias, ignoring case (criterion 4).
    case duplicateName(String)
    /// The name, short name or an alias is empty or has leading or trailing whitespace.
    case invalidText(ExerciseID)
    /// A secondary muscle repeats the primary muscle or another secondary muscle.
    case invalidMuscles(ExerciseID)
    /// The start load in `Units` is negative or not a multiple of the equipment's default step.
    case invalidStartLoad(ExerciseID, Units)
    /// `loadKind: bodyweight` must go with bodyweight equipment and a zero load in both units, and
    /// a zero load needs that `loadKind`.
    case loadKindMismatch(ExerciseID)
    /// Fewer than two alternatives, the exercise itself, or a repeated alternative (criterion 3).
    case invalidAlternatives(ExerciseID)
    /// An alternative's id is not in the catalog.
    case unknownAlternative(ExerciseID, alternative: ExerciseID)
    /// An alternative has a different movement pattern (criterion 3).
    case alternativePatternMismatch(ExerciseID, alternative: ExerciseID)
}

/// Why `ProgramEditing.removeLastWeek` refused to shorten the block (rule 4; F11 criterion 4).
public enum ProgramEditError: Error, Equatable, Sendable {
    /// Rule 4: a block has at least 2 weeks.
    case minimumTwoWeeks
    /// The block's last week holds a finished workout. `weekNumber` is one-based, as the message prints it.
    case weekHasLoggedSessions(weekNumber: Int)
}
