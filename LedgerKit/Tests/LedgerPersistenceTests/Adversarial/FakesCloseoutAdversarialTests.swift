import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F07 S1 close-out: the fix round's GRDB side. `unknownExercise` is raised before any row is written and counts a
/// soft-deleted exercise as stored (the foreign key's view); a row's volume beyond the column is refused on both
/// stores though every set alone fits; and an edit that fails midway (a ⅛ lb load in its last slot, after a day
/// was removed and every schedule cleared) still rolls back whole, the case `failedEdit_leavesTheSavedVersion`
/// covered before its fault moved ahead of the writes.
@Suite("Adversarial F07 S1 close-out · storage rules on GRDB", .tags(.persistence))
struct FakesCloseoutAdversarialTests {
    @Test("A slot naming a soft-deleted exercise saves, as the foreign key sees the row; a custom one too")
    func deletedAndCustomExercises_areStored() async throws {
        let stack = try await S2Kit.stack()
        try await stack.exercises.save(S2Kit.exercise(40, "Mine", isCustom: true))
        try await S2Kit.damage(
            stack.queue,
            "UPDATE exercise SET deleted_at = '2026-10-03T00:00:00Z' WHERE id = ?",
            [S2Kit.exerciseID(1).rawValue.uuidString]
        )
        var program = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 2)
        program.days[0].slots[0] = try program.days[0].slots[0].with(exercise: S2Kit.exerciseID(1))
        program.days[0].slots[1] = try program.days[0].slots[1].with(exercise: S2Kit.exerciseID(40))
        try await stack.programs.save(program)
        #expect(try await stack.programs.active() == program)
    }

    @Test("An unknown exercise is refused before any row is written, even with every other row new")
    func unknownExercise_writesNothing() async throws {
        let stack = try await S2Kit.stack()
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        var program = try S2Kit.program(3, weeks: 3, days: 3, slotsPerDay: 3)
        program.days[2].slots[2] = try program.days[2].slots[2].with(exercise: S2Kit.exerciseID(77))
        program.days[1].slots[0] = try program.days[1].slots[0].with(exercise: S2Kit.exerciseID(78))
        await #expect(
            throws: LedgerPersistenceError.unknownExercise("exercise \(S2Kit.exerciseID(78).rawValue.uuidString)")
        ) {
            try await stack.programs.save(program)
        }
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before)
    }

    @Test("A failed edit (a ⅛ lb load in the last slot, a day removed, schedules cleared) leaves every row")
    func failedEditMidway_rollsBackWhole() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program()
        try await stack.programs.save(program)
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        var days = program.days
        days.removeFirst()
        let last = days.count - 1
        let eighth = Weight.pounds(0.125)
        days[last].slots[days[last].slots.count - 1] = try days[last].slots.last.unsafelyUnwrapped.with(
            startLoad: eighth
        )
        stack.clock.advance()
        await #expect(throws: LedgerPersistenceError.inexactWeight(eighth.grams)) {
            try await stack.programs.save(program.rebuilt(weeks: [program.weeks[0], program.weeks[1]].map {
                Week(id: $0.id, index: $0.index, schedule: [:])
            }, days: days))
        }
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before)
    }

    @Test("A row whose sets each fit but whose volume does not is refused on both stores, with the same error")
    func volumeBeyondTheColumn_isRefusedAlike() async throws {
        let spec = S3Kit.SetSpec(weight: .kilograms(900_000), reps: 20, kind: .working, isDone: true)
        let sets = Array(repeating: spec, count: 62)
        let workout = S3Kit.workout(1, [S3Kit.RowSpec(S3Kit.bench, sets)])
        let stack = try await S3Kit.stack()
        let fakes = InMemoryStores()
        let stored = await HistoryModelAdversarialTests.outcome {
            try await stack.workouts.materialize(workout, slotUpdates: [])
        }
        let faked = await HistoryModelAdversarialTests.outcome {
            try await fakes.workouts.materialize(workout, slotUpdates: [])
        }
        #expect(stored.hasPrefix("threw inexactWeight"), "\(stored)")
        #expect(stored == faked)
    }

    @Test("A done set whose e1RM no column keeps, though its weight and the row's volume do, is refused alike")
    func estimateBeyondTheColumn_isRefusedAlike() async throws {
        // 700,000 t × 12 reps estimates ≈ 1.0 × 10¹⁹ units; a −700,000 t set brings the volume back to 0.
        let workout = S3Kit.workout(1, [S3Kit.RowSpec(S3Kit.bench, [
            S3Kit.SetSpec(weight: .kilograms(700_000_000), reps: 12, kind: .working, isDone: true),
            S3Kit.SetSpec(weight: .kilograms(-700_000_000), reps: 12, kind: .working, isDone: true)
        ])])
        let stack = try await S3Kit.stack()
        let fakes = InMemoryStores()
        let stored = await HistoryModelAdversarialTests.outcome {
            try await stack.workouts.materialize(workout, slotUpdates: [])
        }
        let faked = await HistoryModelAdversarialTests.outcome {
            try await fakes.workouts.materialize(workout, slotUpdates: [])
        }
        #expect(stored.hasPrefix("threw inexactWeight"), "\(stored)")
        #expect(stored == faked)
    }
}
