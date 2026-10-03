#if DEBUG
    import Foundation
    import LedgerDomain

    /// The finished workouts `InMemoryWorkoutRepository` stores and `InMemoryStatsQueries` reads: ported from
    /// F05's adversarial `HistoryModel`, the in-memory oracle the GRDB types were checked against, without its
    /// fault injection.
    struct InMemoryHistory: Sendable {
        struct Entry: Sendable {
            var workout: WorkoutState
            /// Detected by `detectRecords()`, never given (product decision #27).
            var records: [PersonalRecord] = []
            var isDeleted = false
        }

        var entries: [WorkoutID: Entry] = [:]
        /// The workout each exercise and set id belongs to, kept after a delete: the ids stay taken.
        var exerciseOwners: [WorkoutExerciseID: WorkoutID] = [:]
        var setOwners: [SetID: WorkoutID] = [:]

        // MARK: Reads

        /// The live workouts with their records, newest first by start (product decision #26); of two that
        /// started together, the smaller id first, as the stored id text sorts.
        var newestFirst: [Entry] {
            entries.values.filter { !$0.isDeleted }.sorted { lhs, rhs in
                if lhs.workout.startedAt != rhs.workout.startedAt {
                    return lhs.workout.startedAt > rhs.workout.startedAt
                }
                return lhs.workout.id.rawValue.uuidString < rhs.workout.id.rawValue.uuidString
            }
        }

        /// The live workouts in history's order, oldest first: by start, then id text.
        var historyOrder: [Entry] {
            entries.values.filter { !$0.isDeleted }.sorted { lhs, rhs in
                Self.place(of: lhs.workout) < Self.place(of: rhs.workout)
            }
        }

        var live: [WorkoutState] {
            newestFirst.map(\.workout)
        }

        func recent(_ limit: Int) -> [WorkoutState] {
            Array(live.prefix(max(0, limit)))
        }

        /// A workout's place in history: its start, then its id text.
        static func place(of workout: WorkoutState) -> (Date, String) {
            (workout.startedAt, workout.id.rawValue.uuidString)
        }

        /// What a history read returns for `workout`: the live-only fields reset.
        static func stored(_ workout: WorkoutState) -> WorkoutState {
            var stored = workout
            stored.cursor = nil
            stored.rest = nil
            stored.autoRest = true
            stored.programUpdates = [:]
            for index in stored.exercises.indices {
                stored.exercises[index].lastPerformance = nil
            }
            return stored
        }

        // MARK: Writes

        /// Stores `workout` over any copy of it, deleted or not, or throws and stores nothing.
        mutating func store(_ workout: WorkoutState) throws(RepositoryError) {
            try refuseIDs(of: workout)
            try Self.refuseNul(in: workout)
            entries[workout.id] = Entry(workout: Self.stored(workout), records: entries[workout.id]?.records ?? [])
            for exercise in workout.exercises {
                exerciseOwners[exercise.id] = workout.id
                for set in exercise.sets {
                    setOwners[set.id] = workout.id
                }
            }
        }

        /// Product decision #27: every live workout's records are `PersonalRecords.detect` against the bests of
        /// the workouts before it, achieved at its start. Replayed from scratch after every write, the simplest
        /// honest way to keep them a function of history (the database replays only what a write touched).
        mutating func detectRecords() {
            var before = PersonalRecords.Bests()
            for entry in historyOrder {
                let workout = entry.workout
                entries[workout.id]?.records = PersonalRecords.detect(
                    workout: workout,
                    against: before,
                    now: workout.startedAt
                )
                before.include(workout)
            }
        }

        /// Throws `duplicateIdentifier` as the GRDB repository orders it: ids another workout holds (exercises,
        /// then sets, the smallest id first), then an id used twice (exercises, then sets, the first repeat).
        private func refuseIDs(of workout: WorkoutState) throws(RepositoryError) {
            let exercises = workout.exercises.map(\.id)
            let sets = workout.exercises.flatMap(\.sets).map(\.id)
            let takenExercises = exercises.filter { exerciseOwners[$0].map { $0 != workout.id } ?? false }
            if let taken = takenExercises.map(\.rawValue.uuidString).min() {
                throw .duplicateIdentifier("workout_exercise \(taken)")
            }
            let takenSets = sets.filter { setOwners[$0].map { $0 != workout.id } ?? false }
            if let taken = takenSets.map(\.rawValue.uuidString).min() {
                throw .duplicateIdentifier("logged_set \(taken)")
            }
            var seenExercises = Set<WorkoutExerciseID>()
            for id in exercises where !seenExercises.insert(id).inserted {
                throw .duplicateIdentifier("workout_exercise \(id.rawValue.uuidString)")
            }
            var seenSets = Set<SetID>()
            for id in sets where !seenSets.insert(id).inserted {
                throw .duplicateIdentifier("logged_set \(id.rawValue.uuidString)")
            }
        }

        private static func refuseNul(in workout: WorkoutState) throws(RepositoryError) {
            if workout.name.unicodeScalars.contains("\0") {
                throw .nulInText("workout.name")
            }
            if workout.tag.unicodeScalars.contains("\0") {
                throw .nulInText("workout.tag")
            }
            if workout.exercises.contains(where: { $0.name.unicodeScalars.contains("\0") }) {
                throw .nulInText("workout_exercise.name")
            }
        }
    }
#endif
