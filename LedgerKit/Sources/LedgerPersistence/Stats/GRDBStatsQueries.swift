import Foundation
import GRDB
import LedgerDomain

/// `StatsQueries` over the finished workouts `GRDBWorkoutRepository` stores.
///
/// - Every query counts **done** sets of live, finished workouts only.
/// - A workout's date is when it ended (`ended_at`): that is the date of a "Last" line, the week a workout's
///   volume and e1RM fall in, and what a range selects. So a workout belongs to one week, whenever its sets
///   were ticked.
/// - The bests (`bestSet`, `bestE1RM`, `e1RMByWeek`) count the sets that can set a personal record:
///   `.working` and `.added` (decision #3, `PersonalRecords.detect`). Volume counts every kind (rule 34).
/// - Weights are never multiplied or summed in SQL (ADR-007): SQL compares and orders the exact `_e7g`
///   integers, and volume is summed in `Decimal`.
/// - Columns are read strictly (`ColumnReader`): a damaged value throws `malformedColumn`, never traps and
///   never reads as a rounded number.
public struct GRDBStatsQueries: StatsQueries {
    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameter now: the clock that says which week is the current one (`e1RMByWeek`); the composition root
    ///   passes the injected date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    /// The "Last" line (spec §6.3, rule 14): the most recent workout in which the exercise has a done
    /// `.working` set, as its end date, how many such sets it has, and the load and reps of the heaviest of
    /// them (of two as heavy, the one with more reps). `nil` when there is none.
    public func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
        let sql = """
        SELECT workout.ended_at AS ended_at, logged_set.weight_e7g AS weight_e7g, logged_set.reps AS reps
        \(SQL.doneSets) AND logged_set.kind = 'working' AND workout_exercise.exercise_id = :exercise
            AND workout.id = (
                SELECT workout.id
                \(SQL.doneSets) AND logged_set.kind = 'working' AND workout_exercise.exercise_id = :exercise
                ORDER BY workout.ended_at DESC, workout.id LIMIT 1
            )
        ORDER BY logged_set.weight_e7g DESC, logged_set.reps DESC
        """
        return try await queue.read { database in
            let rows = try Row.fetchAll(database, sql: sql, arguments: ["exercise": ColumnCodec.text(exerciseID)])
            guard let top = rows.first else {
                return nil
            }
            let set = ColumnReader(row: top, table: "logged_set")
            return try LastPerformance(
                date: ColumnReader(row: top, table: "workout").date("ended_at"),
                sets: rows.count,
                reps: set.reps("reps").value,
                load: Weight(e7g: set.integer("weight_e7g"))
            )
        }
    }

    /// The heaviest done set of the exercise, and of two as heavy the one with more reps; `nil` when there is
    /// none.
    public func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        let sql = """
        SELECT logged_set.weight_e7g AS weight_e7g, logged_set.reps AS reps
        \(SQL.doneSets) \(SQL.recordKinds) AND workout_exercise.exercise_id = ?
        ORDER BY logged_set.weight_e7g DESC, logged_set.reps DESC LIMIT 1
        """
        return try await queue.read { database in
            guard let row = try Row.fetchOne(database, sql: sql, arguments: [ColumnCodec.text(exerciseID)]) else {
                return nil
            }
            let set = ColumnReader(row: row, table: "logged_set")
            return try (Weight(e7g: set.integer("weight_e7g")), set.reps("reps"))
        }
    }

    /// The best Brzycki e1RM of the exercise's done sets of at most 12 reps (decision #4); `nil` when there
    /// is none.
    public func bestE1RM(exerciseID: ExerciseID) async throws -> Weight? {
        let sql = """
        SELECT MAX(logged_set.e1rm_e7g) AS e1rm_e7g
        \(SQL.doneSets) \(SQL.recordKinds) AND workout_exercise.exercise_id = ?
        """
        return try await queue.read { database in
            try Row.fetchOne(database, sql: sql, arguments: [ColumnCodec.text(exerciseID)]).flatMap { row in
                try ColumnReader(row: row, table: "logged_set").weight("e1rm_e7g")
            }
        }
    }

    /// The best e1RM of each of the last `lastWeeks` stats weeks, the current one (the week holding `now`)
    /// included, keyed by `calendar.isoWeekKey(for:)` (decision #4). A week with no estimate has no key; a
    /// `lastWeeks` that is not positive gives none.
    public func e1RMByWeek(
        exerciseID: ExerciseID,
        lastWeeks: Int,
        calendar: WeekCalendar
    ) async throws -> [WeekKey: Weight] {
        guard lastWeeks > 0, let currentWeek = calendar.firstDayOfWeek(containing: now()) else {
            return [:]
        }
        let sql = """
        SELECT workout.ended_at AS ended_at, MAX(logged_set.e1rm_e7g) AS e1rm_e7g
        \(SQL.doneSets) \(SQL.recordKinds) AND workout_exercise.exercise_id = ? AND logged_set.e1rm_e7g IS NOT NULL
        GROUP BY workout.id ORDER BY workout.ended_at, workout.id
        """
        return try await queue.read { database in
            var best: [WeekKey: Weight] = [:]
            for row in try Row.fetchAll(database, sql: sql, arguments: [ColumnCodec.text(exerciseID)]) {
                let endedAt = try ColumnReader(row: row, table: "workout").date("ended_at")
                let estimate = try Weight(e7g: ColumnReader(row: row, table: "logged_set").integer("e1rm_e7g"))
                // Whole weeks back from the current one; a workout dated after it counts for no week.
                guard let week = calendar.firstDayOfWeek(containing: endedAt),
                      (0 ..< lastWeeks).contains(currentWeek.days(since: week) / 7)
                else {
                    continue
                }
                let key = calendar.isoWeekKey(for: endedAt)
                best[key] = max(best[key] ?? estimate, estimate)
            }
            return best
        }
    }

    /// Rule 34: Σ weight × reps over the done sets, of every kind, of the workouts that ended in `range`. The
    /// Today delta (decision #15) is this for the current week against the previous complete week.
    public func weeklyVolume(in range: Range<Date>) async throws -> Volume {
        // One row per distinct weight, so SQL sums only the reps and the product is exact `Decimal`.
        let sql = """
        SELECT logged_set.weight_e7g AS weight_e7g, SUM(logged_set.reps) AS reps
        \(SQL.doneSets) AND workout.ended_at >= ? AND workout.ended_at < ?
        GROUP BY logged_set.weight_e7g ORDER BY logged_set.weight_e7g
        """
        return try await queue.read { database in
            try Row.fetchAll(database, sql: sql, arguments: SQL.bounds(range)).reduce(Volume.zero) { total, row in
                let set = ColumnReader(row: row, table: "logged_set")
                let weight = try Weight(e7g: set.integer("weight_e7g"))
                return try total + Volume(gramReps: weight.grams * Decimal(set.integer("reps") as Int64))
            }
        }
    }

    /// Rule 35: how many finished workouts ended in `range`, with or without a done set.
    ///
    /// A workout row whose id is not stored as text is damage that no read returns (`WorkoutRows.fetch`), and
    /// every other query misses it already, since its children's text `workout_id` never equals it. It is not
    /// counted here either.
    public func sessionsCompleted(in range: Range<Date>) async throws -> Int {
        let sql = """
        SELECT COUNT(*) FROM workout
        WHERE deleted_at IS NULL AND phase = 'finished' AND ended_at >= ? AND ended_at < ?
            AND typeof(id) = 'text'
        """
        return try await queue.read { database in
            try SQL.count(sql, SQL.bounds(range), in: database)
        }
    }

    /// How many workouts hold a done set, of any kind, of the exercise.
    public func sessionCount(exerciseID: ExerciseID) async throws -> Int {
        let sql = "SELECT COUNT(DISTINCT workout.id) \(SQL.doneSets) AND workout_exercise.exercise_id = ?"
        return try await queue.read { database in
            try SQL.count(sql, [ColumnCodec.text(exerciseID)], in: database)
        }
    }

    /// The personal records the exercise's workouts set, newest first; within a workout, the estimated 1RM
    /// before the weight at reps. A record row this app cannot read is logged and left out, and stays stored.
    public func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord] {
        let sql = """
        SELECT personal_record.* FROM personal_record JOIN workout ON workout.id = personal_record.workout_id
        WHERE personal_record.exercise_id = ? AND personal_record.deleted_at IS NULL
            AND workout.deleted_at IS NULL AND workout.phase = 'finished'
        ORDER BY personal_record.achieved_at DESC, personal_record.kind, personal_record.id
        """
        return try await queue.read { database in
            try Row.fetchAll(database, sql: sql, arguments: [ColumnCodec.text(exerciseID)]).compactMap { row in
                row.readable(as: PersonalRecordRecord.databaseTableName) { try PersonalRecordRecord(row: $0).record }
            }
        }
    }

    /// The `limit` exercises with a done set in the most recent workouts, the latest first; none when `limit`
    /// is not positive. Exercises of one workout are in id order. An exercise id this app cannot read is logged
    /// and left out.
    public func recentlyLogged(limit: Int) async throws -> [ExerciseID] {
        let sql = """
        SELECT workout_exercise.exercise_id AS id, MAX(workout.ended_at) AS ended_at
        \(SQL.doneSets)
        GROUP BY workout_exercise.exercise_id ORDER BY ended_at DESC, workout_exercise.exercise_id LIMIT ?
        """
        let table = WorkoutExerciseRecord.databaseTableName
        return try await queue.read { database in
            try Row.fetchAll(database, sql: sql, arguments: [max(0, limit)]).compactMap { row in
                row.readable(as: table) { try ColumnReader(row: $0, table: table).identifier("id") }
            }
        }
    }
}

