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
    /// JSON takes its default (`Settings.init(from:)`). A row in a payload version this app does not know
    /// throws `LedgerPersistenceError.unknownPayloadVersion`, and the row is left as it is.
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

    /// The settings now, then after every save that changes them.
    public func observe() -> AsyncStream<Settings> {
        ValueObservation.tracking { database in try Self.fetch(database) }
            .removeDuplicates()
            .stream(in: queue)
    }

    private static let rowID = "singleton"

    private static func fetch(_ database: Database) throws -> Settings {
        let sql = "SELECT payload_version, payload FROM settings WHERE id = ?"
        guard let row = try Row.fetchOne(database, sql: sql, arguments: [rowID]) else {
            return .default
        }
        return try SettingsCodec.decode(Data((row["payload"] as String).utf8), version: row["payload_version"])
    }
}

/// `Settings` as `settings.payload`: JSON with sorted keys, decoded by the row's payload version
/// (orchestrator decision, 2026-09-30). Version 1 is the only one so far.
enum SettingsCodec {
    /// The payload version `encode` writes.
    static let version = 1

    static func encode(_ settings: Settings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(settings)
    }

    static func decode(_ payload: Data, version: Int) throws -> Settings {
        switch version {
        case 1:
            try JSONDecoder().decode(Settings.self, from: payload)
        default:
            throw LedgerPersistenceError.unknownPayloadVersion(version)
        }
    }
}
