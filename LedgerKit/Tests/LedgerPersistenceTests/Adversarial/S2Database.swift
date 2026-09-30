import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Synchronization

/// F05 S2 adversarial round 1: databases, a settable clock and SQL probes for the S2 attacks.
extension S2Kit {
    // MARK: - Databases

    struct Stack {
        let queue: DatabaseQueue
        let clock: Clock
        let exercises: GRDBExerciseRepository
        let programs: GRDBProgramRepository
    }

    /// A settable clock for `now`, so timestamps are deterministic.
    final class Clock: Sendable {
        private let current = Mutex(Date(timeIntervalSinceReferenceDate: 800_000_000))

        var now: Date {
            current.withLock { $0 }
        }

        func advance(seconds: TimeInterval = 60) {
            current.withLock { $0 = $0.addingTimeInterval(seconds) }
        }
    }

    /// An in-memory database whose exercise table holds `slotExercises`.
    static func stack() async throws -> Stack {
        let queue = try LedgerDatabase.inMemory()
        let clock = Clock()
        let exercises = GRDBExerciseRepository(queue, now: { clock.now })
        for exercise in slotExercises {
            try await exercises.save(exercise)
        }
        return Stack(queue: queue, clock: clock, exercises: exercises, programs: GRDBProgramRepository(queue, now: {
            clock.now
        }))
    }

    // MARK: - SQL probes

    static func liveCount(_ queue: DatabaseQueue, _ table: String) async throws -> Int {
        try await queue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table) WHERE deleted_at IS NULL") ?? -1
        }
    }

    static func count(_ queue: DatabaseQueue, _ table: String) async throws -> Int {
        try await queue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
        }
    }

    /// Runs `sql` with foreign keys off, as a foreign writer or damage could leave a row.
    static func damage(_ queue: DatabaseQueue, _ sql: String, _ arguments: StatementArguments = []) async throws {
        try await queue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA foreign_keys = OFF")
            defer { try? database.execute(sql: "PRAGMA foreign_keys = ON") } // restoring; the write already ran
            try database.execute(sql: sql, arguments: arguments)
        }
    }

    /// The row counts a program implies: weeks, days, slots, misses.
    static func expectedCounts(_ programs: [Program]) -> [String: Int] {
        [
            "program": programs.count,
            "program_week": programs.map(\.weeks.count).reduce(0, +),
            "day_template": programs.map(\.days.count).reduce(0, +),
            "slot": programs.map { $0.days.map(\.slots.count).reduce(0, +) }.reduce(0, +),
            "slot_miss": programs.map { $0.days.flatMap(\.slots).map(\.misses.count).reduce(0, +) }.reduce(0, +)
        ]
    }

    static func liveCounts(_ queue: DatabaseQueue) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in ["program", "program_week", "day_template", "slot", "slot_miss"] {
            counts[table] = try await liveCount(queue, table)
        }
        return counts
    }
}
