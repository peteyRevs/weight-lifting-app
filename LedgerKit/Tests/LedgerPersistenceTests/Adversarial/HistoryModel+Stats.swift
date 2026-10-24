import Foundation
import LedgerDomain

/// `HistoryModel` as the stats queries: each one computed from the live workouts' states, in memory.
extension HistoryModel: StatsQueries {
    /// The sets of `exercise` in `workout`, across every row that performs it, in row order.
    private func sets(of exercise: ExerciseID, in workout: WorkoutState) -> [LoggedSet] {
        workout.exercises.filter { $0.exerciseID == exercise }.flatMap(\.sets)
    }

    /// The done sets of `exercise` that can hold a best: `.working` and `.added` (decision #3).
    private func recordSets(of exercise: ExerciseID, in workout: WorkoutState) -> [LoggedSet] {
        var kinds: Set<SetKind> = [.working, .added]
        if has(.bestsCountWarmups) {
            kinds.insert(.warmup)
        }
        if has(.bestsCountDrops) {
            kinds.insert(.drop)
        }
        return sets(of: exercise, in: workout).filter { $0.isDone && kinds.contains($0.kind) }
    }

    private func estimate(_ set: LoggedSet) -> Weight? {
        if has(.estimatesAbove12Reps), set.reps.value > OneRepMax.maximumReps, set.reps.value < 37 {
            return Weight(grams: set.weight.grams * 36 / Decimal(37 - set.reps.value))
        }
        return OneRepMax.brzycki(weight: set.weight, reps: set.reps)
    }

