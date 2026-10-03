#if DEBUG
    import Foundation
    import LedgerDomain

    /// `ExerciseRepository` in memory, keeping `ExerciseRepositoryContract` (LedgerTestSupport) as the GRDB
    /// repository does: it searches, filters and orders with `ExerciseSearch`, the helper the GRDB repository
    /// uses, so the two cannot drift; and it seeds as product decision #24 says.
    public final class InMemoryExerciseRepository: ExerciseRepository {
        struct Row: Equatable, Sendable {
            var exercise: Exercise
            /// The catalog version that last wrote the row; `nil` for a custom exercise or one the lifter saved,
            /// which a catalog upgrade never touches.
            var catalogVersion: Int?
        }

        struct State: Sendable {
            var rows: [ExerciseID: Row] = [:]

            var all: [Exercise] {
                ExerciseSearch.sorted(rows.values.map(\.exercise))
            }
        }

        private let state: ObservedState<State, [Exercise]>

        /// An empty repository, or one holding `catalog` as seeded at `version` (`seedIfNeeded`'s rule).
        public init(catalog: [Exercise] = [], version: Int = 1) {
            var initial = State()
            Self.seed(catalog, version: version, into: &initial)
            state = ObservedState(initial)
        }

        public func all() async throws -> [Exercise] {
            state.read(\.all)
        }

        public func exercise(id: ExerciseID) async throws -> Exercise? {
            state.read { $0.rows[id]?.exercise }
        }

        public func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise] {
            let needle = ExerciseSearch.key(query)
            return state.read(\.all).filter { exercise in
                ExerciseSearch.matches(name: exercise.name, shortName: exercise.shortName, needle: needle)
                    && equipment.map { exercise.equipment == $0 } ?? true
                    && muscle.map { exercise.primaryMuscle == $0 } ?? true
            }
        }

        /// Stores the exercise as the lifter's, so a catalog upgrade leaves it (decision #24).
        public func save(_ exercise: Exercise) async throws {
            try Self.refuseNul(in: exercise)
            state.write { $0.rows[exercise.id] = Row(exercise: exercise, catalogVersion: nil) }
        }

        public func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws {
            try state.write { current throws(RepositoryError) in
                for entry in Self.written(catalog, at: version, over: current) {
                    try Self.refuseNul(in: entry)
                }
                Self.seed(catalog, version: version, into: &current)
            }
        }

        public func observeAll() -> AsyncStream<[Exercise]> {
            state.observe(\.all)
        }

        /// Writes the entries `written(_:at:over:)` picks, each as a catalog exercise of `version`.
        private static func seed(_ catalog: [Exercise], version: Int, into state: inout State) {
            for entry in written(catalog, at: version, over: state) {
                var exercise = entry
                exercise.isCustom = false
                state.rows[entry.id] = Row(exercise: exercise, catalogVersion: version)
            }
        }

        /// The entries a seed at `version` writes, in the catalog's order: none unless `version` is above the
        /// applied one (the highest a catalog row records); then every new id, and every catalog row of an older
        /// version, the last entry of an id listed twice. Custom exercises and those the lifter saved are left.
        private static func written(_ catalog: [Exercise], at version: Int, over state: State) -> [Exercise] {
            let applied = state.rows.values.compactMap(\.catalogVersion).max()
            guard applied.map({ $0 < version }) ?? true else {
                return []
            }
            var seen = Set<ExerciseID>()
            let lastOfEachID = catalog.reversed().filter { seen.insert($0.id).inserted }.reversed()
            return lastOfEachID.filter { entry in
                guard let row = state.rows[entry.id] else {
                    return true
                }
                guard let rowVersion = row.catalogVersion else {
                    return false
                }
                return rowVersion < version
            }
        }

        /// Text holding U+0000 is refused, as SQLite would cut it short.
        private static func refuseNul(in exercise: Exercise) throws(RepositoryError) {
            if exercise.name.unicodeScalars.contains("\0") {
                throw .nulInText("exercise.name")
            }
            if exercise.shortName.unicodeScalars.contains("\0") {
                throw .nulInText("exercise.short_name")
            }
        }
    }
#endif
