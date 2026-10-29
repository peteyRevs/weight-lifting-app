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
        try queue.write { database in try open(in: database, kind: kind, now: now, newID: newID).id }
    }

    /// `id(in:kind:now:newID:)` inside the caller's write, and whether it inserted the row: true only on a new
    /// install's first launch. `LedgerStores.open` seeds the region's settings in that same write (F14-S1-5 and
    /// F14-S1a-R1-3, ruled), so the row and the seed are written together or not at all.
    static func open(
        in database: Database,
        kind: Kind,
        now: Date,
        newID: @Sendable () -> UUID
    ) throws -> (id: DeviceID, isNew: Bool) {
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
