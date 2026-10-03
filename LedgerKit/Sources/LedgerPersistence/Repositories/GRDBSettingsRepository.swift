import Foundation
import GRDB
import LedgerDomain

/// `SettingsRepository` over the single `settings` row, whose `payload` is the JSON `Settings` in
/// `payload_version`.
public struct GRDBSettingsRepository: SettingsRepository {
    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameter now: the clock for `updated_at`; the composition root passes the injected date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    /// The saved settings, or `Settings.default` before the first save. A key missing from the stored
    /// JSON takes its default (`Settings.init(from:)`). A row this app cannot read throws and is left as it
    /// is: `LedgerPersistenceError.unknownPayloadVersion` for a later payload version, `.malformedColumn`
    /// for a damaged column, and `DecodingError` for JSON holding an invalid value.
    public func load() async throws -> Settings {
        try await queue.read { database in try Self.fetch(database) }
    }

    /// Upserts the one row. The payload is the JSON bytes cast to `TEXT`, which SQLite reads as UTF-8,
    /// the encoding `JSONEncoder` writes.
    public func save(_ settings: Settings) async throws {
        let payload = try SettingsCodec.encode(settings)
        let updatedAt = ColumnCodec.timestamp(now())
        try await queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO settings (id, payload_version, payload, updated_at) VALUES (?, ?, CAST(? AS TEXT), ?)
                ON CONFLICT (id) DO UPDATE SET payload_version = excluded.payload_version,
                    payload = excluded.payload, updated_at = excluded.updated_at
                """,
                arguments: [Self.rowID, SettingsCodec.version, payload, updatedAt]
            )
        }
    }

    /// The settings now, then after every save that changes them. The stream ends, with the error logged,
    /// when the row cannot be read (`load()` says why); F07 and F14 then fall back to the defaults in
    /// memory without saving over the row.
    public func observe() -> AsyncStream<Settings> {
        ValueObservation.tracking { database in try Self.fetch(database) }
            .removeDuplicates()
            .stream(in: queue)
    }

    private static let rowID = "singleton"

    /// Reads the columns as values, so a damaged one (a version stored as text or a blob, a payload that is
    /// not UTF-8 text) throws `LedgerPersistenceError.malformedColumn` rather than trapping, and never
    /// falls back to the defaults, which a later save would write over the lifter's settings.
    private static func fetch(_ database: Database) throws -> Settings {
        let sql = "SELECT payload_version, payload FROM settings WHERE id = ?"
        guard let row = try Row.fetchOne(database, sql: sql, arguments: [rowID]) else {
            return .default
        }
        guard let version = Int.fromDatabaseValue(row["payload_version"]) else {
            throw LedgerPersistenceError.malformedColumn("settings.payload_version")
        }
        guard let payload = String.fromDatabaseValue(row["payload"]) else {
            throw LedgerPersistenceError.malformedColumn("settings.payload")
        }
        return try SettingsCodec.decode(Data(payload.utf8), version: version)
    }
}
