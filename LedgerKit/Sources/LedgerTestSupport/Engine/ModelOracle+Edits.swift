import Foundation
import LedgerDomain

/// `ModelOracle`'s one-row and one-exercise edits, and its rest and terminal edits.
extension Model {
    func find(_ setID: SetID, in exerciseIndex: Int) -> Int? {
        guard exerciseIndex >= 0, exerciseIndex < workout.exercises.count else {
            return nil
        }
        for (setIndex, set) in workout.exercises[exerciseIndex].sets.enumerated() where set.id == setID {
            return setIndex
        }
        return nil
    }

    mutating func select(_ exerciseIndex: Int, _ setIndex: Int) {
        guard exerciseIndex >= 0, exerciseIndex < workout.exercises.count,
              setIndex >= 0, setIndex < workout.exercises[exerciseIndex].sets.count,
              workout.exercises[exerciseIndex].sets[setIndex].doneAt == nil
        else {
            return
        }
        workout.cursor = Cursor(exerciseIndex: exerciseIndex, setIndex: setIndex)
    }

    mutating func changeTarget(_ exerciseIndex: Int, _ setID: SetID, _ weight: Weight?, _ reps: Reps?) {
        guard let setIndex = find(setID, in: exerciseIndex) else {
            return
        }
        if let weight {
            workout.exercises[exerciseIndex].sets[setIndex].weight = weight < .zero ? .zero : weight
        }
        if let reps {
            workout.exercises[exerciseIndex].sets[setIndex].reps = reps
        }
    }

    mutating func addSet(_ exerciseIndex: Int, _ set: LoggedSet) {
        guard exerciseIndex >= 0, exerciseIndex < workout.exercises.count else {
            return
        }
        for exercise in workout.exercises {
            for existing in exercise.sets where existing.id == set.id {
                return
            }
        }
        let weight = set.weight < .zero ? .zero : set.weight
        let added = LoggedSet(id: set.id, weight: weight, reps: set.reps, kind: .added, doneAt: nil)
        workout.exercises[exerciseIndex].sets.append(added)
    }

    mutating func repeatAll(_ exerciseIndex: Int, _ weight: Weight, _ reps: Reps) {
        guard exerciseIndex >= 0, exerciseIndex < workout.exercises.count else {
            return
        }
        for setIndex in 0 ..< workout.exercises[exerciseIndex].sets.count {
            workout.exercises[exerciseIndex].sets[setIndex].weight = weight < .zero ? .zero : weight
            workout.exercises[exerciseIndex].sets[setIndex].reps = reps
        }
    }

    mutating func swap(_ exerciseIndex: Int, _ exerciseID: ExerciseID, _ name: String, _ alsoUpdateProgram: Bool) {
        guard exerciseIndex >= 0, exerciseIndex < workout.exercises.count else {
            return
        }
        workout.exercises[exerciseIndex].exerciseID = exerciseID
        workout.exercises[exerciseIndex].name = name
        if alsoUpdateProgram, let slotID = workout.exercises[exerciseIndex].slotID {
            workout.programUpdates[slotID] = exerciseID
        }
    }

    mutating func extendRest(by amount: Duration) {
        let (seconds, limit) = (amount / .seconds(1), Self.restLimit)
        if let rest = workout.rest, rest.endsAt > time {
            // Each term is cut to ±limit first, so the sum cannot overflow; for the totals this model
            // writes (0…limit) the cut changes nothing once setRest caps the sum.
            let sum = min(max(rest.total, .zero - limit), limit) + min(max(amount, .zero - limit), limit)
            setRest(endsAt: rest.endsAt.addingTimeInterval(seconds), total: sum, from: time)
        } else {
            setRest(endsAt: time.addingTimeInterval(seconds), total: amount, from: time)
        }
    }

    /// The bound `WorkoutEngine.longestRest` documents, written out: one hour.
    static let restLimit = Duration.seconds(3600)

    /// Writes the rest capped: `total` into 0…restLimit, `endsAt` at most restLimit after `start`.
    mutating func setRest(endsAt: Date, total: Duration, from start: Date) {
        let latest = start.addingTimeInterval(Self.restLimit / .seconds(1))
        workout.rest = RestTimer(endsAt: min(endsAt, latest), total: min(max(total, .zero), Self.restLimit))
    }

    mutating func end(as phase: WorkoutPhase, at endedAt: Date) {
        workout.phase = phase
        workout.endedAt = endedAt
        workout.rest = nil
    }
}
