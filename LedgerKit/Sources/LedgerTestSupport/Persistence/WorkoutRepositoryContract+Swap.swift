import Foundation
import LedgerDomain

/// A swapped exercise's save (F10 S8 criteria 9 and 10): history keeps the replacement and the original, and a
/// program change is compare-and-set (ADR-004 amendment §3): applied only while the slot still holds the
/// exercise the workout was built from (`WorkoutState.originalExercise(ofSlot:)`). Run where `linkedClauses`
/// run, since they need the programs.
extension WorkoutRepositoryContract {
    static let swapClauses: [Clause] = [
        Clause(
            "a swap's entry lands while its slot holds the exercise the workout began with; a slot changed since "
                + "keeps its exercise, and the workout and the other entries are stored",
            compareAndSet
        ),
        Clause(
            "storing the workout again after the slot was changed keeps the later choice; with no change, nothing",
            laterSaveKeepsTheLaterChoice
        ),
        Clause("a swap back to the exercise the slot held changes nothing, whatever the slot holds now", swapBack),
        Clause(
            "history keeps the replacement's id, name, equipment and step and the original; Last and bests follow it",
            historyKeepsTheReplacement
        )
    ]

    /// `workout` with exercise `index` built from `slot` (whose exercise is its original) and swapped for
    /// `exercise`, which brings its name, equipment and step; with `inProgram`, the slot's program change.
    static func swapping(
        _ workout: WorkoutState,
        at index: Int,
        from slot: Slot,
        to exercise: Exercise,
        inProgram: Bool = true
    ) -> WorkoutState {
        var swapped = workout
        let old = workout.exercises[index]
        swapped.exercises[index] = WorkoutExercise(
            id: old.id,
            slotID: slot.id,
            exerciseID: exercise.id,
            originalExerciseID: slot.exerciseID,
            name: exercise.name,
            equipment: exercise.equipment,
            step: exercise.equipment.defaultStep(in: workout.units),
            rest: old.rest,
            rpe: old.rpe,
            isSupersetWithPrevious: old.isSupersetWithPrevious,
            targetSets: old.targetSets,
            targetReps: old.targetReps,
            targetLoad: old.targetLoad,
            sets: old.sets,
            lastPerformance: old.lastPerformance
        )
        if inProgram {
            swapped.programUpdates[slot.id] = exercise.id
        }
        return swapped
    }

    /// The contract's exercise `id`, or its first when the contract has no such exercise.
    static func exercise(_ id: ExerciseID) -> Exercise {
        exercises.first { $0.id == id } ?? exercises[0]
    }

    /// An exercise of the contract's six that is neither of `held`.
    static func other(than held: ExerciseID...) -> ExerciseID {
        exercises.map(\.id).first { !held.contains($0) } ?? exercises[0].id
    }

    static func compareAndSet(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        let (edited, kept) = (program.days[0].slots[0], program.days[1].slots[0])
        var workout = swapping(workout(of: program), at: 0, from: edited, to: exercise(replacement(for: edited)))
        workout = swapping(workout, at: 1, from: kept, to: exercise(replacement(for: kept)))
        var changed = program // the lifter edits the first slot while the workout runs
        changed.days[0].slots[0].exerciseID = other(than: edited.exerciseID, replacement(for: edited))
        try await stores.programs.save(changed)
        try await stores.materialize(workout)
        var expected = changed
        expected.days[1].slots[0].exerciseID = replacement(for: kept)
        return try await ContractCheck.first(
            expectProgram(expected, "the program after the save", in: stores),
            ContractCheck.expect(stores.workouts.workout(id: workout.id) == stored(workout), true, "it is stored")
        )
    }

    static func laterSaveKeepsTheLaterChoice(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        let slot = program.days[0].slots[0]
        let workout = swapping(workout(of: program), at: 0, from: slot, to: exercise(replacement(for: slot)))
        try await stores.materialize(workout)
        var swapped = program
        swapped.days[0].slots[0].exerciseID = replacement(for: slot)
        let once = try await expectProgram(swapped, "after one save", in: stores)
        try await stores.materialize(workout)
        let twice = try await expectProgram(swapped, "after a second save", in: stores)
        var edited = program // the lifter's later choice: a third exercise
        edited.days[0].slots[0].exerciseID = other(than: slot.exerciseID, replacement(for: slot))
        try await stores.programs.save(edited)
        try await stores.materialize(workout) // a waiting end, a retry or a rebuild, after the edit
        return try await ContractCheck.first(
            once,
            twice,
            expectProgram(edited, "after storing it again over a later edit", in: stores),
            ContractCheck.expect(stores.workouts.recent(limit: 10) == [stored(workout)], true, "it is stored once")
        )
    }

    static func swapBack(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        let slot = program.days[0].slots[0]
        let workout = swapping(workout(of: program), at: 0, from: slot, to: exercise(slot.exerciseID))
        try await stores.materialize(workout)
        let unchanged = try await expectProgram(program, "after a swap back", in: stores)
        var edited = program
        edited.days[0].slots[0].exerciseID = replacement(for: slot)
        try await stores.programs.save(edited)
        try await stores.materialize(workout)
        return try await ContractCheck.first(
            unchanged,
            expectProgram(edited, "after a swap back stored again over a later edit", in: stores)
        )
    }

    static func historyKeepsTheReplacement(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        let original = exercises[0]
        guard let slot = program.days.flatMap(\.slots).first(where: { $0.exerciseID == original.id }) else {
            return "the contract's program has no slot of \(original.name)"
        }
        // The contract's workout performs exercises 0 to 4: the sixth is new to it, a kettlebell for a barbell,
        // whose steps differ in kilograms (2 against 2.5).
        let replacement = exercises[5]
        var base = workout(of: program)
        base.units = .kg
        let workout = swapping(base, at: 0, from: slot, to: replacement)
        try await stores.materialize(workout)
        let read = try await stores.workouts.workout(id: workout.id)?.exercises.first
        let next = Self.workout(number: 9, endedAt: workout.startedAt.addingTimeInterval(86400))
        let bests = try await stores.stats.bests(before: next, for: [replacement.id, original.id])
        return try await ContractCheck.first(
            ContractCheck.expect(read == stored(workout).exercises.first, true, "the stored exercise"),
            ContractCheck.expect(read?.exerciseID, replacement.id, "its exercise"),
            ContractCheck.expect(read?.originalExerciseID, original.id, "its original"),
            ContractCheck.expect(read?.equipment, replacement.equipment, "its equipment"),
            ContractCheck.expect(read?.step, replacement.equipment.defaultStep(in: workout.units), "its step"),
            ContractCheck.expect(stores.stats.lastPerformance(exerciseID: replacement.id) != nil, true, "its Last"),
            ContractCheck.expect(stores.stats.lastPerformance(exerciseID: original.id) == nil, true, "the original's"),
            ContractCheck.expect(bests.bestSet(of: replacement.id) != nil, true, "its best set"),
            ContractCheck.expect(bests.bestSet(of: original.id) == nil, true, "the original's best set")
        )
    }
}
