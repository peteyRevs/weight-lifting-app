import Foundation
import LedgerDomain
import LedgerPersistence

/// Set edits, deletion, misses, ids, U+0000 and observation.
extension WorkoutRepositoryContract {
    static func updateSets(_ stores: HistoryStores) async throws -> String? {
        let workout = workout()
        try await stores.materialize(workout)
        var edited = workout
        var sets = workout.exercises[1].sets
        sets.removeFirst()
        sets[0].weight = .pounds(60)
        sets[1].doneAt = nil
        sets.append(LoggedSet(
            id: .derived(from: workout.exercises[1].id, index: 9),
            weight: .pounds(50),
            reps: Reps(clamping: 12),
            kind: .added,
            doneAt: workout.endedAt
        ))
        edited.exercises[1].sets = sets
        try await stores.workouts.updateSets(workoutExerciseID: workout.exercises[1].id, sets: sets)
        let unknown = WorkoutExerciseID(EventBuilders.uuid(0x404))
        let missing = await ContractCheck.expectError(
            LedgerPersistenceError.missingRow(key("workout_exercise", unknown))
        ) { try await stores.workouts.updateSets(workoutExerciseID: unknown, sets: sets) }
        return try await ContractCheck.first(
            missing,
            ContractCheck.expect(stores.workouts.workout(id: workout.id), edited, "workout(id:) after updateSets")
        )
    }

