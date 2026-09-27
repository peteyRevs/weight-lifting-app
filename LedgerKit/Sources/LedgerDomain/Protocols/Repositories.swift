import Foundation

// Repository and query protocols (architecture §7, engineering-standards §3). Declared here,
// implemented over GRDB in LedgerPersistence (F05), injected via swift-dependencies (F07).

/// The exercise catalog plus custom exercises (decision #12).
public protocol ExerciseRepository: Sendable {
    func all() async throws -> [Exercise]
    func exercise(id: ExerciseID) async throws -> Exercise?
    func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise]
    func save(_ exercise: Exercise) async throws
    /// Seeds or additively upgrades the bundled catalog (F03); never touches custom exercises.
    func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws
    func observeAll() -> AsyncStream<[Exercise]>
}

/// Programs (blocks) and which one is active.
public protocol ProgramRepository: Sendable {
    func active() async throws -> Program?
    func save(_ program: Program) async throws
    func setActive(_ id: ProgramID) async throws
    func delete(_ id: ProgramID) async throws
    func observeActive() -> AsyncStream<Program?>
}

/// Finished workouts (rule 31 materialisation; decision #11 history list and edits).
public protocol WorkoutRepository: Sendable {
    /// Rule 31: stores the finished workout, its summary and PRs, and the slots whose `misses`
    /// changed (rule 13), in one transaction.
    func materialize(_ workout: WorkoutState, summary: WorkoutSummary, prs: [PersonalRecord], slotUpdates: [Slot])
        async throws
    func workout(id: WorkoutID) async throws -> WorkoutState?
    func recent(limit: Int) async throws -> [WorkoutState]
    func workouts(in range: Range<Date>) async throws -> [WorkoutState]
    func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws
    func delete(id: WorkoutID) async throws
    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]>
}

/// User preferences (single row).
public protocol SettingsRepository: Sendable {
    func load() async throws -> Settings
    func save(_ settings: Settings) async throws
    func observe() -> AsyncStream<Settings>
}

/// History aggregates (spec §6.1 "History", §7.7; decisions #3, #4, #15).
public protocol StatsQueries: Sendable {
    /// Spec §6.3 "Last" line.
    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance?
    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)?
    func bestE1RM(exerciseID: ExerciseID) async throws -> Weight?
    /// Decision #4: the best e1RM per week, keyed by `WeekCalendar.isoWeekKey(for:)`.
    func e1RMByWeek(exerciseID: ExerciseID, lastWeeks: Int, calendar: WeekCalendar) async throws -> [WeekKey: Weight]
    /// Rule 34 / decision #15.
    func weeklyVolume(in range: Range<Date>) async throws -> Volume
    /// Rule 35 / decision #15.
    func sessionsCompleted(in range: Range<Date>) async throws -> Int
    func sessionCount(exerciseID: ExerciseID) async throws -> Int
    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord]
    func recentlyLogged(limit: Int) async throws -> [ExerciseID]
}
