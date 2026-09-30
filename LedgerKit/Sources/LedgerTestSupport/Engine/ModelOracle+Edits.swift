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

    /// "+30s": grows the rest the tapping device showed, else a fresh rest from the tap, except that a
    /// rest already running past that fresh rest's end is left alone ("+30s" never shortens a rest).
    mutating func extendRest(by amount: Duration, shown: Bool, tappedAt: Date) {
        let freshEnd = tappedAt.addingTimeInterval(amount / .seconds(1))
        if shown, let rest = workout.rest {
            // Each term is cut to ±limit first, so the sum cannot overflow; for the totals this model
            // writes (0…limit) the cut changes nothing once setRest caps the sum.
            let limit = Self.restLimit
            let sum = min(max(rest.total, .zero - limit), limit) + min(max(amount, .zero - limit), limit)
            setRest(endsAt: rest.endsAt.addingTimeInterval(amount / .seconds(1)), total: sum, from: tappedAt)
        } else if let rest = workout.rest, rest.endsAt > freshEnd {
            return
        } else {
            setRest(endsAt: freshEnd, total: amount, from: tappedAt)
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

// MARK: - Malformed envelopes

extension ModelOracle {
    /// `false` for an envelope the rules skip: a stamp or any date it carries that is not a finite
    /// number, or a rest length below zero or above an hour. There is no time window.
    static func accepts(_ envelope: EventEnvelope) -> Bool {
        let dates = [envelope.wallClock] + payloadDates(of: envelope.event)
        for date in dates where !date.timeIntervalSinceReferenceDate.isFinite {
            return false
        }
        for length in restLengths(of: envelope.event) where length < .zero || length > Model.restLimit {
            return false
        }
        return true
    }

    /// Every date an event carries.
    static func payloadDates(of event: WorkoutEvent) -> [Date] {
        switch event {
        case let .started(snapshot):
            var dates = [snapshot.startedAt]
            dates += [snapshot.endedAt, snapshot.rest?.endsAt].compactMap(\.self)
            for exercise in snapshot.exercises {
                dates += exercise.sets.compactMap(\.doneAt)
                if let last = exercise.lastPerformance {
                    dates.append(last.date)
                }
            }
            return dates
        case let .setLogged(_, _, _, _, doneAt):
            return [doneAt]
        case let .setAdded(_, set):
            return [set.doneAt].compactMap(\.self)
        case let .restStarted(endsAt, _):
            return [endsAt]
        case let .restExtended(_, _, tappedAt):
            return [tappedAt]
        case let .finished(endedAt), let .discarded(endedAt):
            return [endedAt]
        default:
            return []
        }
    }

    /// Every rest length an event carries.
    static func restLengths(of event: WorkoutEvent) -> [Duration] {
        switch event {
        case let .started(snapshot):
            [snapshot.rest?.total].compactMap(\.self)
        case let .restStarted(_, total):
            [total]
        case let .restExtended(amount, _, _):
            [amount]
        default:
            []
        }
    }
}
