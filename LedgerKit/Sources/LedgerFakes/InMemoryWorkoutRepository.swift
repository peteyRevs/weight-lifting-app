#if DEBUG
    import Foundation
    import LedgerDomain

    /// `WorkoutRepository` in memory, keeping `WorkoutRepositoryContract` (LedgerTestSupport): an upsert that
    /// stores all or nothing, newest-first reads by start (product decision #26), soft deletion, and personal
    /// records that are a function of history (decision #27), replayed from scratch after every write.
    ///
    /// `InMemoryStatsQueries` reads the same history, and a `materialize` writes the misses of its `slotUpdates`
    /// and the exercises of its workout's `programUpdates` to `programs`, and drops the workout's log from
    /// `events` when asked, in the same step as the workout, so the stores answer as one database would.
    /// Weights and dates are refused as the database's columns refuse them (`StorageBoundary`, ADR-007).
    public final class InMemoryWorkoutRepository: WorkoutRepository {
        let history: ObservedState<InMemoryHistory>
        private let programs: InMemoryProgramRepository
        private let events: InMemoryWorkoutEventStore?

        /// Holding `workouts`, each materialised in order (one that would fail is left out); slot and program
        /// updates go to `programs`. With `events` (as `InMemoryStores` gives it), a save can drop the workout's
        /// log in the same step; without, this repository holds no log, and says so.
        public init(
            programs: InMemoryProgramRepository = InMemoryProgramRepository(),
            workouts: [WorkoutState] = [],
            events: InMemoryWorkoutEventStore? = nil
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
            self.events = events
        }

        /// Returns whether the log went with the save: only when asked, and only when an event store is linked,
        /// whose log it then is. Without one this repository holds no log, and answers `false`.
        public func materialize(
            _ workout: WorkoutState,
            slotUpdates: [Slot],
            droppingLog: Bool
        ) async throws -> Bool {
            guard workout.phase == .finished, workout.endedAt != nil else {
                throw RepositoryError.notFinished("workout \(workout.id.rawValue.uuidString)")
            }
            let log = droppingLog ? events : nil
            try history.write { current throws(RepositoryError) in
                try current.store(workout)
                current.detectRecords()
                // Last, once nothing can throw, in the database's order, and under this write's lock: no reader
                // sees the workout without its misses or its program changes, or with its log, as the
                // database's one transaction (the other stores' locks are only ever taken inside this one,
                // never the other way round).
                programs.writeSave(
                    misses: slotUpdates,
                    exercises: workout.programUpdates,
                    inProgram: workout.source?.programID
                )
                log?.drop(workout.id)
            }
            return log != nil
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

        /// Every live workout's entry, newest first, with the records it holds now (F13 S1).
        public func historyEntries() async throws -> [HistoryEntry] {
            history.read { $0.historyEntries }
        }

        /// `historyEntries()` now, then after every write that changes it (F13 S1).
        public func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
            history.observe { $0.historyEntries }
        }

        /// The live workout `id` with its records now, then after every write that changes either (F13 S2).
        public func observeWorkout(id: WorkoutID) -> AsyncStream<RecordedWorkout?> {
            history.observe { $0.recorded(id) }
        }
    }
#endif
