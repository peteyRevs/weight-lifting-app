import LedgerDomain

/// Where Today asks the app to go. A route is an intent, never a navigation call: `LedgerAppKit` resolves it
/// (architecture §4).
public nonisolated enum TodayRoute: Hashable, Sendable {
    /// Start the session of `day` in program week `weekIndex` (0 is the block's first): F10's start use case,
    /// which resumes a live workout of the same program, week and day (rule 17).
    case startWorkout(program: ProgramID, weekIndex: Int, day: DayTemplateID)
    /// Back to the live workout: F10's cover.
    case resumeWorkout
    /// A finished workout's detail, in the History tab (F13).
    case openWorkout(WorkoutID)
    /// The program builder with week `weekIndex` selected (F11).
    case editWeek(program: ProgramID, weekIndex: Int)
    /// The Program tab, where the next block starts (F24).
    case openProgram
    /// Settings (F14), from the gear in the header (product decision #19).
    case settings
    /// Setting up a program (F08).
    case setUpProgram
}
