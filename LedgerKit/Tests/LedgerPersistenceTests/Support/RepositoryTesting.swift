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

/// The exercise and program repositories over one fresh in-memory database, on one `ManualClock`.
struct Repositories {
    let queue: DatabaseQueue
    let clock = ManualClock()
    let exercises: GRDBExerciseRepository
    let programs: GRDBProgramRepository

    init() throws {
        queue = try LedgerDatabase.inMemory()
        exercises = GRDBExerciseRepository(queue, now: clock.now)
        programs = GRDBProgramRepository(queue, now: clock.now)
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
}
