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
    /// or inserts this device's row (`LocalDevice`). Throws whatever either throws; a file that cannot be opened
    /// is left exactly as it was (product decision #29).
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
