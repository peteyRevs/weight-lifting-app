import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBProgramRepository`: criterion 2, the shared contract, and how a save diffs a program's rows in one
/// write transaction.
@Suite("GRDBProgramRepository", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramRepositoryTests {
    typealias Contract = ProgramRepositoryContract

    /// The live rows of each table, in order: program, week, day, slot, miss.
    static let liveCounts = """
    SELECT (SELECT COUNT(*) FROM program WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM program_week WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM day_template WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM slot WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM slot_miss WHERE deleted_at IS NULL)
    """

    @Test("The GRDB repository keeps the contract clause", arguments: ProgramRepositoryContract.clauses)
    func contract_clauseHolds(_ clause: ProgramRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Repositories.withProgramExercises().programs)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("Criterion 2: 8 weeks × 4 days round-trip equal, misses included, active or not")
    func eightByFour_roundTripsEqual_includingMisses() async throws {
        let programs = try await Repositories.withProgramExercises().programs
        let active = try Contract.program(number: 1, isActive: true)
        let inactive = try Contract.program(number: 2, isActive: false)
        #expect(active.weeks.count == 8 && active.days.count == 4)
        #expect(active.days.flatMap(\.slots).contains { !$0.misses.isEmpty })
        try await programs.save(active)
        try await programs.save(inactive)
        #expect(try await programs.active() == active)
        #expect(try await programs.program(id: active.id) == active)
        #expect(try await programs.program(id: inactive.id) == inactive)
        #expect(try await programs.program(id: ProgramID(EventBuilders.uuid(0xDEAD))) == nil)
    }

    @Test("A day with no slots, a week with no days and a program with no goal round-trip equal")
    func emptyParts_roundTripEqual() async throws {
        let programs = try await Repositories.withProgramExercises().programs
        var program = try Contract.program()
        program.days[2].slots = []
        program.weeks[4].schedule = [:]
        program.goal = nil
        program.daysPerWeek = nil
        try await programs.save(program)
        #expect(try await programs.active() == program)
    }

    @Test("A save is one row per week, day, slot and miss, with exact loads and the civil start date")
    func save_writesTheDocumentedColumns() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let program = try Contract.program()
        try await repositories.programs.save(program)
        #expect(try await repositories.texts(Self.liveCounts) == ["1 8 4 20 16"])
        let root = "SELECT start_date || ' ' || goal || ' ' || days_per_week || ' ' || is_active FROM program"
        #expect(try await repositories.texts(root) == ["2026-08-17 strength 4 1"])
        let slot = program.days[1].slots[1] // RPE 8, a drop set, a 21 kg start load and no step
        let columns = """
        SELECT position || ' ' || sets || ' ' || reps || ' ' || reps_hi || ' ' || rpe_x2 || ' ' || rest_seconds
            || ' ' || progression || ' ' || quote(start_load_e7g) || ' ' || quote(step_e7g) || ' '
            || is_superset_with_previous || ' ' || drop_sets
        FROM slot WHERE id = ?
        """
        #expect(try await repositories.texts(columns, [ColumnCodec.text(slot.id)]) == [
            "1 3 6 8 16 90 fixed 210000000000 NULL 0 1"
        ])
        let schedule = "SELECT quote(mon) || quote(fri) || is_deload FROM program_week WHERE week_index = 7"
        #expect(try await repositories.texts(schedule) == ["'\(ColumnCodec.text(program.days[0].id))'NULL1"])
    }

    @Test("A partial update rewrites only what changed: unchanged rows keep updated_at, removed ones are soft-deleted")
    func partialUpdate_diffsChildren() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let program = try Contract.program()
        try await repositories.programs.save(program)
        let saved = repositories.clock.timestamp
        repositories.clock.advance()
        let edited = try Contract.edited(program)
        try await repositories.programs.save(edited)
        let edit = repositories.clock.timestamp
        #expect(try await repositories.programs.active() == edited)
        // The last day went, with its 5 slots and their misses; one slot and one miss came.
        #expect(try await repositories.texts(Self.liveCounts) == ["1 8 3 16 15"])
        let deleted = """
        SELECT (SELECT COUNT(*) FROM day_template WHERE deleted_at = :edit) || ' '
            || (SELECT COUNT(*) FROM slot WHERE deleted_at = :edit) || ' '
            || (SELECT COUNT(*) FROM slot_miss WHERE deleted_at = :edit)
        """
        #expect(try await repositories.texts(deleted, ["edit": edit]) == ["1 5 6"])
        // Updated: the program, 8 weeks (schedule; one also a deload), a renamed day, day 1's first slot, and
        // the misses added. Unchanged: day 0 and day 1's rows, and every other slot.
        let updated = """
        SELECT (SELECT COUNT(*) FROM program WHERE updated_at = :edit) || ' '
            || (SELECT COUNT(*) FROM program_week WHERE updated_at = :edit) || ' '
            || (SELECT COUNT(*) FROM day_template WHERE deleted_at IS NULL AND updated_at = :edit) || ' '
            || (SELECT COUNT(*) FROM slot WHERE deleted_at IS NULL AND updated_at = :edit) || ' '
            || (SELECT COUNT(*) FROM slot WHERE deleted_at IS NULL AND updated_at = :saved)
        """
        #expect(try await repositories.texts(updated, ["edit": edit, "saved": saved]) == ["1 8 1 2 14"])
        let created = "SELECT DISTINCT created_at FROM slot WHERE deleted_at IS NULL ORDER BY created_at"
        #expect(try await repositories.texts(created) == [saved, edit])
    }

    @Test("A failure part-way through a save leaves every row as it was: one transaction")
    func failedSave_changesNothing() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let program = try Contract.program()
        try await repositories.programs.save(program)
        let before = try await repositories.texts("SELECT id || updated_at || quote(deleted_at) FROM slot ORDER BY id")
        repositories.clock.advance()
        var edited = try Contract.edited(program)
        // The last slot now names an exercise the database lacks, so its update fails after the program, its
        // weeks and days, and every other slot were written.
        edited.days[2].slots[4].exerciseID = Seeders.catalogID(4040)
        await #expect(throws: DatabaseError.self) { try await repositories.programs.save(edited) }
        #expect(try await repositories.programs.active() == program)
        let after = try await repositories.texts("SELECT id || updated_at || quote(deleted_at) FROM slot ORDER BY id")
        #expect(after == before)
        #expect(try await repositories.texts(Self.liveCounts) == ["1 8 4 20 16"])
    }

    @Test("Two days or two slots with one id are refused by name, and nothing is saved")
    func duplicateIdentifiers_areRefused() async throws {
        let programs = try await Repositories.withProgramExercises().programs
        var slots = try Contract.program()
        let slot = slots.days[0].slots[0]
        slots.days[3].slots.append(slot)
        let slotError = LedgerPersistenceError.duplicateIdentifier("slot \(ColumnCodec.text(slot.id))")
        await #expect(throws: slotError) { try await programs.save(slots) }
        var days = try Contract.program()
        days.days.append(days.days[0])
        let dayError = LedgerPersistenceError.duplicateIdentifier("day_template \(ColumnCodec.text(days.days[0].id))")
        await #expect(throws: dayError) { try await programs.save(days) }
        #expect(try await programs.active() == nil)
    }

    @Test("An inexact load is refused by name, and nothing is saved")
    func inexactLoad_isRefused() async throws {
        let programs = try await Repositories.withProgramExercises().programs
        var program = try Contract.program()
        let eighth = Weight.pounds(Decimal(string: "100.125") ?? 0)
        program.days[0].slots[0] = try Slot(
            id: program.days[0].slots[0].id,
            exerciseID: program.days[0].slots[0].exerciseID,
            sets: 3, reps: 5, repsHi: 8, rpe: 8, restSeconds: 90, progression: .linear,
            startLoad: eighth
        )
        await #expect(throws: LedgerPersistenceError.inexactWeight(eighth.grams)) { try await programs.save(program) }
        #expect(try await programs.active() == nil)
    }

    @Test("setActive of a program that is not saved, or deleted, throws by name and changes nothing")
    func setActive_unknownProgram_throws() async throws {
        let programs = try await Repositories.withProgramExercises().programs
        let program = try Contract.program()
        try await programs.save(program)
        let unknown = ProgramID(EventBuilders.uuid(0xBEEF))
        await #expect(throws: LedgerPersistenceError.missingRow("program \(ColumnCodec.text(unknown))")) {
            try await programs.setActive(unknown)
        }
        #expect(try await programs.active() == program)
        try await programs.delete(program.id)
        await #expect(throws: LedgerPersistenceError.missingRow("program \(ColumnCodec.text(program.id))")) {
            try await programs.setActive(program.id)
        }
    }
}
