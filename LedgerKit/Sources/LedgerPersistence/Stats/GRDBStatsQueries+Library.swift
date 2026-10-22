import Foundation
import GRDB
import LedgerDomain

/// The Library's reads (F12).
public extension GRDBStatsQueries {
    /// `bestSet(exerciseID:)` of every exercise, in one read: per exercise, the heaviest done `.working` or
    /// `.added` set of a live finished workout, and of two as heavy the one with more reps (product decision
    /// #25). One pass over the counted sets, ranked within each exercise. An exercise with no such set has no
    /// entry.
    ///
    /// A row this app cannot read (an id or a weight a later version wrote, or damage) is logged and left out,
    /// as `recentlyLogged` leaves one out, so one bad row never hides every other exercise's best.
    func bestSets() async throws -> [ExerciseID: BestSet] {
        let sql = """
        SELECT id, weight_e7g, reps FROM (
            SELECT workout_exercise.exercise_id AS id, logged_set.weight_e7g AS weight_e7g, logged_set.reps AS reps,
                ROW_NUMBER() OVER (
                    PARTITION BY workout_exercise.exercise_id
                    ORDER BY logged_set.weight_e7g DESC, logged_set.reps DESC
                ) AS place
            \(Self.recordSets)
        )
        WHERE place = 1
        """
        let table = WorkoutExerciseRecord.databaseTableName
        let rows = try await queue.read { database in
            try Row.fetchAll(database, sql: sql).compactMap { row in
                // The row's `id` is the exercise's, so a row left out is logged under the exercise (review n2).
                row.readable(as: ExerciseRecord.databaseTableName) { row -> (ExerciseID, BestSet) in
                    let set = ColumnReader(row: row, table: "logged_set")
                    let id: ExerciseID = try ColumnReader(row: row, table: table).identifier("id")
                    return try (id, BestSet(weight: Weight(e7g: set.integer("weight_e7g")), reps: set.reps("reps")))
                }
            }
        }
        return Dictionary(rows) { first, _ in first }
    }

    /// Each live finished workout with a done set of the exercise, newest first as `recent` lists them (of two that
    /// started together, the smaller id first), with its done sets of every kind in row and set order (F12 S2,
    /// N9). One read through `idx_wex_exercise_workout`. A set that cannot be read throws, as `bestSet` does.
    func exerciseSessions(exerciseID: ExerciseID) async throws -> [ExerciseSession] {
        let sql = """
        SELECT logged_set.*, workout.id AS session_id, workout.started_at AS started_at
        \(Self.doneSets) AND workout_exercise.exercise_id = ?
        ORDER BY workout.started_at DESC, workout.id, workout_exercise.position, logged_set.position
        """
        return try await queue.read { database in
            var sessions: [ExerciseSession] = []
            for row in try Row.fetchAll(database, sql: sql, arguments: [ColumnCodec.text(exerciseID)]) {
                let workout = ColumnReader(row: row, table: WorkoutRecord.databaseTableName)
                let id: WorkoutID = try workout.identifier("session_id")
                let set = try LoggedSetRecord(row: row).set
                if sessions.last?.workoutID == id {
                    sessions[sessions.count - 1].sets.append(set)
                } else {
                    let startedAt = try workout.date("started_at")
                    sessions.append(ExerciseSession(workoutID: id, startedAt: startedAt, sets: [set]))
                }
            }
            return sessions
        }
    }
}
