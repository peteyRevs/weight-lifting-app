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
///   decision #3 compares. It compares them as whole 10⁻⁷ g (ADR-007; they order as the weights do), so the
///   worst case, a typo fixed in the first of 400 workouts of one lift, stays inside the stats budget.
/// - History is read as the stats queries read it: a damaged value that an aggregate returns throws by name, and
///   the write stores nothing, rather than judge a record against history it cannot read.
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
    /// Adds a row of the walk, or of the bests before it, to `tally`: an exercise's record sets at one rep count
    /// (column 1, `reps`), at their heaviest (column 2, `weight_e7g`) and best estimate (column 3, `e1rm_e7g`),
    /// in whole 10⁻⁷ g. Read by index, as strictly as `ColumnReader` reads: GRDB finds a column by name with a
    /// case-insensitive search, and for the worst case's 4,800 rows that cost 3 ms of 45 (Debug, host).
    static func add(_ row: Row, to tally: inout PersonalRecords.Tally<Int64>) throws(LedgerPersistenceError) {
        func integer(_ index: Int, _ column: String) throws(LedgerPersistenceError) -> Int64 {
            guard case let .int64(value) = (row[index] as DatabaseValue).storage else {
                throw .malformedColumn("logged_set.\(column)")
            }
            return value
        }
        guard let reps = try Int(exactly: integer(1, "reps")).flatMap(Reps.init) else {
            throw .malformedColumn("logged_set.reps")
        }
        let estimate = (row[3] as DatabaseValue).isNull ? nil : try integer(3, "e1rm_e7g")
        try tally.add(integer(2, "weight_e7g"), reps: reps, estimate: estimate)
    }

    /// Makes the records of `scope`'s exercises, from its start onward, and the record counts of the workouts
    /// that hold them, what the invariant says, in the caller's transaction. Records that did not change keep
    /// their rows and stamps (`SyncedRecord.write`), and statements run in one order for one history.
    static func redetect(_ scope: Scope, in database: Database, at timestamp: String) throws {
        var recount = [ColumnCodec.text(scope.workoutID)]
        if let start = scope.start, !scope.exercises.isEmpty {
            let records = try replay(scope.exercises, from: start, in: database)
            let stored = try storedRecords(of: scope.exercises, from: start, in: database)
            try PersonalRecordRecord.write(records, over: stored, in: database, at: timestamp)
            recount += records.map { ColumnCodec.text($0.workoutID) }
            recount += stored.compactMap { String.fromDatabaseValue($0["workout_id"]) }
        }
        try writeCounts(of: Set(recount).sorted(), in: database, at: timestamp)
    }

    /// The records `PersonalRecords.found` finds for `exercises` in the workouts from `start` on, each judged
    /// against the bests before it.
    private static func replay(
        _ exercises: [DatabaseValue],
        from start: Position,
        in database: Database
    ) throws -> [PersonalRecordRecord] {
        var walk = try Walk(bests: GRDBStatsQueries.bests(for: exercises, before: start, in: database))
        let rows = try Row.fetchCursor(
            database,
            sql: walkSQL(exercises: exercises.count),
            arguments: StatementArguments(exercises) + [start.startedAt, start.id]
        )
        while let row = try rows.next() {
            try walk.add(row)
        }
        try walk.close()
        return walk.records
    }

    /// The walk: per workout from the start on (in history's order), exercise and rep count, the record sets'
    /// heaviest weight and best estimate, and the workout's columns.
    private static func walkSQL(exercises count: Int) -> String {
        """
        SELECT workout_exercise.exercise_id AS exercise_id, logged_set.reps AS reps,
            MAX(logged_set.weight_e7g) AS weight_e7g, MAX(logged_set.e1rm_e7g) AS e1rm_e7g,
            workout.id AS workout_id, workout.started_at AS started_at, workout.is_deload AS is_deload
        \(GRDBStatsQueries.recordSets)
            AND workout_exercise.exercise_id IN (\(databaseQuestionMarks(count: count)))
            AND (workout.started_at, workout.id) >= (?, ?)
        GROUP BY workout.id, workout_exercise.exercise_id, logged_set.reps
        ORDER BY workout.started_at, workout.id, workout_exercise.exercise_id, logged_set.reps
        """
    }

    /// The live records of `exercises` in the live finished workouts from `start` on, in id order: the rows
    /// `redetect` replaces.
    private static func storedRecords(
        of exercises: [DatabaseValue],
        from start: Position,
        in database: Database
    ) throws -> [Row] {
        try Row.fetchAll(
            database,
            sql: """
            SELECT personal_record.* FROM personal_record JOIN workout ON workout.id = personal_record.workout_id
            WHERE personal_record.deleted_at IS NULL
                AND personal_record.exercise_id IN (\(databaseQuestionMarks(count: exercises.count)))
                AND workout.deleted_at IS NULL AND workout.phase = 'finished' AND workout.ended_at IS NOT NULL
                AND (workout.started_at, workout.id) >= (?, ?)
            ORDER BY personal_record.id
            """,
            arguments: StatementArguments(exercises) + [start.startedAt, start.id]
        )
    }

    /// Makes the `pr_count` of each live workout of `ids` its number of live records. Only a count that changed
    /// is written, so a write that changes no record runs no `UPDATE`.
    private static func writeCounts(of ids: [String], in database: Database, at timestamp: String) throws {
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
            sql: """
            UPDATE workout SET pr_count = (\(count)), updated_at = ?
            WHERE id IN (\(databaseQuestionMarks(count: stale.count)))
            """,
            arguments: [timestamp] + StatementArguments(stale)
        )
    }
}

