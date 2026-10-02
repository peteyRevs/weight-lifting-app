import CryptoKit
import Foundation
import GRDB
import LedgerDomain

/// A `slot` row: one exercise of a day template, and its place in `DayTemplate.slots`. Its misses are
/// `slot_miss` rows, so a slot read from a row has none until `ProgramRows` adds them.
struct SlotRecord: SyncedRecord {
    static let databaseTableName = "slot"

    let slot: Slot
    let dayTemplateID: DayTemplateID
    let position: Int

    var rowID: String {
        ColumnCodec.text(slot.id)
    }

    init(_ slot: Slot, dayTemplateID: DayTemplateID, position: Int) {
        self.slot = slot
        self.dayTemplateID = dayTemplateID
        self.position = position
    }

    /// Validates through `Slot.init`, so a stored value out of range throws `SlotValidationError`.
    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        slot = try Slot(
            id: read.identifier("id"),
            exerciseID: read.identifier("exercise_id"),
            sets: read.integer("sets"),
            reps: read.integer("reps"),
            repsHi: read.integer("reps_hi"),
            rpe: Decimal(read.integer("rpe_x2") as Int) / 2,
            restSeconds: read.integer("rest_seconds"),
            progression: read.enumeration("progression"),
            startLoad: read.weight("start_load_e7g"),
            step: read.weight("step_e7g"),
            isSupersetWithPrevious: read.flag("is_superset_with_previous"),
            dropSets: read.integer("drop_sets")
        )
        dayTemplateID = try read.identifier("day_template_id")
        position = try read.integer("position")
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = rowID
        container["day_template_id"] = ColumnCodec.text(dayTemplateID)
        container["position"] = position
        container["exercise_id"] = ColumnCodec.text(slot.exerciseID)
        container["sets"] = slot.sets
        container["reps"] = slot.reps
        container["reps_hi"] = slot.repsHi
        container["rpe_x2"] = NSDecimalNumber(decimal: slot.rpe.value * 2).intValue // 10…20, whole
        container["rest_seconds"] = slot.rest.seconds
        container["progression"] = slot.progression.rawValue
        container["start_load_e7g"] = try slot.startLoad?.e7g()
        container["step_e7g"] = try slot.step?.e7g()
        container["is_superset_with_previous"] = slot.isSupersetWithPrevious
        container["drop_sets"] = slot.dropSets
    }
}

/// A `slot_miss` row: one week index in `Slot.misses` (rule 13).
struct SlotMissRecord: SyncedRecord {
    static let databaseTableName = "slot_miss"

    let slotID: SlotID
    let weekIndex: Int

    /// The id this app writes: derived from the slot and the week, so one miss has one id on every device and
    /// a sync merges two records of it instead of keeping both (ADR-002 allows no `UNIQUE` to prevent that).
    var rowID: String {
        Self.id(slot: slotID, week: weekIndex).uuidString
    }

    init(slotID: SlotID, weekIndex: Int) {
        self.slotID = slotID
        self.weekIndex = weekIndex
    }

    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        slotID = try read.identifier("slot_id")
        weekIndex = try read.integer("week_index")
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = rowID
        container["slot_id"] = ColumnCodec.text(slotID)
        container["week_index"] = weekIndex
    }

    /// RFC 9562 §5.5: the name-based UUID (SHA-1, version 5) of `week` as decimal text, in `slot`'s namespace.
    static func id(slot: SlotID, week: Int) -> UUID {
        let namespace = withUnsafeBytes(of: slot.rawValue.uuid) { Array($0) }
        var digest = Array(Insecure.SHA1.hash(data: namespace + Array(String(week).utf8)))
        digest[6] = digest[6] & 0x0F | 0x50 // version 5
        digest[8] = digest[8] & 0x3F | 0x80 // RFC 9562 variant
        return UUID(uuid: digest.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
    }
}
