#if DEBUG
    import LedgerDesign
    import LedgerDomain
    import LedgerFakes

    /// The Debug menu's sample workouts (F10 plan, O15), so that the cover and the conflict with a workout
    /// that is already running can be reached on a database with no program, before onboarding and Today are
    /// wired to them. Debug builds only, like the menu.
    public extension WorkoutLauncher {
        /// Starts the day at `day` in the active program (0 is its first), in its first week, as `start(_:)`
        /// would; with no active program it first saves the spec's seed program (`Fixtures.seedProgram()`)
        /// as the active one. Every start makes a new workout id, as every start does.
        func startSample(day: Int = 0) {
            accept(.sample(day: day))
        }
    }

    public extension DebugMenu.Action {
        /// The menu's two rows for `WorkoutLauncher.startSample(day:)`: the first day, and the second, which
        /// asks for another day while the first one's workout is running. The UI tests find them by their
        /// identifiers; `perform` is handed the row's day.
        static func sampleWorkouts(_ perform: @escaping @MainActor (Int) -> Void) -> [DebugMenu.Action] {
            [
                DebugMenu.Action("Start sample workout", identifier: "debug.menu.startSampleWorkout") { perform(0) },
                DebugMenu.Action(
                    "Start another day's sample workout",
                    identifier: "debug.menu.startOtherSampleWorkout"
                ) {
                    perform(1)
                }
            ]
        }
    }

    /// The program the sample starts its workouts in, which the UI tests also open on (F08, ruling R2: the app's
    /// `-LEDGER_UITEST_PROGRAM seed`).
    public nonisolated enum SampleProgram {
        /// The active program; with none, the spec's seed program (`Fixtures.seedProgram()`), saved as the active
        /// one first.
        @discardableResult
        public static func activeOrSeed(in programs: any ProgramRepository) async throws -> Program {
            if let active = try await programs.active() {
                return active
            }
            let seed = try Fixtures.seedProgram()
            try await programs.save(seed)
            return seed
        }
    }

    nonisolated enum WorkoutSample {
        /// The active program holds no day at that place: it cannot happen with the seed program as it is.
        struct NoDay: Error {}

        /// The day at `index` of the active program, in its first week; the program is the seed program when
        /// there was none. The first week is always inside the block, whatever today's date is.
        static func source(day index: Int, in programs: any ProgramRepository) async throws -> WorkoutSource {
            let program = try await SampleProgram.activeOrSeed(in: programs)
            guard program.days.indices.contains(index) else {
                throw NoDay()
            }
            return WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: program.days[index].id)
        }
    }
#endif
