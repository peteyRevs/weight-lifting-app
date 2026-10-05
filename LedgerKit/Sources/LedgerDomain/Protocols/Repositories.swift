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
    /// `duplicateIdentifier`; a slot naming an exercise that is not stored throws `unknownExercise` (seed the
    /// catalog first; product decision #28); a name or tag holding U+0000 throws `nulInText`; a failed save writes
    /// nothing.
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
///
/// **Personal records are a function of history** (product decision #27). After every write, the stored records
/// equal `PersonalRecords.detect` replayed over the stored workouts in order (by start, then id), each workout
/// judged against the bests as they stood before it (`StatsQueries.bests(before:for:)`), with `achievedAt` its
/// start. Each write re-checks them, in its own transaction, for the exercises it touched, from the workout it
/// changed onward: so correcting a typo in an old workout removes the false record and gives a later workout
/// the record it then deserves. Callers never supply records.
public protocol WorkoutRepository: Sendable {
    /// Rule 31: stores the finished workout with its exercises and sets, the misses of `slotUpdates` (rule 13)
    /// and the program changes its swaps asked for (`workout.programUpdates`, decision #13), detects personal
    /// records again from it onward and, when `droppingLog`, drops the workout's event log
    /// (`WorkoutEventStore`), in one transaction: all of it or nothing. When it throws, nothing changed: no
    /// workout, no miss, no program change, and the log whole.
    ///
    /// - It is an upsert keyed by the workout's id: materialising the same workout again changes nothing, the
    ///   program included as long as it was not edited in between; a changed one replaces its exercises and
    ///   sets, and a deleted one comes back. A workout stored late, before others, takes its place in the
    ///   order, and the records of those after it follow.
    /// - Of each slot in `slotUpdates` only `misses` is written, replacing the slot's stored misses whole, so
    ///   build each slot from the program as stored now. A slot that is not stored is skipped.
    /// - Each entry of `workout.programUpdates` sets the exercise of one slot, and nothing else of it. It may
    ///   only touch a stored slot of the workout's own program (`source.programID`), and only name a stored
    ///   exercise: an entry of an ad-hoc workout, or one naming a slot that is not stored, a slot of another
    ///   program or an exercise that is not stored, is skipped. A skipped entry never fails the save.
    /// - An entry is applied by every materialisation: one made after the lifter changed that slot sets it
    ///   back to the swap's exercise. So store an older workout again without its `programUpdates`, as
    ///   without its slots.
    ///
    /// **The log.** A workout's log is that workout before it was saved (ADR-004 rule 5), and the save is what
    /// ends its use: that is why this repository may drop it. It drops that one log, never reads an envelope
    /// and never writes one; the caller has made sure the log is complete
    /// (`WorkoutEventStore.unreadableCount(for:)`).
    ///
    /// Returns whether this repository dropped the log with the save. `false` when `droppingLog` is false, and
    /// from a repository that holds no log, whose caller then compacts it in a second step. `true` says only
    /// that the log is gone from the repository's own database: nothing ties a repository to the event store
    /// a caller holds beside it, so a caller that holds one looks there before it takes the log for gone, as
    /// the session host does. Every implementation states which it is; there is no default.
    ///
    /// Throws `notFinished` unless the workout is `.finished` with an `endedAt`; `duplicateIdentifier` for an
    /// exercise or set id used twice, or held by another stored workout (even a deleted one); `nulInText` for a
    /// name or tag holding U+0000.
    func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog: Bool) async throws -> Bool
    /// The stored workout, or `nil`. A history read resets the live-only fields: no `cursor`, no `rest`, no
    /// `programUpdates`, no exercise's `lastPerformance`, and `autoRest` true.
    func workout(id: WorkoutID) async throws -> WorkoutState?
    /// The `limit` workouts that started last, newest first (of two that started together, the smaller id first);
    /// none when `limit` is below 1.
    func recent(limit: Int) async throws -> [WorkoutState]
    /// The workouts that started in `range` (its upper bound excluded), newest first, as `recent`.
    func workouts(in range: Range<Date>) async throws -> [WorkoutState]
    /// Replaces the sets of one exercise of a stored workout. Everything computed from sets follows, personal
    /// records included: that exercise's records are detected again from this workout onward, in the same
    /// transaction (product decision #27). An exercise of no stored workout throws `missingRow`; a set id used
    /// twice, or held by another workout, `duplicateIdentifier`.
    func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws
    /// Removes the workout, with its records, from every read and every stats query, and detects the records of
    /// its exercises again in the workouts after it; materialising it again brings it back. An unknown id does
    /// nothing.
    func delete(id: WorkoutID) async throws
    /// `recent(limit:)` now, then after every change that alters it, and for no other write.
    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]>
}

public extension WorkoutRepository {
    /// The save alone: `materialize(_:slotUpdates:droppingLog:)` that leaves the workout's log where it is.
    func materialize(_ workout: WorkoutState, slotUpdates: [Slot]) async throws {
        _ = try await materialize(workout, slotUpdates: slotUpdates, droppingLog: false)
    }
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
/// - the bests (`bestSet`, `bestE1RM`, `e1RMByWeek`, `bests(before:for:)`) count `.working` and `.added` sets,
///   those that can set a personal record (decision #25; warm-ups and drop sets never count);
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
    /// The records the exercise's stored workouts set, newest first by `achievedAt` (the workout's start); of two
    /// workouts that started together, the smaller id first (as `recent`); within a workout, the estimated 1RM
    /// before the weight at reps.
    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord]
    /// Product decision #27: the bests `PersonalRecords.detect` judges `workout` against, for each of
    /// `exerciseIDs`: those of the stored workouts that come before it, by start and then id (decision #26),
    /// never `workout` itself, stored or not (not even a stored copy that started earlier). A workout this app
    /// cannot read is left out. Counts the sets the other bests count (decision #25). An exercise with no such set
    /// has no entry. For the live "PR!" moment, pass the active workout, and detect with `now: startedAt`.
    func bests(before workout: WorkoutState, for exerciseIDs: Set<ExerciseID>) async throws -> PersonalRecords.Bests
    /// The `limit` exercises with a done set in the most recent workouts, the latest first, and exercises of
    /// one workout in id order; none when `limit` is below 1.
    func recentlyLogged(limit: Int) async throws -> [ExerciseID]
}
