import Foundation
import GRDB
import LedgerDomain

/// A finished workout as the rows of its four tables (`workout`, `workout_exercise`, `logged_set`,
/// `personal_record`). Saving writes the first three over the stored rows in the caller's transaction (`write`);
/// reading assembles them into `WorkoutState`s (`fetch`). The records are derived: `RecordReplay` writes them
/// after the workout's rows, in the same transaction (product decision #27).
struct WorkoutRows {
    let workoutID: WorkoutID
    private var workout: WorkoutRecord?
    private var exercises: [WorkoutExerciseRecord] = []
    private var sets: [LoggedSetRecord] = []
    /// Whether writing soft-deletes the workout's personal records (a delete); otherwise they are left to
    /// `RecordReplay`.
    private var deletesRecords = false

    /// The rows of `state`.
    init(_ state: WorkoutState) {
        workoutID = state.id
        workout = WorkoutRecord(state)
        exercises = state.exercises.enumerated().map { WorkoutExerciseRecord($1, workoutID: state.id, position: $0) }
        sets = state.exercises.flatMap { exercise in
            exercise.sets.enumerated().map { LoggedSetRecord($1, workoutExerciseID: exercise.id, position: $0) }
        }
    }

    /// No rows at all: writing them soft-deletes the workout and everything in it, its records included.
    init(deleting id: WorkoutID) {
        workoutID = id
        deletesRecords = true
    }

    /// Makes the workout's live rows these, in the caller's transaction: new and changed rows are upserted,
    /// unchanged ones left alone, and live rows the workout no longer has soft-deleted
    /// (`SyncedRecord.write(_:over:in:at:)`). So writing the same workout twice changes nothing the second
    /// time, and writing a deleted workout brings it back.
    ///
    /// The children are diffed against every live row under the workout's id, whatever the state of the rows
    /// above them. A workout or exercise row soft-deleted on its own (a sync applies a parent's deletion before
    /// its children's) then cannot hide live rows the workout no longer has: the write soft-deletes them (S3-2).
    func write(_ database: Database, at timestamp: String) throws {
        // Every live row is read before any is written: soft-deleting an exercise first would hide its sets.
        let children = Selection.stored(workoutID)
        let storedWorkout = try Selection.one(workoutID).rows(Query.workouts, in: database)
        let storedExercises = try children.rows(Query.exercises, in: database)
        let storedSets = try children.rows(Query.setsUnderAnyExercise, in: database)
        let storedRecords = deletesRecords ? try children.rows(Query.records, in: database) : []
        try refuseOtherWorkoutsIDs(in: database)
        // Parents first, so every foreign key an insert names exists.
        try WorkoutRecord.write(workout.map { [$0] } ?? [], over: storedWorkout, in: database, at: timestamp)
        try WorkoutExerciseRecord.write(exercises, over: storedExercises, in: database, at: timestamp)
        try LoggedSetRecord.write(sets, over: storedSets, in: database, at: timestamp)
        if deletesRecords {
            try PersonalRecordRecord.write([], over: storedRecords, in: database, at: timestamp)
        }
    }

    /// Throws `duplicateIdentifier` when an exercise or a set of this workout has an id that another stored
    /// workout holds, live or deleted. Upserting it would move that row into this workout, and the other
    /// workout would lose it (the takeover S2's review B1 found for programs).
    private func refuseOtherWorkoutsIDs(in database: Database) throws {
        try refuse(
            exercises.map(\.rowID),
            of: WorkoutExerciseRecord.databaseTableName,
            heldBy: Query.exerciseOwners,
            in: database
        )
        try refuse(sets.map(\.rowID), of: LoggedSetRecord.databaseTableName, heldBy: Query.setOwners, in: database)
    }

    /// Throws `duplicateIdentifier("table id")` for the first of `ids` that `ownersSQL` finds under another
    /// workout.
    private func refuse(_ ids: [String], of table: String, heldBy ownersSQL: String, in database: Database) throws {
        guard !ids.isEmpty else {
            return
        }
        let taken = try String.fetchOne(
            database,
            sql: ownersSQL + "(\(databaseQuestionMarks(count: ids.count))) ORDER BY 1 LIMIT 1",
            arguments: StatementArguments([ColumnCodec.text(workoutID)] + ids)
        )
        if let taken {
            throw LedgerPersistenceError.duplicateIdentifier("\(table) \(taken)")
        }
    }

    /// The live workouts `selection` picks, newest first (by `started_at`, then id; product decision #26), each with
    /// its live exercises
    /// and sets in their stored order.
    ///
    /// A workout is one aggregate: a damaged row anywhere in it, or a case a later version added, makes the
    /// whole workout unreadable. When `strict`, that throws (`LedgerPersistenceError`); otherwise the workout
    /// is logged and left out, and stays stored, so one bad workout never hides the history around it.
    ///
    /// That includes a workout or exercise row whose id is not stored as text. SQL compares the id with its
    /// children's text `…_id` and finds none, so reading on would return a workout with no exercises, or an
    /// exercise with no sets (S3-3).
    static func fetch(_ selection: Selection, in database: Database, strict: Bool) throws -> [WorkoutState] {
        // Children are grouped by their parent's id as stored, so grouping never fails on a damaged id.
        let exerciseRows = try Dictionary(grouping: selection.rows(Query.exercises, in: database)) { row in
            row["workout_id"] as DatabaseValue
        }
        let setRows = try Dictionary(grouping: selection.rows(Query.sets, in: database)) { row in
            row["workout_exercise_id"] as DatabaseValue
        }
        let read = { (row: Row) in
            try requireTextID(of: row, in: WorkoutRecord.databaseTableName)
            var state = try WorkoutRecord(row: row).workout
            state.exercises = try exerciseRows[row["id"], default: []].map { exerciseRow in
                try requireTextID(of: exerciseRow, in: WorkoutExerciseRecord.databaseTableName)
                var exercise = try WorkoutExerciseRecord(row: exerciseRow).exercise
                exercise.sets = try setRows[exerciseRow["id"], default: []].map { try LoggedSetRecord(row: $0).set }
                return exercise
            }
            return state
        }
        return try selection.rows(Query.workouts, in: database).compactMap { row in
            try strict ? read(row) : row.readable(as: WorkoutRecord.databaseTableName, read)
        }
    }

