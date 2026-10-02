import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: saving an edited program diffs its child rows. Moves across days, removals
/// and re-additions of the same ids, reorders, and what an edit does to `updated_at` and `deleted_at`.
@Suite("Adversarial S2 · program edits", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramEditAdversarialTests {
    static func saveAndExpect(_ program: Program, _ stack: S2Kit.Stack, _ comment: Comment? = nil) async throws {
        stack.clock.advance()
        try await stack.programs.save(program)
        #expect(try await stack.programs.program(id: program.id) == program, comment)
        #expect(try await S2Kit.liveCounts(stack.queue) == S2Kit.expectedCounts([program]), comment)
    }

    @Test("A slot moved to another day while its old day is removed, in one save, survives with its misses")
    func moveSlot_andRemoveItsDay_inOneSave() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 3, days: 3, slotsPerDay: 3)
        try await stack.programs.save(program)
        var days = program.days
        let moved = try days[0].slots[1].with(misses: [0, 2])
        days[2].slots.insert(moved, at: 0)
        days.remove(at: 0)
        let weeks = program.weeks.map { week in
            Week(id: week.id, index: week.index, isDeload: week.isDeload, schedule: week.schedule.filter {
                $0.value != program.days[0].id
            })
        }
        try await Self.saveAndExpect(program.rebuilt(weeks: weeks, days: days), stack)
    }

    @Test("Slots swapped between two days in one save both land in their new day")
    func swapSlotsAcrossDays() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        var days = program.days
        let first = days[0].slots
        days[0].slots = days[1].slots.reversed()
        days[1].slots = first.reversed()
        try await Self.saveAndExpect(program.rebuilt(days: days), stack)
    }

    @Test("A removed slot, day, week and miss come back when re-added with the same ids")
    func removedRows_comeBack_whenReAdded() async throws {
        let stack = try await S2Kit.stack()
        let original = try S2Kit.program(weeks: 4, days: 3, slotsPerDay: 3)
        try await stack.programs.save(original)
        var days = original.days
        let removedDay = days.remove(at: 1)
        days[0].slots.remove(at: 2)
        days[1].slots[0] = try days[1].slots[0].with(misses: [])
        let weeks = original.weeks.dropLast().map { week in
            Week(id: week.id, index: week.index, isDeload: false, schedule: week.schedule.filter {
                $0.value != removedDay.id
            })
        }
        try await Self.saveAndExpect(original.rebuilt(weeks: Array(weeks), days: days), stack, "removal")
        try await Self.saveAndExpect(original, stack, "re-added")
        #expect(try await S2Kit.count(stack.queue, "slot") == S2Kit.expectedCounts([original])["slot"], "no second row")
    }

    @Test("Reordering slots and days, and renumbering weeks' schedules, round-trips every time")
    func reorders_roundTrip() async throws {
        let stack = try await S2Kit.stack()
        var program = try S2Kit.program(weeks: 4, days: 4, slotsPerDay: 5)
        try await stack.programs.save(program)
        var generator = SeededGenerator(seed: 23)
        for _ in 0 ..< 12 {
            var days = program.days.shuffled(using: &generator)
            for index in days.indices {
                days[index].slots.shuffle(using: &generator)
            }
            let weeks = program.weeks.map { week in
                let shuffled = Array(week.schedule.values).shuffled(using: &generator)
                let schedule = Dictionary(uniqueKeysWithValues: zip(
                    Weekday.allCases.shuffled(using: &generator),
                    shuffled
                ))
                return Week(
                    id: week.id,
                    index: week.index,
                    isDeload: Bool.random(using: &generator),
                    schedule: schedule
                )
            }
            program = try program.rebuilt(weeks: weeks, days: days)
            try await Self.saveAndExpect(program, stack)
        }
    }

    @Test("Growing a block from 2 to 20 weeks and back keeps the other rows")
    func weeksGrowAndShrink() async throws {
        let stack = try await S2Kit.stack()
        let base = try S2Kit.program(weeks: 2, days: 2, slotsPerDay: 2)
        try await stack.programs.save(base)
        let long = (0 ..< 20).map { index in
            Week(id: S2Kit.weekID(5000 + index), index: index, isDeload: index.isMultiple(of: 4), schedule: [
                .friday: base.days[index % 2].id
            ])
        }
        try await Self.saveAndExpect(base.rebuilt(weeks: long), stack, "grown")
        try await Self.saveAndExpect(base, stack, "shrunk to the original weeks")
    }

    @Test("A failed save (an unknown exercise in the last slot) leaves the saved version and every row as they were")
    func failedEdit_leavesTheSavedVersion() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program()
        try await stack.programs.save(program)
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        var days = program.days
        days.removeFirst()
        let last = days.count - 1
        days[last].slots[days[last].slots.count - 1] = try days[last].slots.last.unsafelyUnwrapped.with(
            exercise: S2Kit.exerciseID(77)
        )
        stack.clock.advance()
        await #expect(throws: DatabaseError.self) {
            try await stack.programs.save(program.rebuilt(weeks: [program.weeks[0], program.weeks[1]].map {
                Week(id: $0.id, index: $0.index, schedule: [:])
            }, days: days))
        }
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before)
    }

    @Test("A slot or week mutated out of range through `var` is refused at save, and nothing is written")
    func directMutation_isRefusedAtSave() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 3, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        let slotEdits: [(inout Slot) -> Void] = [
            { $0.sets = 13 }, { $0.sets = 0 }, { $0.reps = 31 }, { $0.repsHi = $0.reps }, { $0.repsHi = 41 },
            { $0.dropSets = 2 }, { $0.startLoad = .pounds(-5) }, { $0.step = .zero }, { $0.step = .pounds(-2.5) }
        ]
        for (index, edit) in slotEdits.enumerated() {
            var broken = program
            edit(&broken.days[1].slots[1])
            await #expect(throws: SlotValidationError.self, "slot edit \(index)") {
                try await stack.programs.save(broken)
            }
        }
        let weekEdits: [(inout Program) -> Void] = [
            { $0.weeks.removeLast(2) }, { $0.weeks[2].index = 5 }, { $0.weeks[1].index = 0 },
            { $0.weeks[0].schedule[.sunday] = S2Kit.dayID(4242) }, { $0.days.removeFirst() }
        ]
        for (index, edit) in weekEdits.enumerated() {
            var broken = program
            edit(&broken)
            await #expect(throws: ProgramValidationError.self, "program edit \(index)") {
                try await stack.programs.save(broken)
            }
        }
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before)
    }
}
