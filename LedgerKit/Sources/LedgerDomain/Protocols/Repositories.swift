import Foundation

// Repository and query protocols (architecture §7, engineering-standards §3). Declared here,
// implemented over GRDB in LedgerPersistence (F05), injected via swift-dependencies (F07).

/// The exercise catalog plus custom exercises (decision #12).
public protocol ExerciseRepository: Sendable {
    /// Every live exercise, in `ExerciseSearch` name order (the name's key, then the id).
    func all() async throws -> [Exercise]
    func exercise(id: ExerciseID) async throws -> Exercise?
    /// The live exercises that `ExerciseSearch.matches` the query (decision #23), with `equipment` and the
    /// primary muscle `muscle` when given, in name order.
    func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise]
    /// Inserts or overwrites the exercise; a saved exercise is the lifter's, so catalog upgrades leave it.
    func save(_ exercise: Exercise) async throws
    /// Seeds the bundled catalog (F03) when `version` is above the applied one: new ids are inserted and live
    /// catalog rows it lists are refreshed in place (decision #24). Never touches custom or deleted exercises.
    func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws
    /// `all()` now, then after every change that alters it.
    func observeAll() -> AsyncStream<[Exercise]>
}

/// Programs (blocks) and which one is active.
public protocol ProgramRepository: Sendable {
    func active() async throws -> Program?
    /// Saves the program whole (weeks, days, slots, misses), re-validated through its `init`s; when active,
    /// every other program becomes inactive. An id used twice, or held by another program, throws
    /// `duplicateIdentifier`; a failed save writes nothing.
    func save(_ program: Program) async throws
    /// Makes the program the one active one; one that is not saved, or is deleted, throws `missingRow`.
    func setActive(_ id: ProgramID) async throws
    /// Soft-deletes the program and everything in it, which also makes it inactive; saving it again brings it
    /// back. An unknown id does nothing.
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
