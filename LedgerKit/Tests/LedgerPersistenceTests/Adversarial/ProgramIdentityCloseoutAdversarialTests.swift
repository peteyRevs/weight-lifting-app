import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 close-out round, S2-1 / B1 variants: ids that another program holds as soft-deleted rows (a removed
/// week, day or slot, a slot under a removed day, a deleted program), several taken at once, and taken ids
/// beside new ones. Each refusal must leave both programs byte for byte, and both must save again afterwards.
@Suite("Adversarial S2 close-out · program ids", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramIdentityCloseoutAdversarialTests {
    enum Takeover: String, CaseIterable, Sendable {
        case weekOfADeletedProgram, dayOfADeletedProgram, slotOfADeletedProgram
        case removedWeek, removedDay, removedSlot, slotOfARemovedDay
        case weekAndSlot, dayAndSlot, lastSlotAmongNewOnes
    }

    @Test(
        "A takeover of another program's live or deleted ids is refused; both programs keep every byte and save again",
        arguments: Takeover.allCases
    )
    func takeover_isRefused_andBothProgramsSaveAgain(takeover: Takeover) async throws {
        let stack = try await S2Kit.stack()
        let original = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2, isActive: true)
        let first = try await Self.prepare(takeover, original, in: stack)
        let second = try S2Kit.program(2, weeks: 3, days: 2, slotsPerDay: 2, isActive: false)
        try await stack.programs.save(second)
        stack.clock.advance()
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        let taken = try Self.taking(takeover, from: original, into: second)
        await #expect(Comment(rawValue: "not refused by id")) {
            try await stack.programs.save(taken)
        } throws: { ProgramIdentityAdversarialTests.isDuplicate($0) }
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before, "rows changed")
        #expect(try await stack.programs.program(id: second.id) == second)

        // Both programs save again afterwards: program 1 restored or edited, program 2 edited with its own ids.
        stack.clock.advance()
        let firstAgain = try first.rebuilt(name: "Block 1, again")
        try await stack.programs.save(firstAgain)
        let secondAgain = try second.rebuilt(name: "Block 2, again")
        try await stack.programs.save(secondAgain)
        #expect(try await stack.programs.program(id: first.id) == firstAgain)
        #expect(try await stack.programs.program(id: second.id) == secondAgain)
        #expect(try await stack.programs.active() == firstAgain)
        #expect(try await S2Kit.liveCounts(stack.queue) == S2Kit.expectedCounts([firstAgain, secondAgain]))
    }

    @Test("The refusal names the table and the first id taken, weeks before days before slots")
    func refusal_namesTheTableAndID() async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2, isActive: true)
        try await stack.programs.save(first)
        let second = try S2Kit.program(2, weeks: 3, days: 2, slotsPerDay: 2, isActive: false)
        let both = try Self.taking(.weekAndSlot, from: first, into: second)
        let weekID = first.weeks[1].id.rawValue
        await #expect(throws: LedgerPersistenceError.duplicateIdentifier("program_week \(weekID)")) {
            try await stack.programs.save(both)
        }
        let slotOnly = try Self.taking(.lastSlotAmongNewOnes, from: first, into: second)
        let slotID = first.days[1].slots[1].id.rawValue
        await #expect(throws: LedgerPersistenceError.duplicateIdentifier("slot \(slotID)")) {
            try await stack.programs.save(slotOnly)
        }
    }

    /// (documents) Ids are primary keys per table, so the check is per table: program 1's slot id as program 2's
    /// day id, and its day id as a week id, collide with nothing, and both programs read back.
    @Test("(documents) An id another program uses in a different table is accepted")
    func idsReusedAcrossTables_areAccepted() async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 2, isActive: true)
        try await stack.programs.save(first)
        let base = try S2Kit.program(2, weeks: 2, days: 1, slotsPerDay: 2, isActive: false)
        let dayID = DayTemplateID(first.days[0].slots[0].id.rawValue)
        let day = DayTemplate(id: dayID, name: "Odd", tag: "OD", slots: base.days[0].slots)
        let weeks = [
            Week(id: WeekID(first.days[0].id.rawValue), index: 0, schedule: [.monday: dayID]),
            Week(id: base.weeks[1].id, index: 1, schedule: [.monday: dayID])
        ]
        let second = try base.rebuilt(weeks: weeks, days: [day])
        try await stack.programs.save(second)
        #expect(try await stack.programs.program(id: first.id) == first)
        #expect(try await stack.programs.program(id: second.id) == second)
    }

    /// Notes, decision 4: "a save repairs a damaged row rather than failing on it". A week or day whose
    /// `program_id` names no program (damage, a foreign writer) belongs to no other program, so a save of its
    /// own program should take it back, as it did before fix round 1. A slot whose `day_template_id` names no
    /// day is repaired.
    @Test(
        "A save repairs a week or day whose program_id names no program",
        arguments: [
            "UPDATE day_template SET program_id = 'nope' WHERE id = ?",
            "UPDATE day_template SET program_id = CAST(program_id AS BLOB) WHERE id = ?",
            "UPDATE program_week SET program_id = 'nope' WHERE id = ?",
            "UPDATE slot SET day_template_id = 'nope' WHERE id = ?"
        ]
    )
    func danglingParent_isRepairedBySave(damage: String) async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 2, days: 2, slotsPerDay: 2, isActive: true)
        try await stack.programs.save(first)
        let target = damage.hasPrefix("UPDATE day_template") ? ColumnCodec.text(first.days[1].id)
            : damage.hasPrefix("UPDATE program_week") ? ColumnCodec.text(first.weeks[1].id)
            : ColumnCodec.text(first.days[1].slots[0].id)
        try await S2Kit.damage(stack.queue, damage, [target])
        let saved = await Result { try await stack.programs.save(first) }
        #expect(throws: Never.self, "the save is refused") { try saved.get() }
        let reread = await Result { try await stack.programs.active() }
        #expect((try? reread.get()) == first, "program 1 stays unreadable: \(reread)")
    }
}

