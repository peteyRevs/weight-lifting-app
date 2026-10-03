#if DEBUG
    import Foundation
    import LedgerDomain

    /// The six in-memory stores, linked where one database links them: the stats read the workouts' history; a
    /// materialised workout's slot updates reach the programs in the same step; and a program saved with a slot
    /// naming an exercise the exercise store does not hold is refused (`unknownExercise`), as the slot's foreign
    /// key refuses it. Settings and the event store stand alone, as their tables do. Built from a `Seed`, which is
    /// stored state: kept as given, without the exercise check (like a database restored as it was).
    public struct InMemoryStores: Sendable {
        /// What the stores hold when they are built.
        public struct Seed: Sendable {
            /// Seeded as the bundled catalog is, at `catalogVersion`.
            public var catalog: [Exercise]
            public var catalogVersion: Int
            public var programs: [Program]
            /// Finished workouts; any other is left out.
            public var workouts: [WorkoutState]
            public var settings: Settings
            public var envelopes: [EventEnvelope]

            public init(
                catalog: [Exercise] = [],
                catalogVersion: Int = ExerciseCatalog.version,
                programs: [Program] = [],
                workouts: [WorkoutState] = [],
                settings: Settings = .default,
                envelopes: [EventEnvelope] = []
            ) {
                self.catalog = catalog
                self.catalogVersion = catalogVersion
                self.programs = programs
                self.workouts = workouts
                self.settings = settings
                self.envelopes = envelopes
            }

            /// Nothing stored: a first launch before seeding.
            public static let empty = Seed()

            /// What previews show: the bundled catalog, the spec's seed program (active), eight weeks of its
            /// history up to `Fixtures.now`, and the default settings in pounds.
            public static func preview() throws -> Seed {
                try Seed(
                    catalog: ExerciseCatalog.seed(),
                    programs: [Fixtures.seedProgram()],
                    workouts: Fixtures.history(weeks: 8),
                    settings: Fixtures.settingsLb
                )
            }
        }

        public let exercises: InMemoryExerciseRepository
        public let programs: InMemoryProgramRepository
        public let workouts: InMemoryWorkoutRepository
        public let stats: InMemoryStatsQueries
        public let settings: InMemorySettingsRepository
        public let events: InMemoryWorkoutEventStore

        /// - Parameter now: the stats' current time, which says which week is the current one.
        public init(seed: Seed = .empty, now: @escaping @Sendable () -> Date = { Fixtures.now }) {
            exercises = InMemoryExerciseRepository(catalog: seed.catalog, version: seed.catalogVersion)
            programs = InMemoryProgramRepository(programs: seed.programs, exercises: exercises)
            workouts = InMemoryWorkoutRepository(programs: programs, workouts: seed.workouts)
            stats = InMemoryStatsQueries(workouts, now: now)
            settings = InMemorySettingsRepository(seed.settings)
            events = InMemoryWorkoutEventStore(seed.envelopes)
        }
    }
#endif
