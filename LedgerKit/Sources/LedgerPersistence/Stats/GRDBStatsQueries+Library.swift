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
                row.readable(as: table) { row -> (ExerciseID, BestSet) in
                    let set = ColumnReader(row: row, table: "logged_set")
                    let id: ExerciseID = try ColumnReader(row: row, table: table).identifier("id")
                    return try (id, BestSet(weight: Weight(e7g: set.integer("weight_e7g")), reps: set.reps("reps")))
                }
            }
        }
        return Dictionary(rows) { first, _ in first }
    }
}
