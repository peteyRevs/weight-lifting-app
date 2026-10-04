#if DEBUG
    import Foundation
    import LedgerDomain

    /// `WorkoutRepository` in memory, keeping `WorkoutRepositoryContract` (LedgerTestSupport): an upsert that
    /// stores all or nothing, newest-first reads by start (product decision #26), soft deletion, and personal
    /// records that are a function of history (decision #27), replayed from scratch after every write.
    ///
    /// `InMemoryStatsQueries` reads the same history, and `materialize`'s `slotUpdates` write their misses to
    /// `programs` in the same step as the workout, so the three answer as one database would. Weights and dates
    /// are refused as the database's columns refuse them (`StorageBoundary`, ADR-007).
    public final class InMemoryWorkoutRepository: WorkoutRepository {
        let history: ObservedState<InMemoryHistory, [WorkoutState]>
        private let programs: InMemoryProgramRepository

        /// Holding `workouts`, each materialised in order (one that would fail is left out); slot updates go to
        /// `programs`.
        public init(
            programs: InMemoryProgramRepository = InMemoryProgramRepository(),
            workouts: [WorkoutState] = []
        ) {
            var initial = InMemoryHistory()
            for workout in workouts where workout.phase == .finished && workout.endedAt != nil {
                // A seed that would fail is a fixture bug, which `FixturesTests` catches; the store then starts
                // without it.
                try? initial.store(workout)
            }
            initial.detectRecords()
            history = ObservedState(initial)
            self.programs = programs
        }

        public func materialize(_ workout: WorkoutState, slotUpdates: [Slot]) async throws {
            guard workout.phase == .finished, workout.endedAt != nil else {
                throw RepositoryError.notFinished("workout \(workout.id.rawValue.uuidString)")
            }
            try history.write { current throws(RepositoryError) in
                try current.store(workout)
                current.detectRecords()
                // Last, once nothing can throw, and under this write's lock: no reader sees the workout without
                // its misses, as the database's one transaction (the program store's lock is only ever taken
                // inside this one, never the other way round).
                programs.writeMisses(of: slotUpdates)
            }
        }

        public func workout(id: WorkoutID) async throws -> WorkoutState? {
            history.read { current in current.entries[id].flatMap { $0.isDeleted ? nil : $0.workout } }
        }

        public func recent(limit: Int) async throws -> [WorkoutState] {
            history.read { $0.recent(limit) }
        }

        public func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
            history.read { $0.live.filter { range.contains($0.startedAt) } }
        }

        public func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
            try history.write { current throws(RepositoryError) in
                let owner = current.entries.values.first { entry in
                    !entry.isDeleted && entry.workout.exercises.contains { $0.id == workoutExerciseID }
                }
                guard var workout = owner?.workout,
                      let index = workout.exercises.firstIndex(where: { $0.id == workoutExerciseID })
                else {
                    throw .missingRow("workout_exercise \(workoutExerciseID.rawValue.uuidString)")
                }
                workout.exercises[index].sets = sets
                try current.store(workout)
                current.detectRecords()
            }
        }

        public func delete(id: WorkoutID) async throws {
            history.write { current in
                current.entries[id]?.isDeleted = true
                current.detectRecords()
            }
        }

        public func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
            history.observe { $0.recent(limit) }
        }
    }
#endif
