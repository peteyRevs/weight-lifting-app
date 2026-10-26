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
            let sets = exercise.sets.filter(Self.countsTowardBests)
            guard !sets.isEmpty else {
                continue
            }
            if candidates[exercise.exerciseID] == nil {
                order.append(exercise.exerciseID)
            }
            candidates[exercise.exerciseID, default: []] += sets
        }
        return order.flatMap { exerciseID in
            var own = Tally<Weight>()
            for set in candidates[exerciseID] ?? [] {
                own.add(set.weight, reps: set.reps, estimate: OneRepMax.brzycki(weight: set.weight, reps: set.reps))
            }
            let before = Tally(estimate: bestE1RM[exerciseID], atReps: bestWeightAtReps[exerciseID] ?? [:])
            return found(own, over: before).map { record in
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

    /// `detect` against `bests`: `bestE1RM` is `bests.e1RM` and `bestWeightAtReps` is `bests.weightAtReps`.
    public static func detect(workout: WorkoutState, against bests: Bests, now: Date) -> [PersonalRecord] {
        detect(workout: workout, bestE1RM: bests.e1RM, bestWeightAtReps: bests.weightAtReps, now: now)
    }

    /// Decision #3 for one exercise of one workout that is not a deload, over any exactly ordered weight:
    /// `own` tallies the workout's sets that count toward bests, `before` the bests before it.
    /// - The estimate is a record when it is strictly above a prior estimate.
    /// - The weight record is the heaviest of the workout's weights (ties → more reps) that is strictly heavier
    ///   than the heaviest prior weight at the same or more reps, which it beats.
    ///
    /// No prior value, no record (a first session is a baseline). The estimate comes first. `detect` calls this
    /// with `Weight`s; a store may call it with whole 10⁻⁷ g, which order the same (ADR-007), to replay records
    /// over its history (product decision #27) without decimal arithmetic.
    public static func found<Value>(_ own: Tally<Value>, over before: Tally<Value>) -> [Found<Value>] {
        var found: [Found<Value>] = []
        if let estimate = own.estimate, let previous = before.estimate, estimate > previous {
            found.append(.estimate(estimate, over: previous))
        }
        // From the most reps down: `ceiling` is the heaviest prior weight at the current rep count or more
        // (ties → more reps, met first), the best that a weight at those reps must beat.
        let prior = before.atReps.keys.sorted(by: >)
        var next = prior.startIndex
        var ceiling: Best<Value>?
        var beaten: (record: Best<Value>, over: Best<Value>)?
        for reps in own.atReps.keys.sorted(by: >) {
            while next < prior.endIndex, prior[next] >= reps {
                if let weight = before.atReps[prior[next]], ceiling.map({ weight > $0.weight }) ?? true {
                    ceiling = Best(weight: weight, reps: prior[next])
                }
                next += 1
            }
            // Of the workout's weights that beat their ceiling, the heaviest (ties → more reps, met first).
            guard let ceiling, let weight = own.atReps[reps], weight > ceiling.weight,
                  beaten.map({ weight > $0.record.weight }) ?? true
            else {
                continue
            }
            beaten = (Best(weight: weight, reps: reps), ceiling)
        }
        if let beaten {
            found.append(.weight(beaten.record.weight, beaten.record.reps, over: beaten.over.weight, beaten.over.reps))
        }
        return found
    }

    /// A weight and the reps it was lifted for.
    private struct Best<Value> {
        let weight: Value
        let reps: Reps
    }

    /// Product decision #25: a done `.working` or `.added` set counts toward an exercise's bests and can set a
    /// record; a warm-up or a drop set never does.
    public static func countsTowardBests(_ set: LoggedSet) -> Bool {
        set.isDone && (set.kind == .working || set.kind == .added)
    }
}

public extension PersonalRecords {
    /// One exercise's bests over some sets, in any exactly ordered weight (`Weight`, or whole 10⁻⁷ g): the best
    /// Brzycki estimate (sets of at most 12 reps, decision #4) and the heaviest weight at each rep count.
    struct Tally<Value: Comparable & Hashable & Sendable>: Hashable, Sendable {
        public var estimate: Value?
        public var atReps: [Reps: Value]

        public init(estimate: Value? = nil, atReps: [Reps: Value] = [:]) {
            self.estimate = estimate
            self.atReps = atReps
        }

        /// Raises the tally with a set of `reps` at `weight`, whose estimate is `estimate` (`nil` above 12 reps).
        public mutating func add(_ weight: Value, reps: Reps, estimate setEstimate: Value?) {
            if let setEstimate {
                estimate = estimate.map { max($0, setEstimate) } ?? setEstimate
            }
            atReps[reps] = atReps[reps].map { max($0, weight) } ?? weight
        }

        /// Raises the tally with another: the bests of both sets of sets.
        public mutating func add(_ other: Tally) {
            if let otherEstimate = other.estimate {
                estimate = estimate.map { max($0, otherEstimate) } ?? otherEstimate
            }
            atReps.merge(other.atReps, uniquingKeysWith: max)
        }
    }

    /// A record `found` finds, and the best it beats.
    enum Found<Value: Comparable & Hashable & Sendable>: Hashable, Sendable {
        case estimate(Value, over: Value)
        case weight(Value, Reps, over: Value, Reps)
    }
}

public extension PersonalRecords.Found<Weight> {
    /// The record as a `PersonalRecord` holds it.
    var kind: PRKind {
        switch self {
        case let .estimate(value, _): .estimatedOneRepMax(value)
        case let .weight(value, reps, _, _): .weightAtReps(value, reps)
        }
    }

    /// The best it beats, as a `PersonalRecord` holds it.
    var previous: PRKind {
        switch self {
        case let .estimate(_, previous): .estimatedOneRepMax(previous)
        case let .weight(_, _, previous, reps): .weightAtReps(previous, reps)
        }
    }
}

public extension PersonalRecords {
    /// What `detect` judges a workout against, per exercise: the best Brzycki e1RM (sets of at most 12 reps,
    /// decision #4) and the best weight at each rep count, over the sets that count toward bests (decision
    /// #25). Product decision #27 has them be the bests as they stood **before** the workout.
    struct Bests: Hashable, Sendable {
        public var e1RM: [ExerciseID: Weight]
        public var weightAtReps: [ExerciseID: [Reps: Weight]]

        public init(e1RM: [ExerciseID: Weight] = [:], weightAtReps: [ExerciseID: [Reps: Weight]] = [:]) {
            self.e1RM = e1RM
            self.weightAtReps = weightAtReps
        }

        /// The heaviest set of the exercise, and of two as heavy the one with more reps (as
        /// `StatsQueries.bestSet`); `nil` when it has none.
        public func bestSet(of exerciseID: ExerciseID) -> (weight: Weight, reps: Reps)? {
            weightAtReps[exerciseID]?
                .map { (weight: $0.value, reps: $0.key) }
                .max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
        }

        /// The bests once `workout` is done: its sets that count toward bests raise them. A deload workout's sets
        /// count too; only its own records are skipped (`detect`).
        public mutating func include(_ workout: WorkoutState) {
            for exercise in workout.exercises {
                for set in exercise.sets where PersonalRecords.countsTowardBests(set) {
                    let id = exercise.exerciseID
                    if let estimate = OneRepMax.brzycki(weight: set.weight, reps: set.reps) {
                        e1RM[id] = max(e1RM[id] ?? estimate, estimate)
                    }
                    let heaviest = weightAtReps[id]?[set.reps].map { max($0, set.weight) } ?? set.weight
                    weightAtReps[id, default: [:]][set.reps] = heaviest
                }
            }
        }
    }
}