/// The replay's walk over its rows, in order. The rows of one workout's exercise come together: their tally is
/// complete at the next workout or exercise, when it is judged against the bests before the workout (unless the
/// workout is a deload) and then raises them.
private struct Walk {
    private(set) var bests: [ExerciseID: PersonalRecords.Tally<Int64>]
    private(set) var records: [PersonalRecordRecord] = []
    private var group: Group?
    private var own = PersonalRecords.Tally<Int64>()

    /// One workout's rows of one exercise: their keys as stored, and the first row, which holds the workout's
    /// columns.
    private struct Group {
        let workoutKey: DatabaseValue
        let exerciseKey: DatabaseValue
        let exercise: ExerciseID
        let row: Row
    }

    init(bests: [ExerciseID: PersonalRecords.Tally<Int64>]) {
        self.bests = bests
    }

    mutating func add(_ row: Row) throws {
        let workoutKey: DatabaseValue = row[4] // the columns of `walkSQL(exercises:)`, by index as in `add`
        let exerciseKey: DatabaseValue = row[0]
        if group?.workoutKey != workoutKey || group?.exerciseKey != exerciseKey {
            try close()
            let exercise: ExerciseID = try ColumnReader(row: row, table: "workout_exercise").identifier("exercise_id")
            group = Group(workoutKey: workoutKey, exerciseKey: exerciseKey, exercise: exercise, row: row.copy())
        }
        try RecordReplay.add(row, to: &own)
    }

    /// Judges the open group, if any, and closes it.
    mutating func close() throws {
        guard let group else {
            return
        }
        let read = ColumnReader(row: group.row, table: "workout")
        if try !read.flag("is_deload") {
            let found = PersonalRecords.found(own, over: bests[group.exercise] ?? .init())
            if !found.isEmpty {
                let workoutID: WorkoutID = try read.identifier("workout_id")
                let startedAt = try ColumnCodec.seconds(read.date("started_at"))
                records += found.map { PersonalRecordRecord($0, of: group.exercise, in: workoutID, at: startedAt) }
            }
        }
        bests[group.exercise, default: .init()].add(own)
        self.group = nil
        own = PersonalRecords.Tally()
    }
}
