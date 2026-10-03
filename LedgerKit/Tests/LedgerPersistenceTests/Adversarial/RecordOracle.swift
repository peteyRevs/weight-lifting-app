import Foundation
import LedgerDomain

/// F05 records follow-up, adversarial round 1: decision #3 and #27 written again from the decisions' text, as
/// the slices before F05's follow-up computed it (each set judged on its own), with none of
/// `PersonalRecords.found`, `Tally` or `Bests`, which both the store and `HistoryModel` now share.
enum RecordOracle {
    /// One exercise's history: the best estimate, and the heaviest weight at each rep count.
    struct History: Equatable {
        var estimate: Weight?
        var atReps: [Int: Weight] = [:]
    }

    /// Decision #25: done working and added sets.
    static func counts(_ set: LoggedSet) -> Bool {
        set.doneAt != nil && (set.kind == .working || set.kind == .added)
    }

    /// The workouts in history's order (decision #26): by start, then id text.
    static func ordered(_ workouts: [WorkoutState]) -> [WorkoutState] {
        workouts.sorted { ($0.startedAt, $0.id.rawValue.uuidString) < ($1.startedAt, $1.id.rawValue.uuidString) }
    }

    /// Every set of `workout` that counts, by exercise, the exercises in the order they first appear.
    static func sets(of workout: WorkoutState) -> [(ExerciseID, [LoggedSet])] {
        var order: [ExerciseID] = []
        var sets: [ExerciseID: [LoggedSet]] = [:]
        for row in workout.exercises {
            let counted = row.sets.filter(counts)
            guard !counted.isEmpty else {
                continue
            }
            if sets[row.exerciseID] == nil {
                order.append(row.exerciseID)
            }
            sets[row.exerciseID, default: []] += counted
        }
        return order.map { ($0, sets[$0] ?? []) }
    }

    /// The heaviest weight at `reps` or more in `history`, and its reps; of two as heavy, the more reps.
    static func best(atOrAbove reps: Int, in history: History) -> (weight: Weight, reps: Int)? {
        history.atReps.filter { $0.key >= reps }
            .map { (weight: $0.value, reps: $0.key) }
            .max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
    }

    /// The records `workout` sets over `before`, achieved at its start.
    static func detect(_ workout: WorkoutState, over before: [ExerciseID: History]) -> [PersonalRecord] {
        guard !workout.isDeload else {
            return []
        }
        return sets(of: workout).flatMap { exercise, sets -> [PersonalRecord] in
            let history = before[exercise] ?? History()
            var found: [(PRKind, PRKind)] = []
            let estimates = sets.compactMap { OneRepMax.brzycki(weight: $0.weight, reps: $0.reps) }
            if let top = estimates.max(), let previous = history.estimate, top > previous {
                found.append((.estimatedOneRepMax(top), .estimatedOneRepMax(previous)))
            }
            let beating = sets.filter { set in
                best(atOrAbove: set.reps.value, in: history).map { set.weight > $0.weight } ?? false
            }
            let top = beating.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
            if let top, let previous = best(atOrAbove: top.reps.value, in: history) {
                found.append((
                    .weightAtReps(top.weight, top.reps),
                    .weightAtReps(previous.weight, Reps(clamping: previous.reps))
                ))
            }
            return found.map { kind, previous in
                PersonalRecord(
                    exerciseID: exercise,
                    kind: kind,
                    previous: previous,
                    achievedAt: workout.startedAt,
                    workoutID: workout.id
                )
            }
        }
    }

    /// `history` raised by `workout`'s counted sets, a deload's included.
    static func include(_ workout: WorkoutState, in history: inout [ExerciseID: History]) {
        for (exercise, sets) in sets(of: workout) {
            for set in sets {
                if let estimate = OneRepMax.brzycki(weight: set.weight, reps: set.reps) {
                    history[exercise, default: History()].estimate = max(
                        history[exercise]?.estimate ?? estimate,
                        estimate
                    )
                }
                let heaviest = history[exercise]?.atReps[set.reps.value].map { max($0, set.weight) } ?? set.weight
                history[exercise, default: History()].atReps[set.reps.value] = heaviest
            }
        }
    }

    /// Every live workout's records, replayed from scratch.
    static func replay(_ workouts: [WorkoutState]) -> [WorkoutID: [PersonalRecord]] {
        var history: [ExerciseID: History] = [:]
        var records: [WorkoutID: [PersonalRecord]] = [:]
        for workout in ordered(workouts) {
            records[workout.id] = detect(workout, over: history)
            include(workout, in: &history)
        }
        return records
    }

    /// The history of `exercises` from the workouts before `place` (start, then id).
    static func bests(before place: WorkoutState, of workouts: [WorkoutState]) -> [ExerciseID: History] {
        let key = (place.startedAt, place.id.rawValue.uuidString)
        var history: [ExerciseID: History] = [:]
        for workout in ordered(workouts) where (workout.startedAt, workout.id.rawValue.uuidString) < key {
            include(workout, in: &history)
        }
        return history
    }

    /// `personalRecords(exerciseID:)` as the protocol orders it: newest start first, then workout id, then the
    /// estimate before the weight.
    static func list(_ records: [WorkoutID: [PersonalRecord]], of exercise: ExerciseID) -> [PersonalRecord] {
        records.values.flatMap(\.self).filter { $0.exerciseID == exercise }.sorted { lhs, rhs in
            if lhs.achievedAt != rhs.achievedAt {
                return lhs.achievedAt > rhs.achievedAt
            }
            if lhs.workoutID != rhs.workoutID {
                return lhs.workoutID.rawValue.uuidString < rhs.workoutID.rawValue.uuidString
            }
            if case .estimatedOneRepMax = lhs.kind {
                return true
            }
            return false
        }
    }
}
