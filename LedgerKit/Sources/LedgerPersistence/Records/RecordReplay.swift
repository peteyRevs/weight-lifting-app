import Foundation
import GRDB
import LedgerDomain

/// Product decision #27: the stored personal records are a function of history.
///
/// The invariant every write keeps: the live `personal_record` rows, and each workout's `pr_count`, equal
/// `PersonalRecords.detect` replayed over the live finished workouts in history's order (by start, then id;
/// decision #26), each workout judged against the bests as they stood before it, with `achievedAt` its start.
///
/// A write changes the sets of one workout, so only the records of the exercises it touched, in that workout
/// and the ones after it, can change. `redetect` replays exactly those, in the write's transaction: the bests
/// before the workout from one aggregate query (`GRDBStatsQueries.bests`), then each later workout that holds a
/// record set of one of the exercises, in order, judged by `PersonalRecords.found` and raising the bests as it
/// goes.
///
/// - The walk reads, per workout, exercise and rep count, the heaviest weight and the best estimate: all that
///   decision #3 compares. It compares them as whole 10⁻⁷ g (ADR-007; they order as the weights do). Records
///   already stored as found are left out of the diff, so a write pays only for the records that change. A
///   History write stays inside `historyWrite` (250 ms), a new workout at the end inside 50 ms (architecture §15).
/// - A workout whose rows cannot be read is left out and logged, as the lists leave it out (orchestrator decision
///   on R-Q1): the write goes through, and the workout keeps its stored records until a write repairs it.
/// - `pr_count` is derived, like the records: a recount does not stamp `updated_at` (decision on R-SF2).
enum RecordReplay {}

/// Where a write starts, and what it touched.
extension RecordReplay {
    /// Where a workout stands in history's order: its start as stored (`started_at`), then its id text, which is
    /// how SQL compares the two columns.
    struct Position: Comparable {
        let startedAt: Double
        let id: String

        init(_ workout: WorkoutState) throws(LedgerPersistenceError) {
            startedAt = try ColumnCodec.seconds(workout.startedAt)
            id = ColumnCodec.text(workout.id)
        }

        init(startedAt: Double, id: String) {
            self.startedAt = startedAt
            self.id = id
        }

        static func < (lhs: Position, rhs: Position) -> Bool {
            (lhs.startedAt, lhs.id) < (rhs.startedAt, rhs.id)
        }
    }

    /// What a write to one workout must check again: the exercises it touched, as stored ids, from the earliest
    /// place the workout held or now holds.
    struct Scope {
        let workoutID: WorkoutID
        private(set) var exercises: [DatabaseValue] = []
        private(set) var start: Position?

        /// The scope of the stored workout `id` before a write: its place, when it is a live finished workout,
        /// and the exercises of its live rows and live records. Read leniently, as stored values, so that a
        /// write can still repair a damaged row of the workout.
        init(ofStored id: WorkoutID, in database: Database) throws {
            workoutID = id
            let key = ColumnCodec.text(id)
            let row = try Row.fetchOne(
                database,
                sql: """
                SELECT started_at FROM workout
                WHERE id = ? AND deleted_at IS NULL AND phase = 'finished' AND ended_at IS NOT NULL
                """,
                arguments: [key]
            )
            if let row, let startedAt = try? ColumnReader(row: row, table: "workout").date("started_at") {
                start = try Position(startedAt: ColumnCodec.seconds(startedAt), id: key)
            }
            exercises = try DatabaseValue.fetchAll(
                database,
                sql: """
                SELECT exercise_id FROM workout_exercise WHERE workout_id = :id AND deleted_at IS NULL
                UNION SELECT exercise_id FROM personal_record WHERE workout_id = :id AND deleted_at IS NULL
                ORDER BY 1
                """,
                arguments: ["id": key]
            )
        }

        /// The scope of an edit of one exercise's sets in the stored `workout`: that exercise, from the workout
        /// on. The workout's other exercises keep their sets, so their records cannot change.
        init(editing exerciseID: ExerciseID, of workout: WorkoutState) throws(LedgerPersistenceError) {
            workoutID = workout.id
            exercises = [ColumnCodec.text(exerciseID).databaseValue]
            start = try Position(workout)
        }

        /// Adds the workout as it is being written: its exercises, and its place if that is earlier.
        mutating func include(_ workout: WorkoutState) throws(LedgerPersistenceError) {
            let position = try Position(workout)
            start = start.map { min($0, position) } ?? position
            let added = workout.exercises.map { ColumnCodec.text($0.exerciseID).databaseValue }
            for exercise in added where !exercises.contains(exercise) {
                exercises.append(exercise)
            }
        }
    }
}

