import Dependencies
import LedgerDomain
#if DEBUG
    import LedgerFakes
#endif

// The stores' keys (architecture §13). `liveValue` is an `Unimplemented*` stub until the composition root binds
// the GRDB stores over one database (F07 S2); `testValue` is the library's default, which fails the test naming
// the key, so a test configures every store it touches (`withTestDependencies`); `previewValue` is an in-memory
// store seeded with the fixtures (`PreviewStores`).

public extension DependencyValues {
    var exerciseRepository: any ExerciseRepository {
        get { self[ExerciseRepositoryKey.self] }
        set { self[ExerciseRepositoryKey.self] = newValue }
    }

    var programRepository: any ProgramRepository {
        get { self[ProgramRepositoryKey.self] }
        set { self[ProgramRepositoryKey.self] = newValue }
    }

    var workoutRepository: any WorkoutRepository {
        get { self[WorkoutRepositoryKey.self] }
        set { self[WorkoutRepositoryKey.self] = newValue }
    }

    var workoutEventStore: any WorkoutEventStore {
        get { self[WorkoutEventStoreKey.self] }
        set { self[WorkoutEventStoreKey.self] = newValue }
    }

    var settingsRepository: any SettingsRepository {
        get { self[SettingsRepositoryKey.self] }
        set { self[SettingsRepositoryKey.self] = newValue }
    }

    var statsQueries: any StatsQueries {
        get { self[StatsQueriesKey.self] }
        set { self[StatsQueriesKey.self] = newValue }
    }
}

enum ExerciseRepositoryKey: DependencyKey {
    static let liveValue: any ExerciseRepository = UnimplementedExerciseRepository()
    #if DEBUG
        static var previewValue: any ExerciseRepository {
            PreviewStores.make().exercises
        }
    #endif
}

enum ProgramRepositoryKey: DependencyKey {
    static let liveValue: any ProgramRepository = UnimplementedProgramRepository()
    #if DEBUG
        static var previewValue: any ProgramRepository {
            PreviewStores.make().programs
        }
    #endif
}

enum WorkoutRepositoryKey: DependencyKey {
    static let liveValue: any WorkoutRepository = UnimplementedWorkoutRepository()
    #if DEBUG
        static var previewValue: any WorkoutRepository {
            PreviewStores.make().workouts
        }
    #endif
}

enum WorkoutEventStoreKey: DependencyKey {
    static let liveValue: any WorkoutEventStore = UnimplementedWorkoutEventStore()
    #if DEBUG
        static var previewValue: any WorkoutEventStore {
            PreviewStores.make().events
        }
    #endif
}

enum SettingsRepositoryKey: DependencyKey {
    static let liveValue: any SettingsRepository = UnimplementedSettingsRepository()
    #if DEBUG
        static var previewValue: any SettingsRepository {
            PreviewStores.make().settings
        }
    #endif
}

enum StatsQueriesKey: DependencyKey {
    static let liveValue: any StatsQueries = UnimplementedStatsQueries()
    #if DEBUG
        static var previewValue: any StatsQueries {
            PreviewStores.make().stats
        }
    #endif
}

#if DEBUG
    /// The stores previews read: `InMemoryStores.Seed.preview()` (the catalog, the spec's seed program and eight
    /// weeks of its history), with the stats' current time `Fixtures.now`.
    ///
    /// The library computes each key's `previewValue` once, so each store comes from its own `make()`: all hold
    /// the same seed, but a write in a live preview reaches only the store it went to. A preview that needs
    /// them linked binds one `InMemoryStores` to every key with `withDependencies`.
    enum PreviewStores {
        static func make() -> InMemoryStores {
            // `FixturesTests` proves the preview seed builds; should it ever fail, a preview shows empty stores
            // rather than crash the canvas.
            InMemoryStores(seed: (try? InMemoryStores.Seed.preview()) ?? .empty)
        }
    }
#endif