extension ProgramIdentityCloseoutAdversarialTests {
    /// Program 1 as stored before the takeover: whole, with a week, a day or a slot removed, or deleted.
    static func prepare(_ takeover: Takeover, _ first: Program, in stack: S2Kit.Stack) async throws -> Program {
        try await stack.programs.save(first)
        stack.clock.advance()
        switch takeover {
        case .weekOfADeletedProgram, .dayOfADeletedProgram, .slotOfADeletedProgram:
            try await stack.programs.delete(first.id)
            return first
        case .removedWeek:
            let shorter = try first.rebuilt(weeks: Array(first.weeks.prefix(2)))
            try await stack.programs.save(shorter)
            return shorter
        case .removedDay, .slotOfARemovedDay:
            let weeks = first.weeks.map { Week(id: $0.id, index: $0.index, schedule: [.monday: first.days[0].id]) }
            let oneDay = try first.rebuilt(weeks: weeks, days: [first.days[0]])
            try await stack.programs.save(oneDay)
            return oneDay
        case .removedSlot:
            var days = first.days
            days[0].slots.removeLast()
            let fewer = try first.rebuilt(days: days)
            try await stack.programs.save(fewer)
            return fewer
        case .weekAndSlot, .dayAndSlot, .lastSlotAmongNewOnes:
            return first
        }
    }

    static func slot(_ id: SlotID) throws -> Slot {
        try Slot(
            id: id, exerciseID: S2Kit.exerciseID(6), sets: 4, reps: 6, repsHi: 8, rpe: 8.5, restSeconds: 150,
            progression: .fixed
        )
    }

    /// Program 2 (already stored, with its own ids), edited to hold ids of program 1 as first saved (`first`,
    /// before `prepare` removed anything), as `takeover` says.
    static func taking(_ takeover: Takeover, from first: Program, into second: Program) throws -> Program {
        var weeks = second.weeks
        var days = second.days
        func takeWeek(_ index: Int) {
            weeks[index] = Week(id: first.weeks[index].id, index: index, schedule: weeks[index].schedule)
        }
        func takeDay() {
            days[0] = DayTemplate(id: first.days[1].id, name: "Taken", tag: "TK", slots: days[0].slots)
            weeks = weeks.map { Week(id: $0.id, index: $0.index, schedule: [.tuesday: first.days[1].id]) }
        }
        switch takeover {
        case .weekOfADeletedProgram, .removedWeek:
            takeWeek(2)
        case .dayOfADeletedProgram, .removedDay:
            takeDay()
        case .slotOfADeletedProgram, .removedSlot:
            days[1].slots[0] = try slot(first.days[0].slots[1].id)
        case .slotOfARemovedDay:
            days[1].slots[1] = try slot(first.days[1].slots[0].id)
        case .weekAndSlot:
            takeWeek(1)
            days[1].slots[1] = try slot(first.days[1].slots[1].id)
        case .dayAndSlot:
            takeDay()
            days[1].slots[0] = try slot(first.days[0].slots[0].id)
        case .lastSlotAmongNewOnes:
            days[1].slots += try (0 ..< 3).map { try slot(SlotID(S2Kit.uuid(0x77, $0))) }
            try days[1].slots.append(slot(first.days[1].slots[1].id))
        }
        return try second.rebuilt(weeks: weeks, days: days)
    }
}
