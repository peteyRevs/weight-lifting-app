import Foundation
import LedgerDomain

/// What a store refuses at its storage boundary (ADR-007; F07 S1 fix round 1, finding F7-1), and which of two
/// faults it meets first (F7-4). Separate from `clauses` because F05's in-memory oracles (`HistoryModel`) model
/// history, not the columns: the GRDB repository and LedgerFakes' `InMemoryWorkoutRepository` run both lists.
public extension WorkoutRepositoryContract {
    static let storageClauses: [Clause] = [
        Clause(
            "a weight no column keeps exactly, or a date that is not finite, is refused by name; nothing is stored",
            refusesWhatNoColumnKeeps
        ),
        Clause(
            "with two faults, the one the rows meet first is thrown: the workout's text before a set's id",
            twoFaults
        )
    ]
}

extension WorkoutRepositoryContract {
    /// A workout a store must refuse, and the error it must refuse it with.
    struct Refusal {
        let what: String
        let workout: WorkoutState
        let error: RepositoryError

        init(_ what: String, _ workout: WorkoutState, _ error: RepositoryError) {
            self.what = what
            self.workout = workout
            self.error = error
        }
    }

    /// The first refusal `stores` gets wrong, or `nil`.
    static func firstWrong(_ refusals: [Refusal], _ stores: HistoryStores) async -> String? {
        for refusal in refusals {
            let workout = refusal.workout
            if let issue = await ContractCheck.expectError(refusal.error, { try await stores.materialize(workout) }) {
                return "\(refusal.what): \(issue)"
            }
        }
        return nil
    }

    static let eighthPound = Weight.pounds(Decimal(string: "0.125") ?? 0)
    static let never = Date(timeIntervalSinceReferenceDate: .infinity)

    static func refusesWhatNoColumnKeeps(_ stores: HistoryStores) async throws -> String? {
        let base = workout()
        var doneSet = base // counted in the volume, which the workout's row stores before any set
        doneSet.exercises[0].sets[0].weight = eighthPound
        var undoneSet = base // not counted in the volume: its own row refuses it
        undoneSet.exercises[2].sets[3].weight = eighthPound
        var target = base
        target.exercises[1].targetLoad = eighthPound
        var started = base
        started.startedAt = never
        var ended = base
        ended.endedAt = never
        var ticked = base
        ticked.exercises[0].sets[0].doneAt = never
        if let issue = await firstWrong([
            Refusal("a done ⅛ lb set", doneSet, .inexactWeight(doneSet.volume.gramReps)),
            Refusal("an undone ⅛ lb set", undoneSet, .inexactWeight(eighthPound.grams)),
            Refusal("a ⅛ lb target load", target, .inexactWeight(eighthPound.grams)),
            Refusal("a start at +∞", started, .nonFiniteDate),
            Refusal("an end at +∞", ended, .nonFiniteDate),
            Refusal("a set done at +∞", ticked, .nonFiniteDate)
        ], stores) {
            return issue
        }
        let afterMaterialize = try await stores.workouts.recent(limit: 10)
        try await stores.materialize(base)
        let sets = undoneSet.exercises[2].sets
        let edit = await ContractCheck.expectError(RepositoryError.inexactWeight(eighthPound.grams)) {
            try await stores.workouts.updateSets(workoutExerciseID: base.exercises[2].id, sets: sets)
        }
        return try await ContractCheck.first(
            ContractCheck.expect(afterMaterialize, [], "recent after the refused materialisations"),
            edit.map { "updateSets with an undone ⅛ lb set: \($0)" },
            ContractCheck.expect(stores.workouts.recent(limit: 10), [base], "recent after the refused edit")
        )
    }

    /// The database writes the workout's row (its text), then the exercises, then the sets: a workout named with
    /// U+0000 that also repeats a set id throws `nulInText`, and an exercise named so, before the repeat.
    static func twoFaults(_ stores: HistoryStores) async throws -> String? {
        var named = workout()
        named.name += "\u{0}"
        named.exercises[0].sets[1] = named.exercises[0].sets[0]
        var exerciseNamed = workout()
        exerciseNamed.exercises[1].name += "\u{0}"
        exerciseNamed.exercises[1].sets[1] = exerciseNamed.exercises[1].sets[0]
        var repeatedAndInexact = workout()
        repeatedAndInexact.exercises[2].sets[3].weight = eighthPound
        repeatedAndInexact.exercises[2].sets[1] = repeatedAndInexact.exercises[2].sets[0]
        let repeated = key("logged_set", repeatedAndInexact.exercises[2].sets[0].id)
        if let issue = await firstWrong([
            Refusal("the workout's name and a repeated set", named, .nulInText("workout.name")),
            Refusal("an exercise's name and a repeated set", exerciseNamed, .nulInText("workout_exercise.name")),
            Refusal("a repeated set and a later set of ⅛ lb", repeatedAndInexact, .duplicateIdentifier(repeated))
        ], stores) {
            return issue
        }
        return try await ContractCheck.expect(stores.workouts.recent(limit: 10), [], "recent after the refused calls")
    }
}