    private func isHeavier(_ lhs: LoggedSet, _ rhs: LoggedSet) -> Bool {
        lhs.weight != rhs.weight ? lhs.weight > rhs.weight : lhs.reps > rhs.reps
    }

    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
        let workouts = state.withLock { live($0) }
        for workout in workouts {
            let all = sets(of: exerciseID, in: workout)
            let counted = all.filter { $0.isDone && ($0.kind == .working || has(.lastCountsEveryKind)) }
            let shown = has(.lastIsFirstSet) ? counted.first : counted.min(by: isHeavier)
            guard let shown else {
                if has(.lastOfAnyWorkout), !all.isEmpty {
                    return nil
                }
                continue
            }
            return LastPerformance(date: date(workout), sets: counted.count, reps: shown.reps.value, load: shown.weight)
        }
        return nil
    }

    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        let sets = state.withLock { live($0) }.flatMap { recordSets(of: exerciseID, in: $0) }
        let best = sets.min { lhs, rhs in
            has(.bestSetFewerReps) && lhs.weight == rhs.weight ? lhs.reps < rhs.reps : isHeavier(lhs, rhs)
        }
        return best.map { ($0.weight, $0.reps) }
    }

    /// F12 S1 (sanctioned): `bestSet(exerciseID:)` of every exercise with a set that counts.
    func bestSets() async throws -> [ExerciseID: BestSet] {
        let ids = Set(state.withLock { live($0) }.flatMap { $0.exercises.map(\.exerciseID) })
        var bests: [ExerciseID: BestSet] = [:]
        for id in ids {
            if let best = try await bestSet(exerciseID: id) {
                bests[id] = BestSet(weight: best.weight, reps: best.reps)
            }
        }
        return bests
    }

    func bestE1RM(exerciseID: ExerciseID) async throws -> Weight? {
        state.withLock { live($0) }.flatMap { recordSets(of: exerciseID, in: $0) }.compactMap(estimate).max()
    }

    func e1RMByWeek(
        exerciseID: ExerciseID,
        lastWeeks: Int,
        calendar given: WeekCalendar
    ) async throws -> [WeekKey: Weight] {
        let calendar = has(.weeksInUTCFromMonday) ? S3Kit.calendar() : given
        guard lastWeeks > 0, calendar.firstDayOfWeek(containing: now) != nil else {
            return [:]
        }
        var best: [WeekKey: Weight] = [:]
        for workout in state.withLock({ live($0) }) {
            let sets = recordSets(of: exerciseID, in: workout)
            let top = sets.compactMap { set in estimate(set).map { (estimate: $0, set: set) } }
                .max { $0.estimate < $1.estimate }
            guard let top else {
                continue
            }
            let dated = has(.weeksByTickTime) ? top.set.doneAt ?? date(workout) : date(workout)
            guard isInLastWeeks(dated, lastWeeks, calendar) else {
                continue
            }
            let key = calendar.isoWeekKey(for: dated)
            best[key] = max(best[key] ?? top.estimate, top.estimate)
        }
        return best
    }

    /// Whether `date` falls in one of the `count` stats weeks that end with the one holding `now`, found by
    /// walking the weeks back as ranges of instants.
    private func isInLastWeeks(_ date: Date, _ count: Int, _ calendar: WeekCalendar) -> Bool {
        var week = calendar.week(containing: now)
        if date >= week.upperBound {
            return has(.futureWeeksCount)
        }
        var back = 0
        while back < count {
            if week.contains(date) {
                return true
            }
            let previous = calendar.previousCompleteWeek(before: week.lowerBound)
            if previous == week {
                return false
            }
            week = previous
            back += 1
        }
        return false
    }

    func weeklyVolume(in range: Range<Date>) async throws -> Volume {
        let sets = state.withLock { live($0) }.filter { contains(range, date($0)) }
            .flatMap { $0.exercises.flatMap(\.sets) }
            .filter { $0.isDone && !(has(.volumeSkipsWarmups) && $0.kind == .warmup) }
        return sets.reduce(Volume.zero) { $0 + Volume(weight: $1.weight, reps: $1.reps) }
    }

    func sessionsCompleted(in range: Range<Date>) async throws -> Int {
        state.withLock { live($0) }.count { workout in
            contains(range, date(workout)) && (!has(.sessionsNeedADoneSet) || workout.doneSets > 0)
        }
    }

    func sessionCount(exerciseID: ExerciseID) async throws -> Int {
        state.withLock { live($0) }.count { workout in
            sets(of: exerciseID, in: workout).contains { $0.isDone || has(.sessionCountIgnoresDone) }
        }
    }

    /// Newest first by when each was achieved (the workout's start); of two workouts that start together, in
    /// list order (the smaller id first); within a workout, in detection order (the estimated 1RM first).
    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord] {
        let records = state.withLock { liveEntries($0) }.flatMap { entry in
            entry.records.filter { $0.exerciseID == exerciseID }
        }
        return records.enumerated().sorted { lhs, rhs in
            if lhs.element.achievedAt != rhs.element.achievedAt {
                return lhs.element.achievedAt > rhs.element.achievedAt
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    /// The bests of the live workouts before `workout` in history's order, folded with `PersonalRecords.Bests`,
    /// for `exerciseIDs` only, never `workout`'s own stored copy (review R-SF1, fix round 1: even one that started
    /// earlier). The `.bestsBeforeIncludeIt` fault counts that copy when it is at or before `workout`'s place.
    func bests(before workout: WorkoutState, for exerciseIDs: Set<ExerciseID>) async throws -> PersonalRecords.Bests {
        let key = (date(workout), workout.id.rawValue.uuidString)
        let all = state.withLock { historyOrder($0) }.reduce(into: PersonalRecords.Bests()) { bests, entry in
            let place = (date(entry.state), entry.state.id.rawValue.uuidString)
            let counted = entry.state.id == workout.id ? has(.bestsBeforeIncludeIt) && place <= key : place < key
            if counted {
                bests.include(entry.state)
            }
        }
        return PersonalRecords.Bests(
            e1RM: all.e1RM.filter { exerciseIDs.contains($0.key) },
            weightAtReps: all.weightAtReps.filter { exerciseIDs.contains($0.key) }
        )
    }

    func recentlyLogged(limit: Int) async throws -> [ExerciseID] {
        var latest: [ExerciseID: (date: Date, place: Int)] = [:]
        for workout in state.withLock({ live($0) }) {
            for (place, exercise) in workout.exercises.enumerated() where exercise.sets.contains(where: \.isDone) {
                let found = (date: date(workout), place: place)
                latest[exercise.exerciseID] = latest[exercise.exerciseID]
                    .map { $0.date >= found.date ? $0 : found } ?? found
            }
        }
        let ordered = latest.sorted { lhs, rhs in
            if lhs.value.date != rhs.value.date {
                return lhs.value.date > rhs.value.date
            }
            return has(.recentlyLoggedInWorkoutOrder)
                ? lhs.value.place < rhs.value.place
                : lhs.key.rawValue.uuidString < rhs.key.rawValue.uuidString
        }
        return limit < 0 && has(.negativeLimitIsAll) ? ordered.map(\.key) : ordered.prefix(max(0, limit)).map(\.key)
    }

    /// F12 S2 (sanctioned): each live workout with a done set of the exercise, newest first, its done sets in row
    /// order, dated as every other query here dates it.
    func exerciseSessions(exerciseID: ExerciseID) async throws -> [ExerciseSession] {
        state.withLock { sessions(of: exerciseID, in: $0) }
    }

    /// F12 S2 (sanctioned): `exerciseSessions` now, then after every write that changes it.
    func observeExerciseSessions(exerciseID: ExerciseID) -> AsyncStream<[ExerciseSession]> {
        let (stream, continuation) = AsyncStream<[ExerciseSession]>.makeStream()
        state.withLock { state in
            let first = sessions(of: exerciseID, in: state)
            continuation.yield(first)
            let observer = SessionObserver(exerciseID: exerciseID, continuation: continuation, last: first)
            state.sessionObservers.append(observer)
        }
        return stream
    }

    func sessions(of exerciseID: ExerciseID, in state: State) -> [ExerciseSession] {
        live(state).compactMap { workout in
            let done = sets(of: exerciseID, in: workout).filter(\.isDone)
            return done.isEmpty ? nil : ExerciseSession(workoutID: workout.id, startedAt: date(workout), sets: done)
        }
    }
}
