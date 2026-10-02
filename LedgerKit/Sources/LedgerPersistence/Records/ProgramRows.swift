import GRDB
import LedgerDomain

/// A program as the rows of its five tables. Saving writes them over the stored rows in one transaction
/// (`write`); reading assembles them into a `Program` through its `init`s (`program(_:in:)`).
struct ProgramRows {
    let programID: ProgramID
    private var program: ProgramRecord?
    private var weeks: [WeekRecord] = []
    private var days: [DayTemplateRecord] = []
    private var slots: [SlotRecord] = []
    private var misses: [SlotMissRecord] = []

    /// The rows of `program`, re-validated first (ADR-007; F02 review N2): every slot is rebuilt through
    /// `Slot.init` and the program through `Program.init`, so a field assigned out of range throws here, at
    /// save time, rather than on the next load.
    init(_ program: Program) throws {
        let validDays = try program.days.map { day in
            var valid = day
            valid.slots = try day.slots.map { try $0.revalidated() }
            return valid
        }
        let valid = try Program(
            id: program.id,
            name: program.name,
            startDate: program.startDate,
            weeks: program.weeks,
            days: validDays,
            goal: program.goal,
            daysPerWeek: program.daysPerWeek,
            isActive: program.isActive
        )
        programID = valid.id
        self.program = ProgramRecord(valid)
        weeks = valid.weeks.map { WeekRecord($0, programID: valid.id) }
        days = valid.days.enumerated().map { DayTemplateRecord($1, programID: valid.id, position: $0) }
        slots = valid.days.flatMap { day in
            day.slots.enumerated().map { SlotRecord($1, dayTemplateID: day.id, position: $0) }
        }
        misses = valid.days.flatMap(\.slots).flatMap { slot in
            slot.misses.sorted().map { SlotMissRecord(slotID: slot.id, weekIndex: $0) }
        }
    }

    /// No rows at all: writing them soft-deletes the program and everything in it.
    init(deleting id: ProgramID) {
        programID = id
    }

    /// Makes the program's live rows these, in the caller's transaction: new and changed rows are upserted,
    /// unchanged ones left alone, and live rows no longer in the program soft-deleted
    /// (`SyncedRecord.write(_:over:in:at:)`).
    func write(_ database: Database, at timestamp: String) throws {
        // Every live row is read before any is written: soft-deleting a day first would hide its slots.
        let key: StatementArguments = [ColumnCodec.text(programID)]
        let storedProgram = try Row.fetchAll(database, sql: Query.program, arguments: key)
        let storedWeeks = try Row.fetchAll(database, sql: Query.weeks, arguments: key)
        let storedDays = try Row.fetchAll(database, sql: Query.days, arguments: key)
        let storedSlots = try Row.fetchAll(database, sql: Query.slots, arguments: key)
        let storedMisses = try Row.fetchAll(database, sql: Query.misses, arguments: key)
        try refuseOtherProgramsIDs(in: database)
        // Parents first, so every foreign key an insert names exists.
        try ProgramRecord.write(program.map { [$0] } ?? [], over: storedProgram, in: database, at: timestamp)
        try WeekRecord.write(weeks, over: storedWeeks, in: database, at: timestamp)
        try DayTemplateRecord.write(days, over: storedDays, in: database, at: timestamp)
        try SlotRecord.write(slots, over: storedSlots, in: database, at: timestamp)
        try SlotMissRecord.write(misses, over: storedMisses, in: database, at: timestamp)
    }

    /// Throws `duplicateIdentifier` when a week, day or slot of this program has an id that another stored
    /// program holds, live or deleted (review B1). Upserting it would move that row into this program, and the other
    /// program would lose it or become unreadable. A miss's id derives from its slot's, so slots cover misses.
    private func refuseOtherProgramsIDs(in database: Database) throws {
        try refuse(weeks.map(\.rowID), of: WeekRecord.databaseTableName, heldBy: Query.weekOwners, in: database)
        try refuse(days.map(\.rowID), of: DayTemplateRecord.databaseTableName, heldBy: Query.dayOwners, in: database)
        try refuse(slots.map(\.rowID), of: SlotRecord.databaseTableName, heldBy: Query.slotOwners, in: database)
    }

    /// Throws `duplicateIdentifier("table id")` for the first of `ids` that `ownersSQL` finds under another
    /// program.
    private func refuse(_ ids: [String], of table: String, heldBy ownersSQL: String, in database: Database) throws {
        guard !ids.isEmpty else {
            return
        }
        let taken = try String.fetchOne(
            database,
            sql: ownersSQL + "(\(databaseQuestionMarks(count: ids.count))) ORDER BY 1 LIMIT 1",
            arguments: StatementArguments([ColumnCodec.text(programID)] + ids)
        )
        if let taken {
            throw LedgerPersistenceError.duplicateIdentifier("\(table) \(taken)")
        }
    }

