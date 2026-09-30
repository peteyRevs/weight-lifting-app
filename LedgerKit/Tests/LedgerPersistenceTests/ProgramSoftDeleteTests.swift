import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// ADR-002's soft deletes on the program tables, the one active program, and `slot_miss` ids derived from
/// their slot and week, so every device writes one id per miss.
@Suite("GRDBProgramRepository · rows", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramSoftDeleteTests {
    typealias Contract = ProgramRepositoryContract

    static let allRows = """
    SELECT (SELECT COUNT(*) FROM program) + (SELECT COUNT(*) FROM program_week) + (SELECT COUNT(*) FROM day_template)
        + (SELECT COUNT(*) FROM slot) + (SELECT COUNT(*) FROM slot_miss)
    """

    @Test("delete soft-deletes every row of the program in one stamp, keeps them, and a save revives them")
    func delete_softDeletesEveryRow_andASaveRevivesThem() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let program = try Contract.program()
        try await repositories.programs.save(program)
        let created = repositories.clock.timestamp
        repositories.clock.advance()
        try await repositories.programs.delete(program.id)
        let deleted = repositories.clock.timestamp
        let stamps = """
        SELECT DISTINCT deleted_at FROM (SELECT deleted_at FROM program UNION ALL SELECT deleted_at FROM program_week
            UNION ALL SELECT deleted_at FROM day_template UNION ALL SELECT deleted_at FROM slot
            UNION ALL SELECT deleted_at FROM slot_miss)
        """
        #expect(try await repositories.texts(stamps) == [deleted])
        #expect(try await repositories.count(Self.allRows) == 1 + 8 + 4 + 20 + 16)
        #expect(try await repositories.programs.program(id: program.id) == nil)
        repositories.clock.advance()
        try await repositories.programs.save(program)
        #expect(try await repositories.programs.active() == program)
        #expect(try await repositories.count(Self.allRows) == 1 + 8 + 4 + 20 + 16)
        let kept = "SELECT DISTINCT created_at FROM slot UNION SELECT DISTINCT created_at FROM program"
        #expect(try await repositories.texts(kept) == [created])
    }

    @Test("setActive flips only the flags that change, and saving the active program again writes nothing")
    func setActive_touchesOnlyChangedRows() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let first = try Contract.program(number: 1, isActive: true)
        let second = try Contract.program(number: 2, isActive: false)
        let third = try Contract.program(number: 3, isActive: false)
        for program in [first, second, third] {
            try await repositories.programs.save(program)
        }
        let saved = repositories.clock.timestamp
        repositories.clock.advance()
        try await repositories.programs.setActive(second.id)
        try await repositories.programs.save(second.activated)
        let flags = "SELECT name || ' ' || is_active || ' ' || (updated_at = ?) FROM program ORDER BY name"
        #expect(try await repositories.texts(flags, [saved]) == ["Block 1 0 0", "Block 2 1 0", "Block 3 0 1"])
        let changed = "SELECT COUNT(*) FROM slot WHERE updated_at != ?"
        #expect(try await repositories.count(changed, [saved]) == 0)
    }

    @Test("A miss's id is the version-5 UUID of its slot and week: fixed, and revived when the miss comes back")
    func missIDs_areDerived_andRevived() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let program = try Contract.program()
        let slot = program.days[0].slots[1]
        let id = SlotMissRecord.id(slot: slot.id, week: 2)
        #expect(id == SlotMissRecord.id(slot: slot.id, week: 2))
        #expect(id != SlotMissRecord.id(slot: slot.id, week: 3))
        #expect(id != SlotMissRecord.id(slot: program.days[0].slots[3].id, week: 2))
        #expect(id.uuidString.dropFirst(14).first == "5") // the version nibble
        #expect("89AB".contains(id.uuidString.dropFirst(19).first ?? "?")) // the RFC 9562 variant
        try await repositories.programs.save(program)
        let row = "SELECT week_index || ' ' || quote(deleted_at) FROM slot_miss WHERE id = ?"
        #expect(try await repositories.texts(row, [id.uuidString]) == ["2 NULL"])
        var cleared = program
        cleared.days[0].slots[1].misses = []
        try await repositories.programs.save(cleared)
        #expect(try await repositories.texts(row, [id.uuidString]) == ["2 '\(repositories.clock.timestamp)'"])
        try await repositories.programs.save(program)
        #expect(try await repositories.texts(row, [id.uuidString]) == ["2 NULL"])
        #expect(try await repositories.count("SELECT COUNT(*) FROM slot_miss") == 16)
    }
}

private extension Program {
    var activated: Program {
        var program = self
        program.isActive = true
        return program
    }
}
