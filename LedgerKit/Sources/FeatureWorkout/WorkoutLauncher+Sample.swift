#if DEBUG
    import LedgerDesign
    import LedgerDomain
    import LedgerFakes

    /// The Debug menu's "Start sample workout" (F10 plan, O15), so that the cover can be reached on a database
    /// with no program, before onboarding and Today are wired to it. Debug builds only, like the menu.
    public extension WorkoutLauncher {
        /// Starts the first day of the active program, in its first week, as `start(_:)` would; with no active
        /// program it first saves the spec's seed program (`Fixtures.seedProgram()`) as the active one. Every
        /// start makes a new workout id, as every start does.
        func startSample() {
            accept(.sample)
        }
    }

    public extension DebugMenu.Action {
        /// The menu's row for `WorkoutLauncher.startSample()`. The UI tests find it by its identifier.
        static func startSampleWorkout(_ perform: @escaping @MainActor () -> Void) -> DebugMenu.Action {
            DebugMenu.Action("Start sample workout", identifier: "debug.menu.startSampleWorkout", perform: perform)
        }
    }

    nonisolated enum WorkoutSample {
        /// The seed program was saved and holds no day: it cannot happen with the fixture as it is.
        struct NoDay: Error {}

        /// The first day of the first week of the active program, which is the seed program when there was
        /// none. The first week is always inside the block, whatever today's date is.
        static func source(in programs: any ProgramRepository) async throws -> WorkoutSource {
            var program = try await programs.active()
            if program == nil {
                let seed = try Fixtures.seedProgram()
                try await programs.save(seed)
                program = seed
            }
            guard let program, let day = program.days.first else {
                throw NoDay()
            }
            return WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: day.id)
        }
    }
#endif
