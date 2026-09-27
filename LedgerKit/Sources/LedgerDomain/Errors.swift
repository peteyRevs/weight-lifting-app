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
