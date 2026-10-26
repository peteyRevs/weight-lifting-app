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
        try await queue.read { database in try Self.fetchBestSets(in: database) }
    }

    /// Each live finished workout with a done set of the exercise, newest first as `recent` lists them (of two that
    /// started together, the smaller id first), with its done sets of every kind in row and set order (F12 S2,
    /// N9). One read through `idx_wex_exercise_workout`. A set that cannot be read throws, as `bestSet` does.
    func exerciseSessions(exerciseID: ExerciseID) async throws -> [ExerciseSession] {
        try await queue.read { database in try Self.fetchSessions(exerciseID, in: database) }
    }

    /// `exerciseSessions(exerciseID:)` now, then after every change that alters it. A set that cannot be read
    /// ends the stream, as every observation's failure does.
    func observeExerciseSessions(exerciseID: ExerciseID) -> AsyncStream<[ExerciseSession]> {
        Self.sessionsObservation(exerciseID).stream(in: queue)
    }

    /// The Library's stats now, then after every change that alters them (F12 S3, N20): one observation of the
    /// tables they are read from, so a workout finished, edited or deleted, the newest or an older one, reaches
    /// RECENTLY LOGGED, the session counts and the PRs. A read that fails ends the stream.
    func observeLibraryStats(recentLimit: Int) -> AsyncStream<LibraryStats> {
        Self.libraryObservation(recentLimit: recentLimit).stream(in: queue)
    }
}

extension GRDBStatsQueries {
    /// `observeLibraryStats(recentLimit:)`'s observation: `recentlyLogged`, each one's `sessionCount` and
    /// `bestSets`, read in one access and emitted only when they differ from the last value.
    static func libraryObservation(recentLimit: Int) -> DistinctObservation<LibraryStats> {
        ValueObservation.tracking { database in
            let recent = try fetchRecentlyLogged(limit: recentLimit, in: database)
            var sessions: [ExerciseID: Int] = [:]
            for id in recent {
                sessions[id] = try fetchSessionCount(id, in: database)
            }
            return try LibraryStats(recent: recent, sessions: sessions, bestSets: fetchBestSets(in: database))
        }
        .removeDuplicates()
    }

    /// `bestSets()`'s read inside a database access.
    static func fetchBestSets(in database: Database) throws -> [ExerciseID: BestSet] {
        let sql = """
        SELECT id, weight_e7g, reps FROM (
            SELECT workout_exercise.exercise_id AS id, logged_set.weight_e7g AS weight_e7g, logged_set.reps AS reps,
                ROW_NUMBER() OVER (
                    PARTITION BY workout_exercise.exercise_id
                    ORDER BY logged_set.weight_e7g DESC, logged_set.reps DESC
                ) AS place
            \(recordSets)
        )
        WHERE place = 1
        """
        let table = WorkoutExerciseRecord.databaseTableName
        let rows = try Row.fetchAll(database, sql: sql).compactMap { row in
            // The row's `id` is the exercise's, so a row left out is logged under the exercise (review n2).
            row.readable(as: ExerciseRecord.databaseTableName) { row -> (ExerciseID, BestSet) in
                let set = ColumnReader(row: row, table: "logged_set")
                let id: ExerciseID = try ColumnReader(row: row, table: table).identifier("id")
                return try (id, BestSet(weight: Weight(e7g: set.integer("weight_e7g")), reps: set.reps("reps")))
            }
        }
        return Dictionary(rows) { first, _ in first }
    }

    /// `observeExerciseSessions(exerciseID:)`'s observation: `exerciseSessions(exerciseID:)`, emitted only when it
    /// differs from the last value.
    static func sessionsObservation(_ exerciseID: ExerciseID) -> DistinctObservation<[ExerciseSession]> {
        ValueObservation.tracking { database in try fetchSessions(exerciseID, in: database) }.removeDuplicates()
    }

    private static func fetchSessions(_ exerciseID: ExerciseID, in database: Database) throws -> [ExerciseSession] {
        let sql = """
        SELECT logged_set.*, workout.id AS session_id, workout.started_at AS started_at
        \(doneSets) AND workout_exercise.exercise_id = ?
        ORDER BY workout.started_at DESC, workout.id, workout_exercise.position, logged_set.position
        """
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

/// The reads of `sessionCount` and `recentlyLogged` inside a database access, which the Library's observation
/// makes too (`observeLibraryStats`, F12 S3).
extension GRDBStatsQueries {
    static func fetchSessionCount(_ exerciseID: ExerciseID, in database: Database) throws -> Int {
        let sql = "SELECT COUNT(DISTINCT workout.id) \(doneSets) AND workout_exercise.exercise_id = ?"
        return try Int.fetchOne(database, sql: sql, arguments: [ColumnCodec.text(exerciseID)]) ?? 0
    }

    static func fetchRecentlyLogged(limit: Int, in database: Database) throws -> [ExerciseID] {
        let sql = """
        SELECT workout_exercise.exercise_id AS id, MAX(workout.started_at) AS started_at
        \(doneSets)
        GROUP BY workout_exercise.exercise_id ORDER BY started_at DESC, workout_exercise.exercise_id LIMIT ?
        """
        let table = WorkoutExerciseRecord.databaseTableName
        return try Row.fetchAll(database, sql: sql, arguments: [max(0, limit)]).compactMap { row in
            row.readable(as: table) { try ColumnReader(row: $0, table: table).identifier("id") }
        }
    }
}
