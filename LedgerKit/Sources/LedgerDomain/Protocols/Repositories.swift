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
    /// Inserts or overwrites the exercise; a saved exercise is the lifter's, so catalog upgrades leave it. A
    /// name or short name holding U+0000 is refused (`nulInText`) and nothing is saved.
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
    /// `duplicateIdentifier`; a name or tag holding U+0000 throws `nulInText`; a failed save writes nothing.
    func save(_ program: Program) async throws
    /// Makes the program the one active one; one that is not saved, or is deleted, throws `missingRow`.
    func setActive(_ id: ProgramID) async throws
    /// Soft-deletes the program and everything in it, which also makes it inactive; saving it again brings it
    /// back. An unknown id does nothing.
    func delete(_ id: ProgramID) async throws
    func observeActive() -> AsyncStream<Program?>
}

/// Finished workouts (rule 31 materialisation; decision #11 history list and edits). `WorkoutRepositoryContract`
/// in LedgerTestSupport pins what follows, for every implementation.
///
/// A workout's date, for ordering and for ranges, is when it started (`startedAt`; product decision #26), so a
/// session begun at 11:30 pm and finished after midnight is the earlier day's, and that week's.
public protocol WorkoutRepository: Sendable {
    /// Rule 31: stores the finished workout with its exercises and sets, `prs` as its personal records, and
    /// the misses of `slotUpdates` (rule 13), in one transaction: all of it or nothing.
    ///
    /// - It is an upsert keyed by the workout's id: materialising the same workout again changes nothing, a
    ///   changed one replaces its exercises, sets and records, and a deleted one comes back.
    /// - Nothing of `summary` is stored: it is `WorkoutEngine.summary(workout, prs:)`, computed from the other
    ///   arguments.
    /// - Of each slot in `slotUpdates` only `misses` is written, replacing the slot's stored misses whole, so
    ///   build each slot from the program as stored now. A slot that is not stored is skipped.
    /// - `workout.programUpdates` is not applied.
    ///
    /// Throws `notFinished` unless the workout is `.finished` with an `endedAt`; `duplicateIdentifier` for an
    /// exercise or set id used twice, or held by another stored workout (even a deleted one), and for a record
    /// that names another workout; `nulInText` for a name or tag holding U+0000.
    func materialize(_ workout: WorkoutState, summary: WorkoutSummary, prs: [PersonalRecord], slotUpdates: [Slot])
        async throws
    /// The stored workout, or `nil`. A history read resets the live-only fields: no `cursor`, no `rest`, no
    /// `programUpdates`, no exercise's `lastPerformance`, and `autoRest` true.
    func workout(id: WorkoutID) async throws -> WorkoutState?
    /// The `limit` workouts that started last, newest first (of two that started together, the smaller id first);
    /// none when `limit` is below 1.
    func recent(limit: Int) async throws -> [WorkoutState]
    /// The workouts that started in `range` (its upper bound excluded), newest first, as `recent`.
    func workouts(in range: Range<Date>) async throws -> [WorkoutState]
    /// Replaces the sets of one exercise of a stored workout. Everything computed from sets follows; the
    /// workout's personal records are left as they are, and can be stale afterwards, until the F05 follow-up re-checks
    /// them in this write (product decision #27). An exercise of no stored
    /// workout throws `missingRow`; a set id used twice, or held by another workout, `duplicateIdentifier`.
    func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws
    /// Removes the workout, with its records, from every read and every stats query; materialising it again
    /// brings it back. An unknown id does nothing.
    func delete(id: WorkoutID) async throws
    /// `recent(limit:)` now, then after every change that alters it, and for no other write.
    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]>
}

/// User preferences (single row).
public protocol SettingsRepository: Sendable {
    func load() async throws -> Settings
    func save(_ settings: Settings) async throws
    func observe() -> AsyncStream<Settings>
}

/// History aggregates (spec §6.1 "History", §7.7; decisions #3, #4, #15), over the workouts a
/// `WorkoutRepository` stores. `StatsQueriesContract` in LedgerTestSupport pins what follows.
///
/// Every query counts done sets of stored workouts only, and a workout's date is when it started (product
/// decision #26). Which kinds of set count differs by query (product decision #25):
/// - the "Last" line counts `.working` sets;
/// - the bests (`bestSet`, `bestE1RM`, `e1RMByWeek`) count `.working` and `.added` sets, those that can set a
///   personal record (decision #25; warm-ups and drop sets never count);
/// - volume, `sessionCount` and `recentlyLogged` count every kind.
public protocol StatsQueries: Sendable {
    /// Spec §6.3 "Last" line: the most recent workout (by start) with a done working set of the exercise (of two
    /// that started together, the smaller id), as its start date, the number of such sets, and the load and reps of the
    /// heaviest of them (of two as heavy, the one with more reps). Rows of one workout that perform the
    /// exercise count together. `nil` when there is none.
    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance?
    /// The heaviest set of the exercise, and of two as heavy the one with more reps; `nil` when there is none.
    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)?
    /// The best Brzycki estimate over sets of at most 12 reps (decision #4); `nil` when there is none.
    func bestE1RM(exerciseID: ExerciseID) async throws -> Weight?
    /// Decision #4: the best e1RM of each of the last `lastWeeks` weeks of `calendar`, the current one
    /// included, keyed by `WeekCalendar.isoWeekKey(for:)`. A week with no estimate has no key; `lastWeeks`
    /// below 1 gives none.
    func e1RMByWeek(exerciseID: ExerciseID, lastWeeks: Int, calendar: WeekCalendar) async throws -> [WeekKey: Weight]
    /// Rule 34 / decision #15: Σ weight × reps over the done sets of the workouts that started in `range`.
    func weeklyVolume(in range: Range<Date>) async throws -> Volume
    /// Rule 35 / decision #15: how many workouts started in `range`, with or without a done set.
    func sessionsCompleted(in range: Range<Date>) async throws -> Int
    /// How many workouts hold a done set of the exercise; one that performs it in two rows counts once.
    func sessionCount(exerciseID: ExerciseID) async throws -> Int
    /// The records the exercise's stored workouts set, newest first by `achievedAt`; of two achieved together,
    /// the estimated 1RM before the weight at reps.
    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord]
    /// The `limit` exercises with a done set in the most recent workouts, the latest first, and exercises of
    /// one workout in id order; none when `limit` is below 1.
    func recentlyLogged(limit: Int) async throws -> [ExerciseID]
}
