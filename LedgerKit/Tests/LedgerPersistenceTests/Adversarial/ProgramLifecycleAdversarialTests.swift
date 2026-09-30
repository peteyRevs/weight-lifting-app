import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: which program is active, soft deletes, and saves after a delete.
@Suite("Adversarial S2 · program lifecycle", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramLifecycleAdversarialTests {
    static func activeCount(_ queue: DatabaseQueue) async throws -> Int {
        try await queue.read { database in
            try Int
                .fetchOne(database, sql: "SELECT COUNT(*) FROM program WHERE is_active = 1 AND deleted_at IS NULL") ??
                -1
        }
    }

    @Test("Saving an active program makes every other one inactive; `active()` is always the last one saved active")
    func savingActive_deactivatesTheOthers() async throws {
        let stack = try await S2Kit.stack()
        let programs = try (1 ... 4).map { try S2Kit.program($0, weeks: 2, days: 1, slotsPerDay: 1, isActive: true) }
        for program in programs {
            try await stack.programs.save(program)
            #expect(try await stack.programs.active() == program)
            #expect(try await Self.activeCount(stack.queue) == 1)
        }
        for program in programs.dropLast() {
            #expect(try await stack.programs.program(id: program.id)?.isActive == false)
        }
    }

    @Test("Saving an inactive edit of the active program leaves no program active")
    func savingInactive_deactivates() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 1, isActive: true)
        try await stack.programs.save(program)
        try await stack.programs.save(program.withActive(false))
        #expect(try await stack.programs.active() == nil)
    }

    @Test("`setActive` switches the one active program and returns it with `isActive` true")
    func setActive_switches() async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 1, isActive: true)
        let second = try S2Kit.program(2, weeks: 2, days: 1, slotsPerDay: 1, isActive: false)
        try await stack.programs.save(first)
        try await stack.programs.save(second)
        try await stack.programs.setActive(second.id)
        #expect(try await stack.programs.active() == second.withActive(true))
        #expect(try await stack.programs.program(id: first.id) == first.withActive(false))
        try await stack.programs.setActive(second.id)
        #expect(try await Self.activeCount(stack.queue) == 1)
    }

    @Test("`setActive` on an unknown or deleted program throws `missingRow` and keeps the active one")
    func setActive_missing_throws() async throws {
        let stack = try await S2Kit.stack()
        let active = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 1, isActive: true)
        let deleted = try S2Kit.program(2, weeks: 2, days: 1, slotsPerDay: 1, isActive: false)
        try await stack.programs.save(active)
        try await stack.programs.save(deleted)
        try await stack.programs.delete(deleted.id)
        for id in [deleted.id, S2Kit.programID(99)] {
            await #expect {
                try await stack.programs.setActive(id)
            } throws: { error in
                guard case .missingRow = error as? LedgerPersistenceError else {
                    return false
                }
                return true
            }
        }
        #expect(try await stack.programs.active() == active)
    }

    @Test("Deleting the active program leaves none active; deleting twice or an unknown id does nothing")
    func deleteActive() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program()
        try await stack.programs.save(program)
        try await stack.programs.delete(program.id)
        #expect(try await stack.programs.active() == nil)
        #expect(try await stack.programs.program(id: program.id) == nil)
        #expect(try await S2Kit.liveCounts(stack.queue).values.allSatisfy { $0 == 0 })
        let rows = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        stack.clock.advance()
        try await stack.programs.delete(program.id)
        try await stack.programs.delete(S2Kit.programID(99))
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == rows, "a second delete rewrote rows")
    }

    @Test("A deleted program saved again comes back whole, and an edited re-save brings back only what it lists")
    func saveAfterDelete_restores() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program()
        try await stack.programs.save(program)
        try await stack.programs.delete(program.id)
        try await stack.programs.save(program)
        #expect(try await stack.programs.active() == program)
        try await stack.programs.delete(program.id)
        var days = program.days
        days[0].slots.removeAll()
        days[1].slots[0] = try days[1].slots[0].with(misses: [])
        let edited = try program.rebuilt(days: days)
        try await stack.programs.save(edited)
        #expect(try await stack.programs.program(id: program.id) == edited)
        #expect(try await S2Kit.liveCounts(stack.queue) == S2Kit.expectedCounts([edited]))
    }

    @Test("Deleting one program leaves another program's rows untouched")
    func delete_isScopedToItsProgram() async throws {
        let stack = try await S2Kit.stack()
        let kept = try S2Kit.program(1, isActive: false)
        let gone = try S2Kit.program(2, isActive: true)
        try await stack.programs.save(kept)
        try await stack.programs.save(gone)
        try await stack.programs.delete(gone.id)
        #expect(try await stack.programs.program(id: kept.id) == kept)
        #expect(try await S2Kit.liveCounts(stack.queue) == S2Kit.expectedCounts([kept]))
    }

    /// Sync (M4) can merge two devices that each made a different program active. Two live `is_active` rows
    /// must not make `active()` fail or flip between calls.
    @Test("(documents) With two active rows, `active()` returns one of them, the same one every time")
    func twoActiveRows_readDeterministically() async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 1, isActive: true)
        let second = try S2Kit.program(2, weeks: 2, days: 1, slotsPerDay: 1, isActive: false)
        try await stack.programs.save(first)
        try await stack.programs.save(second)
        try await S2Kit.damage(stack.queue, "UPDATE program SET is_active = 1")
        let read = try await stack.programs.active()
        let secondActive = try second.withActive(true)
        #expect(read == first || read == secondActive)
        for _ in 0 ..< 5 {
            #expect(try await GRDBProgramRepository(stack.queue).active() == read)
        }
    }
}
