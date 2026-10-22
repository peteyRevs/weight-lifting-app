#if DEBUG
    import Foundation
    import LedgerDomain

    /// `StatsQueries` in memory over an `InMemoryWorkoutRepository`'s history, keeping `StatsQueriesContract`
    /// (LedgerTestSupport): each query computed from the live workouts' states, as F05's adversarial
    /// `HistoryModel` computes them. Which sets count differs by query (product decision #25): the "Last" line
    /// counts done `.working` sets, the bests done `.working` and `.added` sets, and volume, `sessionCount` and
    /// `recentlyLogged` every done set.
    public struct InMemoryStatsQueries: StatsQueries {
        private let workouts: InMemoryWorkoutRepository
        private let now: @Sendable () -> Date

        /// - Parameter now: the current time, which says which week is the current one.
        public init(_ workouts: InMemoryWorkoutRepository, now: @escaping @Sendable () -> Date) {
            self.workouts = workouts
            self.now = now
        }

        private var live: [WorkoutState] {
            workouts.history.read(\.live)
        }

        public func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
            for workout in live {
                let working = Self.sets(of: exerciseID, in: workout).filter { $0.isDone && $0.kind == .working }
                if let shown = working.min(by: Self.isHeavier) {
                    return LastPerformance(
                        date: workout.startedAt,
                        sets: working.count,
                        reps: shown.reps.value,
                        load: shown.weight
                    )
                }
            }
            return nil
        }

        public func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
            let best = live.flatMap { Self.recordSets(of: exerciseID, in: $0) }.min(by: Self.isHeavier)
            return best.map { ($0.weight, $0.reps) }
        }

        /// `bestSet(exerciseID:)`'s rule over every exercise, in one walk of the live workouts' sets, so the
        /// contract's comparison of the two is not this query against itself (review R2-5).
        public func bestSets() async throws -> [ExerciseID: BestSet] {
            var best: [ExerciseID: LoggedSet] = [:]
            for exercise in live.flatMap(\.exercises) {
                for set in exercise.sets where set.isDone && (set.kind == .working || set.kind == .added) {
                    if best[exercise.exerciseID].map({ Self.isHeavier(set, $0) }) ?? true {
                        best[exercise.exerciseID] = set
                    }
                }
            }
            return best.mapValues { BestSet(weight: $0.weight, reps: $0.reps) }
        }

        public func bestE1RM(exerciseID: ExerciseID) async throws -> Weight? {
            live.flatMap { Self.recordSets(of: exerciseID, in: $0) }.compactMap(Self.estimate).max()
        }

        public func e1RMByWeek(
            exerciseID: ExerciseID,
            lastWeeks: Int,
            calendar: WeekCalendar
        ) async throws -> [WeekKey: Weight] {
            let current = now()
            guard lastWeeks > 0, calendar.firstDayOfWeek(containing: current) != nil else {
                return [:]
            }
            var best: [WeekKey: Weight] = [:]
            for workout in live {
                let top = Self.recordSets(of: exerciseID, in: workout).compactMap(Self.estimate).max()
                guard let top, Self.isInLastWeeks(workout.startedAt, lastWeeks, calendar, now: current) else {
                    continue
                }
                let key = calendar.isoWeekKey(for: workout.startedAt)
                best[key] = max(best[key] ?? top, top)
            }
            return best
        }

        public func weeklyVolume(in range: Range<Date>) async throws -> Volume {
            live.filter { range.contains($0.startedAt) }
                .flatMap { $0.exercises.flatMap(\.sets) }
                .filter(\.isDone)
                .reduce(Volume.zero) { $0 + Volume(weight: $1.weight, reps: $1.reps) }
        }

        public func sessionsCompleted(in range: Range<Date>) async throws -> Int {
            live.count { range.contains($0.startedAt) }
        }

        public func sessionCount(exerciseID: ExerciseID) async throws -> Int {
            live.count { workout in Self.sets(of: exerciseID, in: workout).contains(where: \.isDone) }
        }

        /// Newest first by when each was achieved (the workout's start); of two workouts that started together,
        /// in list order (the smaller id first); within a workout, in detection order (the estimated 1RM first).
        public func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord] {
            let records = workouts.history.read(\.newestFirst).flatMap { entry in
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

        /// The bests of the live workouts before `workout` in history's order, never `workout`'s own stored copy,
        /// for `exerciseIDs` only.
        public func bests(
            before workout: WorkoutState,
            for exerciseIDs: Set<ExerciseID>
        ) async throws -> PersonalRecords.Bests {
            let place = InMemoryHistory.place(of: workout)
            let all = workouts.history.read(\.historyOrder).reduce(into: PersonalRecords.Bests()) { bests, entry in
                if entry.workout.id != workout.id, InMemoryHistory.place(of: entry.workout) < place {
                    bests.include(entry.workout)
                }
            }
            return PersonalRecords.Bests(
                e1RM: all.e1RM.filter { exerciseIDs.contains($0.key) },
                weightAtReps: all.weightAtReps.filter { exerciseIDs.contains($0.key) }
            )
        }

        public func recentlyLogged(limit: Int) async throws -> [ExerciseID] {
            var latest: [ExerciseID: Date] = [:]
            for workout in live {
                for exercise in workout.exercises where exercise.sets.contains(where: \.isDone) {
                    latest[exercise.exerciseID] = max(
                        latest[exercise.exerciseID] ?? workout.startedAt,
                        workout.startedAt
                    )
                }
            }
            let ordered = latest.sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.rawValue.uuidString < rhs.key.rawValue.uuidString
            }
            return ordered.prefix(max(0, limit)).map(\.key)
        }

        // MARK: Helpers

        /// The sets of `exercise` in `workout`, across every row that performs it, in row order.
        private static func sets(of exercise: ExerciseID, in workout: WorkoutState) -> [LoggedSet] {
            workout.exercises.filter { $0.exerciseID == exercise }.flatMap(\.sets)
        }

        /// The done sets of `exercise` that can hold a best: `.working` and `.added` (decision #25).
        private static func recordSets(of exercise: ExerciseID, in workout: WorkoutState) -> [LoggedSet] {
            sets(of: exercise, in: workout).filter { $0.isDone && ($0.kind == .working || $0.kind == .added) }
        }

        private static func estimate(_ set: LoggedSet) -> Weight? {
            OneRepMax.brzycki(weight: set.weight, reps: set.reps)
        }

        /// The heavier of two sets, and of two as heavy the one with more reps.
        private static func isHeavier(_ lhs: LoggedSet, _ rhs: LoggedSet) -> Bool {
            lhs.weight != rhs.weight ? lhs.weight > rhs.weight : lhs.reps > rhs.reps
        }

        /// Whether `date` falls in one of the `count` stats weeks that end with the one holding `now`, found by
        /// walking the weeks back as ranges of instants.
        private static func isInLastWeeks(_ date: Date, _ count: Int, _ calendar: WeekCalendar, now: Date) -> Bool {
            var week = calendar.week(containing: now)
            if date >= week.upperBound {
                return false
            }
            for _ in 0 ..< count {
                if week.contains(date) {
                    return true
                }
                let previous = calendar.previousCompleteWeek(before: week.lowerBound)
                if previous == week {
                    return false
                }
                week = previous
            }
            return false
        }
    }
#endif
