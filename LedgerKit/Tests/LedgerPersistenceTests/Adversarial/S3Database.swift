import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence

/// F05 S3 adversarial round 1: a database with a settable clock, and SQL probes for the history attacks.
extension S3Kit {
    struct Stack {
        let queue: DatabaseQueue
        let clock: S2Kit.Clock
        let workouts: GRDBWorkoutRepository
        let programs: GRDBProgramRepository
        let exercises: GRDBExerciseRepository

        /// Stats that read the current time as `now`.
        func stats(now: Date = S3Kit.now) -> GRDBStatsQueries {
            GRDBStatsQueries(queue, now: { now })
        }

        /// Materialises `workout` with the receipt the engine computes for it.
        func materialize(_ workout: WorkoutState, prs: [PersonalRecord] = [], slots: [Slot] = []) async throws {
            try await workouts.materialize(
                workout,
                summary: WorkoutEngine.summary(workout, prs: prs),
                prs: prs,
                slotUpdates: slots
            )
        }

        func texts(_ sql: String, _ arguments: StatementArguments = []) async throws -> [String] {
            try await queue.read { database in try String.fetchAll(database, sql: sql, arguments: arguments) }
        }

        func execute(_ sql: String, _ arguments: StatementArguments = []) async throws {
            try await queue.write { database in try database.execute(sql: sql, arguments: arguments) }
        }

        /// Runs `sql` with foreign keys off, as a foreign writer or damage could leave a row.
        func damage(_ sql: String, _ arguments: StatementArguments = []) async throws {
            try await S2Kit.damage(queue, sql, arguments)
        }

        /// Every row of the history tables and the misses, metadata included, as text: for "nothing changed".
        func dump() async throws -> [String] {
            try await queue.read { database in
                try S3Kit.historyTables.flatMap { table in
                    try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY CAST(id AS TEXT), rowid")
                        .map { "\(table): \($0.description)" }
                }
            }
        }

        /// Live row counts of the four history tables.
        func liveCounts() async throws -> [Int] {
            var counts: [Int] = []
            for table in ["workout", "workout_exercise", "logged_set", "personal_record"] {
                try await counts.append(S2Kit.liveCount(queue, table))
            }
            return counts
        }
    }

    static let historyTables = ["workout", "workout_exercise", "logged_set", "personal_record", "slot_miss"]

    /// An in-memory database. `workout_exercise.exercise_id` is no foreign key, so history needs no catalog;
    /// `S2Kit.slotExercises` are stored for the programs whose misses a workout writes.
    static func stack() async throws -> Stack {
        let queue = try LedgerDatabase.inMemory()
        let clock = S2Kit.Clock()
        let exercises = GRDBExerciseRepository(queue, now: { clock.now })
        for exercise in S2Kit.slotExercises {
            try await exercises.save(exercise)
        }
        return Stack(
            queue: queue,
            clock: clock,
            workouts: GRDBWorkoutRepository(queue, now: { clock.now }),
            programs: GRDBProgramRepository(queue, now: { clock.now }),
            exercises: exercises
        )
    }

    /// The live row counts `workouts` and `records` imply: workouts, exercises, sets, records.
    static func expectedCounts(_ workouts: [WorkoutState], records: Int = 0) -> [Int] {
        [
            workouts.count,
            workouts.map(\.exercises.count).reduce(0, +),
            workouts.map(\.totalSets).reduce(0, +),
            records
        ]
    }
}
