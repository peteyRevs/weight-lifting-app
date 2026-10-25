import Foundation
import LedgerDomain

/// Finished workouts for persistence tests (F05 S3): one built set by set, and a seeded history of any size.
public extension Seeders {
    /// One set row of a seeded workout.
    struct SetSpec: Sendable {
        public var weight: Weight
        public var reps: Int
        public var kind: SetKind
        public var isDone: Bool

        /// `reps` × `pounds` lb; reps below 1 become 1.
        public init(_ pounds: Decimal, _ reps: Int, _ kind: SetKind = .working, done: Bool = true) {
            weight = .pounds(pounds)
            self.reps = reps
            self.kind = kind
            isDone = done
        }
    }

    /// One exercise of a seeded workout: what was performed, and its set rows.
    struct ExerciseLog: Sendable {
        public var exercise: Exercise
        public var slotID: SlotID?
        public var sets: [SetSpec]

        public init(_ exercise: Exercise, slotID: SlotID? = nil, _ sets: [SetSpec]) {
            self.exercise = exercise
            self.slotID = slotID
            self.sets = sets
        }

        /// `sets` done working sets of `reps` × `pounds` lb.
        public static func straight(_ exercise: Exercise, sets: Int, reps: Int, pounds: Decimal) -> ExerciseLog {
            ExerciseLog(exercise, Array(repeating: SetSpec(pounds, reps), count: sets))
        }
    }

    /// The id of seeded workout `number`.
    static func workoutID(_ number: Int) -> WorkoutID {
        WorkoutID(EventBuilders.uuid(0x0D00_0000 + number))
    }

    /// A finished workout as `WorkoutRepository.materialize` takes it, and as it reads back: no cursor, no
    /// rest, and the other live-only fields at their defaults.
    ///
    /// It ends at `endedAt` after `minutes`. Exercise and set ids derive from the workout's, as in a built
    /// session. Each exercise's targets are its working rows (their count, and the first one's reps and
    /// weight), and its step is its equipment's in `units`. Done sets are ticked at even intervals from the
    /// start, in row order.
    static func workout(
        number: Int,
        endedAt: Date,
        minutes: Int = 60,
        isDeload: Bool = false,
        units: Units = .lb,
        source: WorkoutSource? = nil,
        _ exercises: [ExerciseLog]
    ) -> WorkoutState {
        let id = workoutID(number)
        let startedAt = endedAt.addingTimeInterval(-60 * Double(minutes))
        let interval = 60 * Double(minutes) / Double(exercises.reduce(1) { $0 + $1.sets.count })
        var rowsBefore = 0
        let built = exercises.enumerated().map { index, log in
            let first = rowsBefore
            rowsBefore += log.sets.count
            return exercise(log, id: .derived(from: id, index: index), units: units) { position in
                startedAt.addingTimeInterval(interval * Double(first + position + 1))
            }
        }
        return WorkoutState(
            id: id,
            source: source,
            name: "Workout \(number) — Seeded",
            tag: "W\(number % 100)",
            isDeload: isDeload,
            exercises: built,
            cursor: nil,
            startedAt: startedAt,
            endedAt: endedAt,
            phase: .finished,
            originDevice: EventBuilders.phone,
            units: units
        )
    }

    /// `log` as a workout's exercise `id`; `doneAt` gives the time a done row at a position was ticked.
    private static func exercise(
        _ log: ExerciseLog,
        id: WorkoutExerciseID,
        units: Units,
        doneAt: (Int) -> Date
    ) -> WorkoutExercise {
        let working = log.sets.filter { $0.kind == .working }
        return WorkoutExercise(
            id: id,
            slotID: log.slotID,
            exerciseID: log.exercise.id,
            originalExerciseID: log.exercise.id,
            name: log.exercise.name,
            equipment: log.exercise.equipment,
            step: log.exercise.equipment.defaultStep(in: units),
            rest: .defaultRest,
            rpe: rpe,
            isSupersetWithPrevious: false,
            targetSets: working.count,
            targetReps: working.first?.reps ?? 1,
            targetLoad: working.first?.weight ?? .zero,
            sets: log.sets.enumerated().map { position, spec in
                LoggedSet(
                    id: .derived(from: id, index: position),
                    weight: spec.weight,
                    reps: Reps(clamping: spec.reps),
                    kind: spec.kind,
                    doneAt: spec.isDone ? doneAt(position) : nil
                )
            }
        )
    }

    /// A history of `workouts` finished workouts, the last ending at `endingAt` and each 42 hours after the
    /// one before (400 of them span about two years). Each holds `setsPerWorkout` set rows, shared among up
    /// to five of `exercises` in turn.
    ///
    /// `rng` picks the exercises, each exercise's load (45 to 315 lb in 5 lb steps) and reps (1 to 15), a drop
    /// set at the end of about one exercise in four, and about one row in twenty left undone, so every stats
    /// query has work to do. The same generator state gives the same history.
    static func history(
        exercises: [Exercise],
        workouts: Int,
        setsPerWorkout: Int,
        rng: inout some RandomNumberGenerator,
        endingAt: Date = EventBuilders.start
    ) -> [WorkoutState] {
        let perWorkout = min(exercises.count, 5)
        return (0 ..< max(0, workouts)).map { number in
            let first = Int.random(in: 0 ..< max(1, exercises.count), using: &rng)
            let logs = (0 ..< perWorkout).map { turn in
                let rows = setsPerWorkout / perWorkout + (turn < setsPerWorkout % perWorkout ? 1 : 0)
                let pounds = Decimal(5 * Int.random(in: 9 ... 63, using: &rng))
                let reps = Int.random(in: 1 ... 15, using: &rng)
                let endsWithDrop = Int.random(in: 0 ..< 4, using: &rng) == 0
                return ExerciseLog(exercises[(first + turn) % exercises.count], (0 ..< rows).map { row in
                    SetSpec(
                        pounds,
                        reps,
                        endsWithDrop && row == rows - 1 ? .drop : .working,
                        done: Int.random(in: 0 ..< 20, using: &rng) != 0
                    )
                })
            }
            let age = Double(workouts - 1 - number) * 42 * 3600
            return workout(number: number, endedAt: endingAt.addingTimeInterval(-age), logs)
        }
    }

    /// One exercise's sessions as `StatsQueries.exerciseSessions` returns them, newest first: a `history` of
    /// `sessions` workouts of `setsPerSession` rows of `exercise` alone, every row done. 400 × 5 is F12 S2's N11
    /// load, 2,000 sets, with `history`'s loads, reps and drop sets.
    static func exerciseSessions(
        of exercise: Exercise,
        sessions: Int,
        setsPerSession: Int,
        rng: inout some RandomNumberGenerator
    ) -> [ExerciseSession] {
        history(exercises: [exercise], workouts: sessions, setsPerWorkout: setsPerSession, rng: &rng)
            .reversed()
            .map { workout in
                let sets = workout.exercises.flatMap(\.sets).map { set in
                    var done = set
                    done.doneAt = set.doneAt ?? workout.startedAt
                    return done
                }
                return ExerciseSession(workoutID: workout.id, startedAt: workout.startedAt, sets: sets)
            }
    }

    /// RPE 8, every seeded exercise's.
    private static var rpe: RPE {
        guard let eight = RPE(8) else {
            preconditionFailure("8 is an RPE: 5…10 in 0.5 steps")
        }
        return eight
    }
}
