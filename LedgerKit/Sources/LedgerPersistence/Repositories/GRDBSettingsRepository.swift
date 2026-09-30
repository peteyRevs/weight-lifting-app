import Foundation
import GRDB
import LedgerDomain

/// `SettingsRepository` over the single `settings` row, whose `payload` is the JSON `Settings`.
public struct GRDBSettingsRepository: SettingsRepository {
    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameter now: the clock for `updated_at`; the composition root passes the injected date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    /// The saved settings, or `Settings.default` before the first save.
    public func load() async throws -> Settings {
        try await queue.read { database in try Self.fetch(database) }
    }

    /// Upserts the one row. The payload is the JSON bytes cast to `TEXT`, which SQLite reads as UTF-8,
    /// the encoding `JSONEncoder` writes.
    public func save(_ settings: Settings) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(settings)
        let updatedAt = ColumnCodec.timestamp(now())
        try await queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO settings (id, payload, updated_at) VALUES (?, CAST(? AS TEXT), ?)
                ON CONFLICT (id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
                """,
                arguments: [Self.rowID, payload, updatedAt]
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
        let sql = "SELECT payload FROM settings WHERE id = ?"
        guard let payload = try String.fetchOne(database, sql: sql, arguments: [rowID]) else {
            return .default
        }
        return try JSONDecoder().decode(Settings.self, from: Data(payload.utf8))
    }
}
