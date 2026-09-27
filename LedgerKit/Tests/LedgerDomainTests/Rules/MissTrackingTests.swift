import Foundation
@testable import LedgerDomain
import Testing

@Suite("MissTracking", .tags(.domain))
struct MissTrackingTests {
    private func slot(misses: Set<Int> = []) throws -> Slot {
        try Fixtures.slot(Fixtures.bench, id: 1, sets: 5, reps: 5, misses: misses)
    }

    /// Five working sets of 185 × 5 (target 5 × 5), with `changes` applied by index.
    private func bench(
        _ changes: [Int: (reps: Int, done: Bool)] = [:],
        extra: [LoggedSet] = []
    ) throws -> WorkoutExercise {
        let working = (0 ..< 5).map { index in
            Fixtures.set(index, pounds: 185, reps: changes[index]?.reps ?? 5, done: changes[index]?.done ?? true)
        }
        return try Fixtures.workoutExercise(
            Fixtures.bench,
            index: 0,
            sets: working + extra,
            targetSets: 5,
            targetReps: 5
        )
    }

    private func update(_ exercise: WorkoutExercise, slot: Slot, week: Int = 3, deload: Bool = false) -> Slot {
        MissTracking.update(slot: slot, exercise: exercise, weekIndex: week, isDeload: deload)
    }

    @Test("A working set short of target reps marks the week missed (decision #5, criterion 11)")
    func workingSetShortOfTargetReps_marksWeekMissed() throws {
        let updated = try update(bench([1: (reps: 4, done: true)]), slot: slot())
        #expect(updated.misses == [3])
    }

    @Test("Fewer done working sets than prescribed marks the week missed (decision #5)")
    func fewerWorkingSetsThanPrescribed_marksMissed() throws {
        #expect(try update(bench([4: (reps: 5, done: false)]), slot: slot()).misses == [3])
        let fourRows = try Fixtures.workoutExercise(
            Fixtures.bench, index: 0, sets: (0 ..< 4).map { Fixtures.set($0, pounds: 185, reps: 5) },
            targetSets: 5, targetReps: 5
        )
        #expect(try update(fourRows, slot: slot()).misses == [3])
    }

    @Test("A short or undone drop set does not mark the week missed (decision #5, criterion 11)")
    func shortDropSet_doesNotMarkMissed() throws {
        let shortDrop = [Fixtures.set(9, pounds: 155, reps: 2, kind: .drop)]
        let undoneDrop = [Fixtures.set(9, pounds: 155, reps: 5, kind: .drop, done: false)]
        #expect(try update(bench(extra: shortDrop), slot: slot()).misses.isEmpty)
        #expect(try update(bench(extra: undoneDrop), slot: slot()).misses.isEmpty)
    }

    @Test("A short added set does not mark the week missed, nor mask a miss (decision #5)")
    func shortAddedSet_doesNotMarkMissed() throws {
        let shortAdded = [Fixtures.set(9, pounds: 185, reps: 1, kind: .added)]
        #expect(try update(bench(extra: shortAdded), slot: slot()).misses.isEmpty)
        let masking = [Fixtures.set(9, pounds: 185, reps: 5, kind: .added)]
        #expect(try update(bench([4: (reps: 5, done: false)], extra: masking), slot: slot()).misses == [3])
    }

    @Test("Deload weeks never change misses (decision #5, criterion 11)")
    func deloadWeek_neverMarksMissed() throws {
        let short = try bench([1: (reps: 4, done: true)])
        #expect(try update(short, slot: slot(), deload: true) == slot())
        let previouslyMissed = try slot(misses: [3])
        #expect(try update(bench(), slot: previouslyMissed, deload: true) == previouslyMissed)
    }

    @Test("A successful week removes a previous miss for that week (rule 13)")
    func successfulWeek_removesPriorMiss() throws {
        let updated = try update(bench(), slot: slot(misses: [1, 3]))
        #expect(updated.misses == [1])
    }

    @Test("Applying the same result twice gives the same slot")
    func update_isIdempotent() throws {
        for exercise in try [bench(), bench([2: (reps: 3, done: true)])] {
            let once = try update(exercise, slot: slot(misses: [0]))
            #expect(update(exercise, slot: once) == once)
        }
    }

    @Test("A skipped week is recorded for every slot unless it is a deload week or outside the block (decision #18)")
    func recordSkippedWeek_marksEverySlot() throws {
        let program = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let skipped = MissTracking.recordSkippedWeek(2, in: program)
        let allSlots = skipped.days.flatMap(\.slots)
        #expect(allSlots.count == 6)
        #expect(allSlots.allSatisfy { $0.misses == [2] })
        #expect(MissTracking.recordSkippedWeek(7, in: program) == program)
        #expect(MissTracking.recordSkippedWeek(8, in: program) == program)
    }
}
