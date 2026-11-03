import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization

/// F13 S3 adversarial (G2): what the batched edit's attacks share: the rows as stored, SQLite's trace, a history.
enum BatchedEditKit {
    typealias Dump = [String: [String: String]]

    static func sweep(_ full: Int, _ reduced: Int) -> Int {
        TestSweep.isReduced ? reduced : full
    }

    /// Every column of every row of `table`, by id, as stored: storage class included.
    static func rows(of table: String, in stack: S3Kit.Stack) async throws -> Dump {
        try await stack.queue.read { database in
            var dump: Dump = [:]
            for row in try Row.fetchAll(database, sql: "SELECT * FROM \(table)") {
                var columns: [String: String] = [:]
                for name in row.columnNames {
                    columns[name] = String(describing: row[name] as DatabaseValue)
                }
                // The dump's values are SQL literals: the id's quotes come off to match `ColumnCodec.text`.
                dump[(columns["id"] ?? "").replacingOccurrences(of: "\"", with: "")] = columns
            }
            return dump
        }
    }

    /// The whole of what a workout write can touch.
    static func all(in stack: S3Kit.Stack) async throws -> [String: Dump] {
        var dump: [String: Dump] = [:]
        for table in ["workout", "workout_exercise", "logged_set", "personal_record"] {
            dump[table] = try await rows(of: table, in: stack)
        }
        return dump
    }

    /// The columns that differ between two rows.
    static func changed(_ old: [String: String]?, _ new: [String: String]?) -> Set<String> {
        let names = Set((old ?? [:]).keys).union((new ?? [:]).keys)
        return names.filter { old?[$0] != new?[$0] }
    }

    /// The SQL of what `body` runs, unexpanded, from SQLite's trace.
    static func trace(_ stack: S3Kit.Stack, during body: () async throws -> Void) async throws -> [String] {
        let lines = Mutex<[String]>([])
        try await stack.queue.writeWithoutTransaction { database in
            database.trace { event in
                if case let .statement(statement) = event {
                    lines.withLock { $0.append(statement.sql) }
                }
            }
        }
        try await body()
        try await stack.queue.writeWithoutTransaction { database in database.trace() }
        return lines.withLock { $0 }
    }

    static func raised(_ sets: [LoggedSet], at place: Int = 0, to weight: Weight, reps: Int? = nil) -> [LoggedSet] {
        var sets = sets
        sets[place].weight = weight
        if let reps {
            sets[place].reps = Reps(clamping: reps)
        }
        return sets
    }

    /// A workout of three exercises, between an older and a newer one on two of them.
    struct History {
        let older: WorkoutState
        let middle: WorkoutState
        let newer: WorkoutState

        var all: [WorkoutState] {
            [older, middle, newer]
        }
    }

    static func history() -> History {
        let older = S3Kit.workout(1, endedAt: S3Kit.day(-4), [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(180, 5)]),
            S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(220, 5)])
        ])
        let middle = S3Kit.workout(2, endedAt: S3Kit.day(-3), [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(185, 5), S3Kit.set(Decimal(string: "187.3") ?? 0, 5)]),
            S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(225, 5), S3Kit.set(225, 5, done: false)]),
            S3Kit.RowSpec(S3Kit.row, [S3Kit.set(135, 8)])
        ])
        let newer = S3Kit.workout(3, endedAt: S3Kit.day(-2), [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(190, 5)]),
            S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(230, 5)])
        ])
        return History(older: older, middle: middle, newer: newer)
    }

    static func stored(_ workouts: [WorkoutState]) async throws -> S3Kit.Stack {
        let stack = try await S3Kit.stack()
        for workout in workouts {
            try await stack.materialize(workout)
        }
        stack.clock.advance()
        return stack
    }
}
