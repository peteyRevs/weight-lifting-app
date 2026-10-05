import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization

/// A clock the test moves by hand, to tell `created_at` from `updated_at`.
final class ManualClock: Sendable {
    private let current = Mutex(EventBuilders.start)

    var now: @Sendable () -> Date {
        { [self] in current.withLock { $0 } }
    }

    /// The `created_at` / `updated_at` text of the current time.
    var timestamp: String {
        ColumnCodec.timestamp(current.withLock { $0 })
    }

    func advance(seconds: TimeInterval = 60) {
        current.withLock { $0.addTimeInterval(seconds) }
    }
}

/// The repositories and the stats queries over one fresh in-memory database, on one `ManualClock`. The stats
/// read the current time as `StatsQueriesContract.now`, whatever the clock says.
struct Repositories {
    let queue: DatabaseQueue
    let clock = ManualClock()
    let exercises: GRDBExerciseRepository
    let programs: GRDBProgramRepository
    let workouts: GRDBWorkoutRepository
    let stats: GRDBStatsQueries
    let events: GRDBWorkoutEventStore

    init() throws {
        queue = try LedgerDatabase.inMemory()
        exercises = GRDBExerciseRepository(queue, now: clock.now)
        programs = GRDBProgramRepository(queue, now: clock.now)
        workouts = GRDBWorkoutRepository(queue, now: clock.now)
        stats = GRDBStatsQueries(queue, now: { StatsQueriesContract.now })
        events = GRDBWorkoutEventStore(queue, now: clock.now)
    }

    /// What a history contract clause runs against (`WorkoutRepositoryContract`, `StatsQueriesContract`).
    var history: HistoryStores {
        HistoryStores(workouts: workouts, stats: stats, programs: programs, events: events)
    }

    /// With `ProgramRepositoryContract.exercises` seeded, which every contract program names.
    static func withProgramExercises() async throws -> Repositories {
        let repositories = try Repositories()
        try await repositories.exercises.seedIfNeeded(ProgramRepositoryContract.exercises, version: 1)
        return repositories
    }

    /// The first column of every row `sql` selects, as text; select `quote(…)` to see `NULL` and types.
    func texts(_ sql: String, _ arguments: StatementArguments = []) async throws -> [String] {
        try await queue.read { database in try String.fetchAll(database, sql: sql, arguments: arguments) }
    }

    /// The number of rows `sql` counts.
    func count(_ sql: String, _ arguments: StatementArguments = []) async throws -> Int {
        try await queue.read { database in try Int.fetchOne(database, sql: sql, arguments: arguments) ?? -1 }
    }

    func execute(_ sql: String, _ arguments: StatementArguments = []) async throws {
        try await queue.write { database in try database.execute(sql: sql, arguments: arguments) }
    }

    /// Runs `sql` with foreign keys off, as damage or a foreign writer could leave a row.
    func damage(_ sql: String, _ arguments: StatementArguments = []) async throws {
        try await queue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA foreign_keys = OFF")
            defer { try? database.execute(sql: "PRAGMA foreign_keys = ON") } // restoring; the write already ran
            try database.execute(sql: sql, arguments: arguments)
        }
    }

    /// The SQL, arguments expanded, of each statement `body` runs that starts with `prefix`, in the order run.
    func statements(startingWith prefix: String, during body: () async throws -> Void) async throws -> [String] {
        let log = StatementLog()
        try await queue.writeWithoutTransaction { database in
            database.trace { event in
                if case let .statement(statement) = event, statement.sql.hasPrefix(prefix) {
                    log.lines.withLock { $0.append(statement.expandedSQL) }
                }
            }
        }
        try await body()
        try await queue.writeWithoutTransaction { database in database.trace() }
        return log.lines.withLock { $0 }
    }
}

/// What `Repositories.statements(startingWith:during:)` collects.
final class StatementLog: Sendable {
    let lines = Mutex<[String]>([])
}
