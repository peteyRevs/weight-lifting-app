import Foundation

/// Personal-record detection at finish (decision #3; replaces the prototype's rule 29).
public enum PersonalRecords {
    /// Decision #3: for each exercise (grouped by `exerciseID`, in workout order) with ≥ 1 done
    /// `.working`/`.added` set:
    /// - `.estimatedOneRepMax` when the best Brzycki e1RM of those sets (reps ≤ 12, decision #4)
    ///   is strictly greater than `bestE1RM[exercise]`;
    /// - `.weightAtReps` when a set's weight is strictly greater than the best weight in history at
    ///   ≥ the same reps; the heaviest such set is reported (ties → more reps).
    ///
    /// Both may fire. Ties are not PRs. No PR without a comparable prior record: an exercise with
    /// no best e1RM, or a set whose rep count has no history at or above it, produces no PR (a
    /// first session is a baseline; F02 spec question 1, orchestrator decision).
    /// Deload workouts never produce PRs. `achievedAt` is `now`.
    public static func detect(
        workout: WorkoutState,
        bestE1RM: [ExerciseID: Weight],
        bestWeightAtReps: [ExerciseID: [Reps: Weight]],
        now: Date
    ) -> [PersonalRecord] {
        guard !workout.isDeload else {
            return []
        }
        var order: [ExerciseID] = []
        var candidates: [ExerciseID: [LoggedSet]] = [:]
        for exercise in workout.exercises {
            let sets = exercise.sets.filter { $0.isDone && ($0.kind == .working || $0.kind == .added) }
            guard !sets.isEmpty else {
                continue
            }
            if candidates[exercise.exerciseID] == nil {
                order.append(exercise.exerciseID)
            }
            candidates[exercise.exerciseID, default: []] += sets
        }
        return order.flatMap { exerciseID in
            let sets = candidates[exerciseID] ?? []
            let kinds = [
                e1RMRecord(sets: sets, previous: bestE1RM[exerciseID]),
                weightRecord(sets: sets, history: bestWeightAtReps[exerciseID] ?? [:])
            ]
            return kinds.compactMap(\.self).map { record in
                PersonalRecord(
                    exerciseID: exerciseID,
                    kind: record.kind,
                    previous: record.previous,
                    achievedAt: now,
                    workoutID: workout.id
                )
            }
        }
    }

    private struct Found {
        let kind: PRKind
        let previous: PRKind
    }

    private static func e1RMRecord(sets: [LoggedSet], previous: Weight?) -> Found? {
        guard let previous,
              let best = sets.compactMap({ OneRepMax.brzycki(weight: $0.weight, reps: $0.reps) }).max(),
              best > previous
        else {
            return nil
        }
        return Found(kind: .estimatedOneRepMax(best), previous: .estimatedOneRepMax(previous))
    }

    private static func weightRecord(sets: [LoggedSet], history: [Reps: Weight]) -> Found? {
        let record = sets
            .filter { set in previousBest(atOrAbove: set.reps, in: history).map { set.weight > $0.weight } ?? false }
            .max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
        guard let record, let previous = previousBest(atOrAbove: record.reps, in: history) else {
            return nil
        }
        return Found(
            kind: .weightAtReps(record.weight, record.reps),
            previous: .weightAtReps(previous.weight, previous.reps)
        )
    }

    /// The heaviest history entry at ≥ `reps` (ties → more reps).
    private static func previousBest(
        atOrAbove reps: Reps,
        in history: [Reps: Weight]
    ) -> (weight: Weight, reps: Reps)? {
        history
            .filter { $0.key >= reps }
            .map { (weight: $0.value, reps: $0.key) }
            .max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
    }
}