/// The replay.
extension RecordReplay {
    /// Makes the records of `scope`'s exercises, from its start onward, and the record counts of the workouts
    /// that hold them, what the invariant says, in the caller's transaction. Records that did not change keep
    /// their rows and stamps, and statements run in one order for one history. A workout the walk cannot read
    /// keeps its stored records (`Walk`).
    static func redetect(_ scope: Scope, in database: Database, at timestamp: String) throws {
        var recount = [ColumnCodec.text(scope.workoutID)]
        if let start = scope.start, !scope.exercises.isEmpty {
            let walk = try replay(scope.exercises, from: start, in: database)
            let stored = try storedRecords(of: scope.exercises, from: start, in: database)
                .filter { !walk.skipped.contains($0[1] as DatabaseValue) }
            let storedByID = Dictionary(
                stored.map { ($0[0] as DatabaseValue, $0) },
                uniquingKeysWith: { old, _ in old }
            )
            // Records already stored as found are left out of the diff: most of a replay's records do not change.
            let unchanged = Set(walk.records.filter { storedByID[$0.rowID.databaseValue].map($0.isStored) == true }
                .map(\.rowID.databaseValue))
            let changed = walk.records.filter { !unchanged.contains($0.rowID.databaseValue) }
            let replaced = stored.filter { !unchanged.contains($0[0] as DatabaseValue) }
            try PersonalRecordRecord.write(changed, over: replaced, in: database, at: timestamp)
            recount += changed.map { ColumnCodec.text($0.workoutID) }
            recount += replaced.compactMap { String.fromDatabaseValue($0[1]) }
        }
        try writeCounts(of: Set(recount).sorted(), in: database)
    }

    /// The walk over the workouts from `start` on, each judged against the bests before it.
    private static func replay(
        _ exercises: [DatabaseValue],
        from start: Position,
        in database: Database
    ) throws -> Walk {
        let bests = try GRDBStatsQueries.bests(for: exercises, before: start, in: database)
        var walk = Walk(bests: bests, judges: true, excluding: nil)
        try walk.walk(database, sql: walkSQL(exercises: exercises.count, from: true), exercises, start)
        return walk
    }

    /// The bests before `position`, a workout at a time: what `GRDBStatsQueries.bests` falls back to when its
    /// aggregate meets a damaged value, so that the damaged workout is left out rather than failing the write.
    static func walkedBests(
        for exercises: [DatabaseValue],
        before position: Position,
        in database: Database
    ) throws -> [ExerciseID: PersonalRecords.Tally<Int64>] {
        // Never the workout at `position` itself, even a stored copy that started earlier (review R-SF1).
        var walk = Walk(bests: [:], judges: false, excluding: position.id.databaseValue)
        try walk.walk(database, sql: walkSQL(exercises: exercises.count, from: false), exercises, position)
        return walk.bests
    }

    /// The walk: per workout (in history's order) from `position` on, or before it, exercise and rep count, the
    /// record sets' heaviest weight and best estimate, and the workout's columns.
    private static func walkSQL(exercises count: Int, from: Bool) -> String {
        """
        SELECT workout_exercise.exercise_id AS exercise_id, logged_set.reps AS reps,
            MAX(logged_set.weight_e7g) AS weight_e7g, MAX(logged_set.e1rm_e7g) AS e1rm_e7g,
            workout.id AS workout_id, workout.started_at AS started_at, workout.is_deload AS is_deload
        \(GRDBStatsQueries.recordSets)
            AND workout_exercise.exercise_id IN (\(databaseQuestionMarks(count: count)))
            AND \(from ? "(workout.started_at, workout.id) >= (?, ?)" : "(workout.started_at, workout.id) < (?, ?)")
        GROUP BY workout.id, workout_exercise.exercise_id, logged_set.reps
        ORDER BY workout.started_at, workout.id, workout_exercise.exercise_id, logged_set.reps
        """
    }

    /// The live records of `exercises` in the live finished workouts from `start` on, in id order, as
    /// `PersonalRecordRecord.contentColumns`: the rows `redetect` replaces.
    private static func storedRecords(
        of exercises: [DatabaseValue],
        from start: Position,
        in database: Database
    ) throws -> [Row] {
        let columns = PersonalRecordRecord.contentColumns.map { "personal_record.\($0)" }.joined(separator: ", ")
        return try Row.fetchAll(
            database,
            sql: """
            SELECT \(columns) FROM personal_record JOIN workout ON workout.id = personal_record.workout_id
            WHERE personal_record.deleted_at IS NULL
                AND personal_record.exercise_id IN (\(databaseQuestionMarks(count: exercises.count)))
                AND workout.deleted_at IS NULL AND workout.phase = 'finished' AND workout.ended_at IS NOT NULL
                AND (workout.started_at, workout.id) >= (?, ?)
            ORDER BY personal_record.id
            """,
            arguments: StatementArguments(exercises) + [start.startedAt, start.id]
        )
    }

    /// Makes the `pr_count` of each live workout of `ids` its number of live records, only where it changed.
    /// The count is derived, like the records (local-only), so it does not stamp `updated_at`: a replay that
    /// recounts a hundred workouts changes no synced row (orchestrator decision on R-SF2).
    private static func writeCounts(of ids: [String], in database: Database) throws {
        let count = "SELECT COUNT(*) FROM personal_record WHERE workout_id = workout.id AND deleted_at IS NULL"
        let stale = try String.fetchAll(
            database,
            sql: """
            SELECT id FROM workout
            WHERE id IN (\(databaseQuestionMarks(count: ids.count))) AND deleted_at IS NULL
                AND pr_count IS NOT (\(count))
            ORDER BY id
            """,
            arguments: StatementArguments(ids)
        )
        guard !stale.isEmpty else {
            return
        }
        try database.execute(
            sql: "UPDATE workout SET pr_count = (\(count)) WHERE id IN (\(databaseQuestionMarks(count: stale.count)))",
            arguments: StatementArguments(stale)
        )
    }
}
