import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: duplicate ids. Ids are primary keys shared by every program, so an id repeated
/// inside one program, or taken from another program (a block copied without new ids, rule 18's "Start next
/// block"), must fail the save rather than land two values in one row or move a row out of the other program.
@Suite("Adversarial S2 · program ids", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramIdentityAdversarialTests {
    static func isDuplicate(_ error: any Error) -> Bool {
        if case .duplicateIdentifier = error as? LedgerPersistenceError {
            return true
        }
        return false
    }

    @Test(
        "Two slots, two days or two weeks sharing an id in one program throw `duplicateIdentifier`; nothing is written"
    )
    func duplicatesInsideOneProgram() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 3, days: 2, slotsPerDay: 2)
        var sameSlot = program.days
        sameSlot[1].slots[1] = try Slot(
            id: sameSlot[0].slots[0].id, exerciseID: S2Kit.exerciseID(3), sets: 5, reps: 5, repsHi: 6, rpe: 9,
            restSeconds: 180, progression: .fixed
        )
        var sameSlotOneDay = program.days
        sameSlotOneDay[0].slots.append(sameSlotOneDay[0].slots[0])
        var sameDay = program.days
        sameDay[1] = DayTemplate(id: sameDay[0].id, name: "Twin", tag: "TW", slots: sameDay[1].slots)
        let sameWeek = program.weeks.enumerated().map { index, week in
            Week(id: index == 2 ? program.weeks[0].id : week.id, index: week.index, schedule: week.schedule)
        }
        let cases: [(String, Program)] = try [
            ("slot across days", program.rebuilt(days: sameSlot)),
            ("slot within a day", program.rebuilt(days: sameSlotOneDay)),
            ("day", program.rebuilt(weeks: program.weeks.map { Week(id: $0.id, index: $0.index) }, days: sameDay)),
            ("week", program.rebuilt(weeks: sameWeek))
        ]
        for (label, broken) in cases {
            await #expect(Comment(rawValue: label)) {
                try await stack.programs.save(broken)
            } throws: { Self.isDuplicate($0) }
            #expect(try await S2Kit.count(stack.queue, "program") == 0, "\(label): something was written")
        }
    }

    enum Taken: String, CaseIterable, Sendable {
        case slot, day, week
    }

    /// Program 2, with one of program 1's ids in place of its own.
    static func copy(taking taken: Taken, from first: Program) throws -> Program {
        let base = try S2Kit.program(2, weeks: 3, days: 2, slotsPerDay: 2, isActive: false)
        switch taken {
        case .slot:
            var days = base.days
            days[0].slots[0] = try first.days[0].slots[0].with(sets: 1, misses: [])
            return try base.rebuilt(days: days)
        case .day:
            var days = base.days
            days[0] = DayTemplate(id: first.days[0].id, name: "Stolen", tag: "ST", slots: base.days[0].slots)
            return try base.rebuilt(weeks: base.weeks.map { Week(id: $0.id, index: $0.index) }, days: days)
        case .week:
            return try base.rebuilt(weeks: base.weeks.map { week in
                Week(id: week.index == 0 ? first.weeks[0].id : week.id, index: week.index, schedule: [:])
            })
        }
    }

    /// Finding S2-1: the save succeeds and moves the row into program 2. A taken slot leaves program 1 a slot
    /// short, and program 2 then reads program 1's misses as its own; a taken day or week makes program 1
    /// unreadable (`danglingSchedule` or `nonContiguousWeeks`), so `active()` throws on every launch.
    @Test(
        "A second program reusing the first one's slot, day or week id fails, and the first program is unchanged",
        arguments: Taken.allCases
    )
    func idsOfAnotherProgram_areRefused(taken: Taken) async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2, isActive: true)
        try await stack.programs.save(first)
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        let copy = try Self.copy(taking: taken, from: first)
        let saved = await Result { try await stack.programs.save(copy) }
        #expect((try? saved.get()) == nil, "the save succeeded")
        let reread = await Result { try await stack.programs.active() }
        let slots = reread.map { $0?.days.flatMap(\.slots).count ?? -1 }
        #expect((try? reread.get()) == first, "program 1 now reads as \(slots) slots")
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before, "rows changed")
        if case .success = saved {
            let copyRead = await Result { try await stack.programs.program(id: copy.id) }
            #expect((try? copyRead.get()) == copy, "program 2 reads back as another program")
        }
    }

    @Test("A second program reusing a deleted program's ids fails too, and the deleted rows stay as they were")
    func idsOfADeletedProgram_areRefused() async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 2, isActive: true)
        try await stack.programs.save(first)
        try await stack.programs.delete(first.id)
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        let base = try S2Kit.program(2, weeks: 2, days: 1, slotsPerDay: 2, isActive: true)
        var days = base.days
        days[0].slots[1] = first.days[0].slots[1]
        let copy = try base.rebuilt(days: days)
        let saved = await Result { try await stack.programs.save(copy) }
        #expect((try? saved.get()) == nil, "the save succeeded")
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before)
        try await stack.programs.save(first)
        #expect(try await stack.programs.program(id: first.id) == first, "program 1 restores whole")
        if case .success = saved {
            let copyRead = await Result { try await stack.programs.program(id: copy.id) }
            let inactiveCopy = try copy.withActive(false)
            #expect((try? copyRead.get()) == inactiveCopy, "restoring program 1 took the slot back from program 2")
        }
    }
}
