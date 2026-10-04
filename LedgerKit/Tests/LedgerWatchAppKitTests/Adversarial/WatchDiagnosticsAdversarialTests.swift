#if DEBUG
    import Foundation
    import LedgerDesign
    import LedgerDomain
    import LedgerFakes
    import LedgerPersistence
    @testable import LedgerWatchAppKit
    import Synchronization
    import Testing

    /// F07 S3 adversarial round 1: the watch's Diagnostics (criterion 7) and launch-to-first-frame (decision #30):
    /// row counts after real writes, and the first frame measured once on a clock that moves.
    @Suite("Adversarial F07 S3 · watch diagnostics", .timeLimit(.minutes(1)))
    struct WatchDiagnosticsAdversarialTests {
        static func values(_ sections: [DiagnosticsSection]) -> [String: String] {
            Dictionary(sections.flatMap(\.lines).map { ($0.id, $0.value) }) { first, _ in first }
        }

        @Test("Row counts follow writes: a program saved and a workout materialised show in their tables")
        func rowCounts_followWrites() async throws {
            let harness = Harness()
            defer { harness.remove() }
            let composition = harness.booted()
            await composition.resume(in: .active)
            let stores = try #require(composition.stores)
            let program = try Fixtures.seedProgram()
            try await stores.programs.save(program)
            let workout = try #require(Fixtures.history(weeks: 1).last)
            try await stores.workouts.materialize(workout, slotUpdates: [])
            let values = await Self.values(composition.diagnostics(health: .unavailable))
            let slots = program.days.flatMap(\.slots).count
            let sets = workout.exercises.flatMap(\.sets).count
            #expect(values["debug.diagnostics.rows.program"] == "1")
            #expect(values["debug.diagnostics.rows.program_week"] == String(program.weeks.count))
            #expect(values["debug.diagnostics.rows.slot"] == String(slots))
            #expect(values["debug.diagnostics.rows.workout"] == "1")
            #expect(values["debug.diagnostics.rows.workout_exercise"] == String(workout.exercises.count))
            #expect(values["debug.diagnostics.rows.logged_set"] == String(sets))
            #expect(values["debug.diagnostics.rows.device"] == "1")
            #expect(try values["debug.diagnostics.rows.exercise"] == String(ExerciseCatalog.seed().count))
            #expect(values["debug.diagnostics.health"] == "Unavailable")
        }

        @Test("The first frame is measured once: later appearances, on a clock that has moved, change nothing")
        func firstFrame_measuredOnce_onAMovingClock() {
            let harness = Harness()
            defer { harness.remove() }
            let clock = Mutex(Harness.now)
            var environment = harness.composition().environment
            environment.now = { clock.withLock { $0 } }
            environment.processStart = Harness.now.addingTimeInterval(-0.25)
            let composition = WatchComposition(environment)
            composition.rootAppeared()
            for _ in 0 ..< 3 {
                clock.withLock { $0 = $0.addingTimeInterval(60) }
                composition.rootAppeared() // the scene re-created, the app back from the background
            }
            #expect(composition.launchToFirstFrame == .milliseconds(250))
        }
    }
#endif
