import Foundation
import LedgerDomain

/// A program update and a workout's save, on stores one database links (F11 S3 criterion 7): both write into
/// the program, and neither may undo the other. `ProgramRepositoryContract`'s update clauses say what an
/// update does alone; these need the workouts too, so they run where `linkedClauses` run.
extension WorkoutRepositoryContract {
    static let linkedUpdateClauses: [Clause] = [
        Clause(
            "a program update and a workout's save give the same program in either order: the save's misses and "
                + "swap, and the update's change",
            updateAndSaveInEitherOrder
        ),
        Clause(
            "an update that removes the slot, then the day, a stored workout came from leaves the workout as it "
                + "was; stored again, the workout skips what is gone",
            updateLeavesHistory
        )
    ]

    /// A builder's edit as a change: the block and a day renamed, a week made a deload, a slot's sets changed
    /// and the third day's last slot removed. It leaves alone the misses and the exercise of every slot it
    /// keeps, which is what lets it and a workout's save be taken in either order.
    static func builderEdit(_ stored: Program) -> Program {
        var changed = stored
        changed.name += ", edited"
        changed.days[1].name += ", edited"
        changed.weeks[5].isDeload.toggle()
        changed.days[0].slots[1].sets = changed.days[0].slots[1].sets % 12 + 1
        changed.days[2].slots.removeLast()
        return changed
    }

    /// A finished workout of `program` with what its save writes into the program: a swap on the first day's
    /// first slot and on the third day's last one, and the misses of three slots.
    static func finished(on program: Program, number: Int) -> (workout: WorkoutState, slotUpdates: [Slot]) {
        var workout = workout(of: program, number: number)
        let (swapped, removed, cleared) = (program.days[0].slots[0], program.days[2].slots[4], program.days[1].slots[1])
        workout.programUpdates = [swapped.id: replacement(for: swapped), removed.id: replacement(for: removed)]
        var slots = [swapped, removed, cleared]
        slots[0].misses = [2, 5]
        slots[1].misses = [1]
        slots[2].misses = []
        return (workout, slots)
    }

    /// `program` after `builderEdit` and the save of `finished(on:number:)`, whichever came first: the third
    /// day's last slot is gone either way, with whatever the save wrote on it.
    static func editedAndSaved(_ program: Program) -> Program {
        var expected = builderEdit(program)
        expected.days[0].slots[0].exerciseID = replacement(for: program.days[0].slots[0])
        expected.days[0].slots[0].misses = [2, 5]
        expected.days[1].slots[1].misses = []
        return expected
    }

    /// One store holds both orders, each on a program of its own.
    static func updateAndSaveInEitherOrder(_ stores: HistoryStores) async throws -> String? {
        let saveFirst = try ProgramRepositoryContract.program()
        let updateFirst = try ProgramRepositoryContract.program(number: 1, isActive: false)
        try await stores.programs.save(saveFirst)
        try await stores.programs.save(updateFirst)
        let early = finished(on: saveFirst, number: 1)
        try await stores.materialize(early.workout, slotUpdates: early.slotUpdates)
        _ = try await stores.programs.update(saveFirst.id, builderEdit)
        _ = try await stores.programs.update(updateFirst.id, builderEdit)
        let late = finished(on: updateFirst, number: 2)
        try await stores.materialize(late.workout, slotUpdates: late.slotUpdates)
        return try await ContractCheck.first(
            expectProgram(editedAndSaved(saveFirst), "the save, then the update", in: stores),
            expectProgram(editedAndSaved(updateFirst), "the update, then the save", in: stores),
            ContractCheck.expect(stores.workouts.recent(limit: 10).count, 2, "the workouts stored")
        )
    }

    /// A finished workout keeps its own name, tag and exercises, and names its day and slots by id only, so
    /// history does not change when the builder removes them (F11 notes, "What `programRepository.save` does
    /// today", sixth row).
    static func updateLeavesHistory(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        let slot = program.days[0].slots[0]
        var workout = workout(of: program)
        workout.exercises[0].slotID = slot.id
        workout.programUpdates = [slot.id: replacement(for: slot)]
        var missed = slot
        missed.misses = [2]
        try await stores.materialize(workout, slotUpdates: [missed])
        _ = try await stores.programs.update(program.id) { stored in
            var changed = stored
            changed.days[0].slots.removeFirst()
            return changed
        }
        let afterSlot = try await stores.workouts.workout(id: workout.id)
        let withoutDay = try await stores.programs.update(program.id) { stored in
            var changed = stored
            let day = changed.days.removeFirst()
            for index in changed.weeks.indices {
                changed.weeks[index].schedule = changed.weeks[index].schedule.filter { $0.value != day.id }
            }
            return changed
        }
        let afterDay = try await stores.workouts.workout(id: workout.id)
        // Stored again, as a rebuild or a recovery stores it: not refused, and nothing comes back.
        try await stores.materialize(workout, slotUpdates: [missed])
        return try await ContractCheck.first(
            ContractCheck.expect(afterSlot == stored(workout), true, "the workout is as it was, its slot removed"),
            ContractCheck.expect(afterDay == stored(workout), true, "the workout is as it was, its day removed"),
            ContractCheck.expect(withoutDay.days.map(\.id), Array(program.days.map(\.id).dropFirst()), "the days left"),
            expectProgram(withoutDay, "the program after the workout was stored again", in: stores),
            ContractCheck.expect(stores.workouts.recent(limit: 10).map(\.id), [workout.id], "the workouts stored")
        )
    }
}
