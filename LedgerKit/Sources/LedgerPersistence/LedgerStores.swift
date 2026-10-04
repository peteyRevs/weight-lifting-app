import Foundation
import GRDB
import LedgerDomain

/// The six GRDB stores over one database queue, and this install's device id: what a composition root binds to
/// the store keys and `deviceID` (architecture §13). The queue serialises every access, so the stores share it.
public struct LedgerStores: Sendable {
    public let queue: DatabaseQueue
    /// This install's device (`LocalDevice`).
    public let deviceID: DeviceID
    public let exercises: GRDBExerciseRepository
    public let programs: GRDBProgramRepository
    public let workouts: GRDBWorkoutRepository
    public let events: GRDBWorkoutEventStore
    public let settings: GRDBSettingsRepository
    public let stats: GRDBStatsQueries

    /// The stores over `queue`, each given `now` (the injected date).
    public init(_ queue: DatabaseQueue, deviceID: DeviceID, now: @escaping @Sendable () -> Date) {
        self.queue = queue
        self.deviceID = deviceID
        exercises = GRDBExerciseRepository(queue, now: now)
        programs = GRDBProgramRepository(queue, now: now)
        workouts = GRDBWorkoutRepository(queue, now: now)
        events = GRDBWorkoutEventStore(queue, now: now)
        settings = GRDBSettingsRepository(queue, now: now)
        stats = GRDBStatsQueries(queue, now: now)
    }

    /// Opens and migrates the database at `url` (`LedgerDatabase.open(at:protection:)`, synchronous), then reads
    /// or inserts this device's row (`LocalDevice`), and throws whatever either throws (product decision #29):
    /// - a missing or empty file becomes a new database;
    /// - a file of Ledger's whose migrations this build knows migrates (when some are pending) and opens;
    /// - any other file is refused before a byte of it is written: one SQLite cannot read (not a database, no
    ///   permission), one that is not Ledger's (`OpenError.notLedgerDatabase`), and one a later version migrated
    ///   (`OpenError.laterSchema`). It is never deleted, moved or replaced either.
    ///
    /// A failure after the preflight (a migration that fails on the data, a damaged `device` row) can leave the
    /// migrations that succeeded before it applied, each in its own transaction, as GRDB's migrator commits them.
    public static func open(
        at url: URL,
        kind: LocalDevice.Kind,
        now: @escaping @Sendable () -> Date,
        newID: @Sendable () -> UUID
    ) throws -> LedgerStores {
        let database = try LedgerDatabase.open(at: url)
        let device = try LocalDevice.id(in: database, kind: kind, now: now(), newID: newID)
        return LedgerStores(database, deviceID: device, now: now)
    }

    /// Where an app keeps its database: `Application Support/Database/ledger.sqlite`, a directory of its own for
    /// SQLite's `-wal` and `-shm` companions (F05).
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Database/ledger.sqlite", directoryHint: .notDirectory)
    }

    /// Seeds the bundled exercise catalog unless its version is already applied (F05: safe on every launch).
    /// Throws when the catalog cannot be read or the write fails; the seed then rolls back whole.
    public func seedCatalog() async throws {
        try await exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
    }
}