    static func deleteHides(_ stores: HistoryStores) async throws -> String? {
        let kept = workout(number: 1)
        let deleted = workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(3600))
        try await stores.materialize(kept)
        try await stores.materialize(deleted)
        try await stores.workouts.delete(id: deleted.id)
        try await stores.workouts.delete(id: deleted.id) // a second delete does nothing
        try await stores.workouts.delete(id: Seeders.workoutID(404)) // nor does an unknown id
        let afterDelete = try await stores.workouts.recent(limit: 10)
        let byID = try await stores.workouts.workout(id: deleted.id)
        let edits = await ContractCheck.expectError(
            LedgerPersistenceError.missingRow(key("workout_exercise", deleted.exercises[0].id))
        ) { try await stores.workouts.updateSets(workoutExerciseID: deleted.exercises[0].id, sets: []) }
        try await stores.materialize(deleted)
        return try await ContractCheck.first(
            ContractCheck.expect(afterDelete, [kept], "recent after delete"),
            ContractCheck.expect(byID, nil, "workout(id:) after delete"),
            edits,
            ContractCheck.expect(
                stores.workouts.recent(limit: 10),
                [deleted, kept],
                "recent after materialising it again"
            )
        )
    }

    static func writesMisses(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        var expected = program
        expected.days[0].slots[0].misses = [2, 5] // had none
        expected.days[0].slots[1].misses = [] // had two
        expected.days[1].slots[1].misses.insert(7) // keeps the two it had
        var resized = expected.days[2].slots[0] // only misses are written: this edit must not reach the program
        resized.sets = resized.sets % 12 + 1
        var unknown = try Seeders.slot(77, day: 0, position: 0, last: false, exercises.map(\.id))
        unknown.misses = [1] // of a slot no program holds: skipped, and the workout is stored all the same
        let updates = [
            expected.days[0].slots[0],
            expected.days[0].slots[1],
            expected.days[1].slots[1],
            resized,
            unknown
        ]
        let workout = workout()
        try await stores.materialize(workout, slotUpdates: updates)
        try await stores.materialize(workout, slotUpdates: updates) // again: the same misses
        return try await ContractCheck.first(
            ContractCheck.expect(stores.programs.active(), expected, "active() after the slot updates"),
            ContractCheck.expect(stores.workouts.workout(id: workout.id), workout, "the workout stored with them")
        )
    }

    static func duplicateIDs(_ stores: HistoryStores) async throws -> String? {
        let workout = workout()
        var setTwice = workout
        setTwice.exercises[3].sets[1] = workout.exercises[0].sets[0]
        var exerciseTwice = workout
        exerciseTwice.exercises[4] = workout.exercises[1]
        // The copied exercise brings its sets, so the exercise is refused first: parents are written first.
        let cases: [(WorkoutState, String)] = [
            (setTwice, key("logged_set", workout.exercises[0].sets[0].id)),
            (exerciseTwice, key("workout_exercise", workout.exercises[1].id))
        ]
        for (broken, key) in cases {
            let issue = await ContractCheck.expectError(LedgerPersistenceError.duplicateIdentifier(key)) {
                try await stores.materialize(broken)
            }
            if let issue {
                return issue
            }
        }
        return try await ContractCheck.expect(stores.workouts.recent(limit: 10), [], "recent after the refused calls")
    }

    static func otherWorkoutsIDs(_ stores: HistoryStores) async throws -> String? {
        let first = workout(number: 1)
        try await stores.materialize(first)
        let second = workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(3600))
        var takesSet = second
        takesSet.exercises[0].sets[0] = first.exercises[2].sets[1]
        var takesExercise = second
        takesExercise.exercises[1] = first.exercises[1]
        takesExercise.exercises[1].sets = second.exercises[1].sets
        let setKey = key("logged_set", first.exercises[2].sets[1].id)
        let cases: [(WorkoutState, String)] = [
            (takesSet, setKey), (takesExercise, key("workout_exercise", first.exercises[1].id))
        ]
        for (thief, key) in cases {
            let issue = await ContractCheck.expectError(LedgerPersistenceError.duplicateIdentifier(key)) {
                try await stores.materialize(thief)
            }
            if let issue {
                return issue
            }
        }
        try await stores.materialize(second)
        let viaEdit = await ContractCheck.expectError(LedgerPersistenceError.duplicateIdentifier(setKey)) {
            try await stores.workouts.updateSets(
                workoutExerciseID: second.exercises[0].id,
                sets: [first.exercises[2].sets[1]]
            )
        }
        let unchanged = try await stores.workouts.recent(limit: 10)
        try await stores.workouts.delete(id: first.id)
        let afterDelete = await ContractCheck.expectError(LedgerPersistenceError.duplicateIdentifier(setKey)) {
            try await stores.materialize(takesSet)
        }
        try await stores.materialize(first)
        return try await ContractCheck.first(
            viaEdit,
            ContractCheck.expect(unchanged, [second, first], "recent after the refused calls"),
            afterDelete.map { "after the first workout was deleted: \($0)" },
            ContractCheck.expect(stores.workouts.workout(id: first.id), first, "the first, materialised again")
        )
    }

    static func refusesNul(_ stores: HistoryStores) async throws -> String? {
        let workout = workout()
        try await stores.materialize(workout)
        var named = workout
        named.name += "\u{0}"
        var tagged = workout
        tagged.tag = "\u{0}"
        var lastExercise = edited(workout)
        lastExercise.exercises[3].name = "Lat\u{0}Pulldown" // refused after every other row was written
        let cases: [(WorkoutState, String)] = [
            (named, "workout.name"), (tagged, "workout.tag"), (lastExercise, "workout_exercise.name")
        ]
        for (refused, column) in cases {
            let issue = await ContractCheck.expectError(LedgerPersistenceError.nulInText(column)) {
                try await stores.materialize(refused)
            }
            if let issue {
                return "\(column): \(issue)"
            }
        }
        return try await ContractCheck.expect(
            stores.workouts.recent(limit: 10),
            [workout],
            "recent after the refused calls"
        )
    }

    static func observeRecent(_ stores: HistoryStores) async throws -> String? {
        let first = workout(number: 1)
        let second = workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(3600))
        let third = workout(number: 3, endedAt: EventBuilders.start.addingTimeInterval(7200))
        var values = stores.workouts.observeRecent(limit: 2).makeAsyncIterator()
        let initial = await values.next()
        try await stores.materialize(first)
        let one = await values.next()
        // Writes that leave the list as it is emit nothing: the next value is the next change.
        try await stores.materialize(first)
        try await stores.workouts.delete(id: Seeders.workoutID(404))
        try await stores.materialize(third)
        let two = await values.next()
        try await stores.materialize(second) // enters the newest two, pushing the first out
        let three = await values.next()
        var edited = second
        edited.exercises[0].sets.removeLast()
        try await stores.workouts.updateSets(workoutExerciseID: second.exercises[0].id, sets: edited.exercises[0].sets)
        let afterEdit = await values.next()
        try await stores.workouts.delete(id: third.id)
        let afterDelete = await values.next()
        return ContractCheck.first(
            ContractCheck.expect(initial, [], "the first value"),
            ContractCheck.expect(one, [first], "the value after one workout"),
            ContractCheck.expect(two, [third, first], "the value after a newer workout"),
            ContractCheck.expect(three, [third, second], "the value after a workout between them"),
            ContractCheck.expect(afterEdit, [third, edited], "the value after updateSets"),
            ContractCheck.expect(afterDelete, [edited, first], "the value after delete")
        )
    }
}