/// The SQL the stats queries share.
private enum SQL {
    /// The done sets of live, finished workouts, joined to their exercise and workout. Continue the
    /// `WHERE` with `AND …`.
    static let doneSets = """
    FROM logged_set
    JOIN workout_exercise ON workout_exercise.id = logged_set.workout_exercise_id
    JOIN workout ON workout.id = workout_exercise.workout_id
    WHERE logged_set.deleted_at IS NULL AND logged_set.done_at IS NOT NULL
        AND workout_exercise.deleted_at IS NULL
        AND workout.deleted_at IS NULL AND workout.phase = 'finished'
    """

    /// Decision #3: the kinds of set that can set a personal record.
    static let recordKinds = "AND logged_set.kind IN ('working', 'added')"

    /// What a `SELECT COUNT(…)` counts. It always answers with one row, so the `0` is never used.
    static func count(_ sql: String, _ arguments: StatementArguments, in database: Database) throws -> Int {
        try Int.fetchOne(database, sql: sql, arguments: arguments) ?? 0
    }

    /// A range's bounds for `ended_at >= ? AND ended_at < ?`.
    static func bounds(_ range: Range<Date>) -> StatementArguments {
        [range.lowerBound.timeIntervalSinceReferenceDate, range.upperBound.timeIntervalSinceReferenceDate]
    }
}