    /// The live program `id`, or `nil`. Stored values are validated as on construction: a damaged column
    /// throws `LedgerPersistenceError`, and a value out of range `SlotValidationError` or
    /// `ProgramValidationError`.
    static func program(_ id: ProgramID, in database: Database) throws -> Program? {
        let key: StatementArguments = [ColumnCodec.text(id)]
        guard let root = try ProgramRecord.fetchOne(database, sql: Query.program, arguments: key) else {
            return nil
        }
        let weekRecords = try WeekRecord.fetchAll(database, sql: Query.weeks, arguments: key)
        let dayRecords = try DayTemplateRecord.fetchAll(database, sql: Query.days, arguments: key)
        let slotsByDay = try Dictionary(
            grouping: SlotRecord.fetchAll(database, sql: Query.slots, arguments: key),
            by: \.dayTemplateID
        )
        let missesBySlot = try Dictionary(
            grouping: SlotMissRecord.fetchAll(database, sql: Query.misses, arguments: key),
            by: \.slotID
        )
        return try Program(
            id: root.id,
            name: root.name,
            startDate: root.startDate,
            weeks: weekRecords.map(\.week),
            days: dayRecords.map { day in
                let daySlots = slotsByDay[day.id, default: []].map { record in
                    var slot = record.slot
                    slot.misses = Set(missesBySlot[slot.id, default: []].map(\.weekIndex))
                    return slot
                }
                return DayTemplate(id: day.id, name: day.name, tag: day.tag, slots: daySlots)
            },
            goal: root.goal,
            daysPerWeek: root.daysPerWeek,
            isActive: root.isActive
        )
    }

    /// The live rows of one program, children in their stored order (ties by id, so the order is total), and
    /// the owner checks of `refuseOtherProgramsIDs`.
    private enum Query {
        static let program = "SELECT * FROM program WHERE id = ? AND deleted_at IS NULL"
        static let weeks = """
        SELECT * FROM program_week WHERE program_id = ? AND deleted_at IS NULL ORDER BY week_index, id
        """
        static let days = """
        SELECT * FROM day_template WHERE program_id = ? AND deleted_at IS NULL ORDER BY position, id
        """
        static let slots = """
        SELECT slot.* FROM slot JOIN day_template ON day_template.id = slot.day_template_id
        WHERE day_template.program_id = ? AND day_template.deleted_at IS NULL AND slot.deleted_at IS NULL
        ORDER BY slot.position, slot.id
        """
        static let misses = """
        SELECT slot_miss.* FROM slot_miss
        JOIN slot ON slot.id = slot_miss.slot_id
        JOIN day_template ON day_template.id = slot.day_template_id
        WHERE day_template.program_id = ? AND day_template.deleted_at IS NULL AND slot.deleted_at IS NULL
            AND slot_miss.deleted_at IS NULL
        ORDER BY slot_miss.week_index, slot_miss.id
        """
        /// The ids, among those that follow in `IN (…)`, of weeks, days or slots of stored programs other than the
        /// first argument, deleted rows and programs included. A row whose `program_id` names no stored program
        /// is damage, not another program's, so a save repairs it (S2-5).
        static let weekOwners = """
        SELECT id FROM program_week WHERE program_id IS NOT ? AND program_id IN (SELECT id FROM program) AND id IN
        """
        static let dayOwners = """
        SELECT id FROM day_template WHERE program_id IS NOT ? AND program_id IN (SELECT id FROM program) AND id IN
        """
        static let slotOwners = """
        SELECT slot.id FROM slot JOIN day_template ON day_template.id = slot.day_template_id
        WHERE day_template.program_id IS NOT ? AND day_template.program_id IN (SELECT id FROM program) AND slot.id IN
        """
    }
}

private extension Slot {
    /// This slot rebuilt through `init`, which checks every range.
    func revalidated() throws(SlotValidationError) -> Slot {
        try Slot(
            id: id,
            exerciseID: exerciseID,
            sets: sets,
            reps: reps,
            repsHi: repsHi,
            rpe: rpe.value,
            restSeconds: rest.seconds,
            progression: progression,
            startLoad: startLoad,
            step: step,
            isSupersetWithPrevious: isSupersetWithPrevious,
            dropSets: dropSets,
            misses: misses
        )
    }
}
