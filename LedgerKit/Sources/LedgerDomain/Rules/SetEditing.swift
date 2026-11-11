import Foundation

/// What fixing a past workout may change (F13 S3, N11; F13 question 3, built to A): the weight and the reps of the sets
/// that were logged, and nothing else. A set not done, and every set's id, kind, order and `doneAt`, pass through as
/// they are; so does every other field of the workout.
///
/// Weights move as F11's start load does (rule 6, `Weight.nextMultiple(of:_:)`, F13 question 5, built to A): to the
/// next multiple of the step in the lifter's units, on the side tapped, never below 0. Reps move by one and never
/// below 1. The rule reads no program: a fix changes records, charts and stats, not a program's hold or advance (F13
/// question 4, built to A).
public enum SetEditing {
    public enum Field: Hashable, Sendable {
        case weight, reps
    }

    /// The sets a lifter can edit: those of `exercise` that were logged, in their order.
    public static func editable(_ exercise: WorkoutExercise) -> [LoggedSet] {
        exercise.sets.filter(\.isDone)
    }

    /// The step of `exercise`'s weight for a lifter reading `units`: its own, a mass in the units the workout was
    /// logged in, while those are the lifter's and it can move a weight; otherwise the equipment's step in `units`.
    public static func step(of exercise: WorkoutExercise, loggedIn logged: Units, readIn units: Units) -> Weight {
        logged == units && exercise.step > .zero ? exercise.step : exercise.equipment.defaultStep(in: units)
    }

    /// `set` one step away in `field`. A set that was not logged is returned as it is.
    public static func stepped(
        _ set: LoggedSet,
        _ field: Field,
        _ direction: StepDirection,
        step: Weight
    ) -> LoggedSet {
        guard set.isDone else {
            return set
        }
        var edited = set
        switch field {
        case .weight:
            edited.weight = set.weight.nextMultiple(of: step, direction)
        case .reps:
            edited.reps = steppedReps(set.reps, direction)
        }
        return edited
    }

    /// Whether a step of `field` that way would change `set`: "−" stops at 0 and at 1 rep. Nothing moves a set that was
    /// not logged.
    public static func canStep(_ set: LoggedSet, _ field: Field, _ direction: StepDirection) -> Bool {
        guard set.isDone else {
            return false
        }
        return switch (field, direction) {
        case (.weight, .downward): set.weight > .zero
        case (.reps, .downward): set.reps > .one
        case (.reps, .upward): set.reps.value < .max
        case (.weight, .upward): true
        }
    }

    /// `workout` with the set `id` one step away in `field`, read in `units`. A set no exercise holds changes nothing.
    public static func stepping(
        _ id: SetID,
        _ field: Field,
        _ direction: StepDirection,
        in workout: WorkoutState,
        units: Units
    ) -> WorkoutState {
        var edited = workout
        for place in edited.exercises.indices {
            let exercise = edited.exercises[place]
            guard let index = exercise.sets.firstIndex(where: { $0.id == id }) else {
                continue
            }
            let step = step(of: exercise, loggedIn: workout.units, readIn: units)
            edited.exercises[place].sets[index] = stepped(exercise.sets[index], field, direction, step: step)
            break
        }
        return edited
    }

    /// What differs between `edited` and `original`, by exercise, as `WorkoutRepository.updateSets(_:of:)` takes it:
    /// empty when nothing does.
    public static func changes(
        from original: WorkoutState,
        to edited: WorkoutState
    ) -> [WorkoutExerciseID: [LoggedSet]] {
        let before = Dictionary(original.exercises.map { ($0.id, $0.sets) }) { first, _ in first }
        var changed: [WorkoutExerciseID: [LoggedSet]] = [:]
        for exercise in edited.exercises where before[exercise.id] != exercise.sets {
            changed[exercise.id] = exercise.sets
        }
        return changed
    }

    private static func steppedReps(_ reps: Reps, _ direction: StepDirection) -> Reps {
        switch direction {
        case .downward: Reps(clamping: reps.value - 1)
        case .upward: reps.value < .max ? Reps(clamping: reps.value + 1) : reps
        }
    }
}