    /// Throws `malformedColumn("table.id")` unless the row's id is stored as text, in the spelling the app
    /// writes (`uuidString`, uppercase).
    private static func requireTextID(of row: Row, in table: String) throws(LedgerPersistenceError) {
        guard case let .string(text) = (row["id"] as DatabaseValue).storage else {
            throw .malformedColumn("\(table).id")
        }
        // A uuid in another spelling (lowercase) parses, but SQL compares the text: it matches no child (S3-5).
        if let uuid = UUID(uuidString: text), uuid.uuidString != text {
            throw .malformedColumn("\(table).id")
        }
    }
}

extension WorkoutRows {
    /// Which workouts a read or a write is about: a subquery that selects their ids, and its arguments.
    struct Selection {
        fileprivate let sql: String
        fileprivate let arguments: StatementArguments

        static func one(_ id: WorkoutID) -> Selection {
            Selection(
                sql: "SELECT id FROM workout WHERE id = ? AND deleted_at IS NULL",
                arguments: [ColumnCodec.text(id)]
            )
        }

        /// The workout row `id`, live or deleted: what a write diffs the workout's children against.
        static func stored(_ id: WorkoutID) -> Selection {
            Selection(sql: "SELECT id FROM workout WHERE id = ?", arguments: [ColumnCodec.text(id)])
        }

        /// The `limit` workouts that started last (product decision #26); none when `limit` is not positive
        /// (SQLite reads a negative `LIMIT` as no limit at all).
        static func recent(limit: Int) -> Selection {
            Selection(
                sql: """
                SELECT id FROM workout WHERE deleted_at IS NULL AND phase = 'finished' AND ended_at IS NOT NULL
                ORDER BY started_at DESC, id LIMIT ?
                """,
                arguments: [max(0, limit)]
            )
        }

        /// The workouts that started in `range` (product decision #26).
        static func started(in range: Range<Date>) -> Selection {
            Selection(
                sql: """
                SELECT id FROM workout
                WHERE deleted_at IS NULL AND phase = 'finished' AND ended_at IS NOT NULL
                    AND started_at >= ? AND started_at < ?
                """,
                arguments: [
                    range.lowerBound.timeIntervalSinceReferenceDate,
                    range.upperBound.timeIntervalSinceReferenceDate
                ]
            )
        }

        /// The rows `query` selects for these workouts.
        fileprivate func rows(_ query: (String) -> String, in database: Database) throws -> [Row] {
            try Row.fetchAll(database, sql: query(sql), arguments: arguments)
        }
    }

    /// The live rows of the workouts a `Selection`'s subquery picks, children in their stored order (ties by
    /// id, so the order is total), and the owner checks of `refuseOtherWorkoutsIDs`.
    private enum Query {
        static func workouts(_ selection: String) -> String {
            "SELECT * FROM workout WHERE id IN (\(selection)) ORDER BY started_at DESC, id"
        }

        static func exercises(_ selection: String) -> String {
            """
            SELECT * FROM workout_exercise WHERE workout_id IN (\(selection)) AND deleted_at IS NULL
            ORDER BY position, id
            """
        }

        static func sets(_ selection: String) -> String {
            """
            SELECT logged_set.* FROM logged_set
            JOIN workout_exercise ON workout_exercise.id = logged_set.workout_exercise_id
            WHERE workout_exercise.workout_id IN (\(selection)) AND workout_exercise.deleted_at IS NULL
                AND logged_set.deleted_at IS NULL
            ORDER BY logged_set.position, logged_set.id
            """
        }

        /// Every live set under the workouts' exercise rows, live or deleted: what a write diffs its sets against.
        static func setsUnderAnyExercise(_ selection: String) -> String {
            """
            SELECT logged_set.* FROM logged_set
            JOIN workout_exercise ON workout_exercise.id = logged_set.workout_exercise_id
            WHERE workout_exercise.workout_id IN (\(selection)) AND logged_set.deleted_at IS NULL
            ORDER BY logged_set.position, logged_set.id
            """
        }

        static func records(_ selection: String) -> String {
            "SELECT * FROM personal_record WHERE workout_id IN (\(selection)) AND deleted_at IS NULL ORDER BY id"
        }

        /// The ids, among those that follow in `IN (…)`, of exercises or sets of stored workouts other than
        /// the first argument, deleted rows and workouts included. A row whose `workout_id` names no stored
        /// workout is damage, not another workout's, so a save repairs it (as S2-5 for programs).
        static let exerciseOwners = """
        SELECT id FROM workout_exercise WHERE workout_id IS NOT ? AND workout_id IN (SELECT id FROM workout) AND id IN
        """
        static let setOwners = """
        SELECT logged_set.id FROM logged_set
        JOIN workout_exercise ON workout_exercise.id = logged_set.workout_exercise_id
        WHERE workout_exercise.workout_id IS NOT ? AND workout_exercise.workout_id IN (SELECT id FROM workout)
            AND logged_set.id IN
        """
    }
}
