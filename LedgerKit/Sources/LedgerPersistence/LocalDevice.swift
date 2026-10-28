import Foundation
import GRDB
import LedgerDomain

/// This install's device (decision B4): the `device` row of this platform's kind. The first launch inserts it
/// with a new id; every later launch reads it back, so the id lasts as long as the database. A restore from a
/// backup brings the old row, and its id, with it; a reinstall starts a new database and gets a new id. Rows of
/// the other kind (the paired device's, once F19 syncs them) are never this device.
public enum LocalDevice {
    /// The `device.kind` column's values.
    public enum Kind: String, Sendable, CaseIterable {
        case phone
        case watch

        /// The `device.name` a new row gets.
        var name: String {
            switch self {
            case .phone: "iPhone"
            case .watch: "Apple Watch"
            }
        }
    }

    /// Reads the row of `kind`, or inserts one with `newID()` created `now`, in one write; returns its id.
    /// Should there ever be more than one row of `kind`, the oldest (then the lowest id) is this device's.
    /// A stored id that is not a UUID throws `LedgerPersistenceError.malformedIdentifier`, and the row is kept.
    public static func id(
        in queue: DatabaseQueue,
        kind: Kind,
        now: Date,
        newID: @Sendable () -> UUID
    ) throws -> DeviceID {
        try open(in: queue, kind: kind, now: now, newID: newID).id
    }

    /// `id(in:kind:now:newID:)`, and whether this call inserted the row: true only on a new install's first launch
    /// (F14-S1-5, ruled: the region's settings are seeded then, and never over an install made before F14).
    public static func open(
        in queue: DatabaseQueue,
        kind: Kind,
        now: Date,
        newID: @Sendable () -> UUID
    ) throws -> (id: DeviceID, isNew: Bool) {
        try queue.write { database in
            let sql = "SELECT id FROM device WHERE kind = ? ORDER BY created_at, id LIMIT 1"
            if let stored = try String.fetchOne(database, sql: sql, arguments: [kind.rawValue]) {
                return try (ColumnCodec.identifier(stored), false)
            }
            let id = DeviceID(newID())
            try database.execute(
                sql: "INSERT INTO device (id, kind, name, created_at) VALUES (?, ?, ?, ?)",
                arguments: [ColumnCodec.text(id), kind.rawValue, kind.name, ColumnCodec.timestamp(now)]
            )
            return (id, true)
        }
    }
}
