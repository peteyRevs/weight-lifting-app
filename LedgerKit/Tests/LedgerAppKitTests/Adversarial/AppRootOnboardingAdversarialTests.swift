#if os(iOS)
    import Foundation
    import GRDB
    @testable import LedgerAppKit
    import LedgerDomain
    import LedgerPersistence
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F08 S3 adversarial round 1 (G2), criteria 3, 5 and 6: onboarding as the app's real root hosts it, saving
    /// to the real database through the keys the composition binds. The root is given no callback: every
    /// switch to the tabs here happens because the gate followed the store.
    @Suite("Adversarial F08 S3 · onboarding through the real root", .serialized, .timeLimit(.minutes(1)))
    struct AppRootOnboardingAdversarialTests {
        static let failure = "Couldn't save your program. Try again."
        static let failed = [failure, "Retry", "Skip setup"]

        /// Refuses every write to the catalog, so the launch's seed step fails (product decision #28).
        static func refuseSeeds(_ app: GateApp) async throws {
            try await app.arrange { queue in
                try await queue.write { try $0.execute(sql: RootGateStoreAdversarialTests.refuseSeed) }
            }
        }

        static func allowSeeds(_ scene: GateRootScene) async throws {
            try await scene.stores.queue.write { database in
                try database.execute(sql: "DROP TRIGGER refuse_insert; DROP TRIGGER refuse_update")
            }
        }

        /// Suspends until onboarding's store has read the catalog `count` times: the last thing a save that
        /// fails for want of a catalog does, and the step before the write of one that succeeds.
        static func catalogRead(_ count: Int, in journal: GateJournal) async {
            await journal.until { entries in entries.count { $0.hasPrefix("exercises.all done") } >= count }
        }

        /// Criteria 3 and 6: `saved` is the generator's default block for a lifter in pounds whose weeks start
        /// on Monday, saved on Wednesday 2026-09-16: it starts on Monday 2026-09-14, and that Wednesday is in
        /// its week index 0.
        static func expectTheDefault(_ saved: Program, in scene: GateRootScene) async throws {
            let monday = try #require(CivilDate(year: 2026, month: 9, day: 14))
            let request = ProgramTemplates.Request(goal: .both, days: .four, units: .lb, startDate: monday)
            let isTheGenerators = try await saved == scene.generated(request, withIDsOf: saved)
            #expect(isTheGenerators, "the stored program is not the generator's default block")
            #expect(saved.isActive)
            #expect(saved.startDate == monday)
            let weeks = WeekCalendar(startDate: saved.startDate, weekStart: .monday, calendar: Fixtures.calendar)
            #expect(weeks.weekIndex(for: GateApp.wednesday) == 0)
            #expect(saved.weeks.map(\.isDeload) == [false, false, false, false, false, false, false, true])
            #expect(saved.goal == .both)
            #expect(saved.daysPerWeek == 4)
            let rows = try await [scene.rows("program_week"), scene.rows("day_template"), scene.rows("slot")]
            #expect(rows == [8, 4, 16])
        }

        @Test("Skip setup on step 1 saves the default program once and the root switches to the tabs on Today")
        func skipSetup_savesTheDefault_andShowsTheTabs() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await GateRootScene.run(app) { scene in
                #expect(scene.host.shown.labels == ["Continue", "Skip setup"])
                scene.tap("Skip setup")
                await app.journal.until("programs.save done")
                await gateObserved { scene.gate.destination == .main }
                let shown = scene.host.shown
                #expect(shown.isTabs, "\(shown)")
                #expect(scene.recorder.seen == [.onboarding, .main], "\(scene.recorder.seen)")
                try await Self.expectTheDefault(scene.theOneProgram(), in: scene)
                #expect(app.journal.count(of: "programs.save begins") == 1)
                #expect(app.journal.count(of: "launch began seedCatalog") == 1, "a first attempt prepares nothing")
            }
        }

        @Test("Continue, Continue, Start training saves the picks' program and the root switches to the tabs")
        func startTraining_savesAndShowsTheTabs() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await GateRootScene.run(app) { scene in
                scene.tap("Continue")
                scene.tap("Continue")
                #expect(scene.host.shown.labels == ["Start training", "Skip setup"])
                scene.tap("Start training")
                await app.journal.until("programs.save done")
                await gateObserved { scene.gate.destination == .main }
                #expect(scene.host.shown.isTabs)
                try await Self.expectTheDefault(scene.theOneProgram(), in: scene)
                #expect(!scene.host.activate("Start training"), "nothing of onboarding is left to tap")
                try await scene.expectRows("program", 1)
            }
        }

        @Test("A lifter in kilograms whose weeks start on Sunday gets that week and those loads through the real root")
        func kilogramsAndSundayWeeks_areTheStoredSettings() async throws {
            let app = GateApp()
            defer { app.remove() }
            var settings = LedgerDomain.Settings.default
            settings.units = .kg
            settings.weekStart = .sunday
            try await app.arrange { [settings] queue in try await GRDBSettingsRepository(queue).save(settings) }
            try await GateRootScene.run(app) { scene in
                scene.tap("Skip setup")
                await app.journal.until("programs.save done")
                await gateObserved { scene.gate.destination == .main }
                let saved = try await scene.theOneProgram()
                let sunday = try #require(CivilDate(year: 2026, month: 9, day: 13))
                let request = ProgramTemplates.Request(goal: .both, days: .four, units: .kg, startDate: sunday)
                let isTheGenerators = try await saved == scene.generated(request, withIDsOf: saved)
                #expect(isTheGenerators, "the stored program is not the generator's block in kilograms from Sunday")
                #expect(saved.startDate == sunday)
                let weeks = WeekCalendar(startDate: saved.startDate, weekStart: .sunday, calendar: Fixtures.calendar)
                #expect(weeks.weekIndex(for: GateApp.wednesday) == 0)
            }
        }
    }

    extension AppRootOnboardingAdversarialTests {
        @Test("Criterion 5: Retry runs the launch's seed step first, then saves, and the root switches to the tabs")
        func retry_runsTheSeedStep_thenSaves() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await Self.refuseSeeds(app)
            // Not in the foreground: the launch retries a failed seed there only when it is asked to, so a
            // second seed step can only be the one "Retry" asked for.
            try await GateRootScene.run(app, phase: .inactive) { scene in
                #expect(!scene.composition.isCatalogSeeded)
                scene.tap("Skip setup")
                await Self.catalogRead(1, in: app.journal)
                #expect(scene.host.shown.labels == Self.failed, "\(scene.host.shown)")
                #expect(app.journal.count(of: "launch began seedCatalog") == 1)
                try await scene.expectRows("program", 0)
                try await Self.allowSeeds(scene)

                let mark = app.journal.entries.count
                scene.tap("Retry")
                await Self.catalogRead(2, in: app.journal)
                let since = app.journal.entries.dropFirst(mark).filter { !$0.hasPrefix("sql ") }
                let seeded = try #require(
                    since.firstIndex(of: "launch began seedCatalog"),
                    "Retry did not run the launch's seed step: \(since)"
                )
                let read = try #require(since.firstIndex(of: "exercises.all begins"))
                #expect(seeded < read, "the seed step runs before the save reads the catalog: \(since)")
                #expect(scene.composition.isCatalogSeeded)
                await app.journal.until("programs.save done")
                await gateObserved { scene.gate.destination == .main }
                #expect(scene.host.shown.isTabs)
                try await Self.expectTheDefault(scene.theOneProgram(), in: scene)
            }
        }

        @Test("A seed that fails again leaves the failure with Retry and nothing saved; when it succeeds, Retry saves")
        func retry_seedFailsAgain_thenSucceeds() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await Self.refuseSeeds(app)
            try await GateRootScene.run(app, phase: .inactive) { scene in
                scene.tap("Continue")
                scene.tap("Continue")
                scene.tap("Start training")
                await Self.catalogRead(1, in: app.journal)
                for attempt in 2 ... 3 { // "Retry", then "Skip setup", which after a failure is a retry too
                    scene.tap(attempt == 2 ? "Retry" : "Skip setup")
                    await Self.catalogRead(attempt, in: app.journal)
                    #expect(app.journal.count(of: "launch began seedCatalog") == attempt)
                    #expect(app.journal.count(of: "launch failed seedCatalog") == attempt)
                    #expect(scene.host.shown.labels == Self.failed, "\(scene.host.shown)")
                    #expect(scene.gate.destination == .onboarding)
                }
                try await scene.expectRows("program", 0)
                #expect(app.journal.count(of: "programs.save begins") == 0)
                try await Self.allowSeeds(scene)
                scene.tap("Retry")
                await app.journal.until("programs.save done")
                await gateObserved { scene.gate.destination == .main }
                #expect(scene.host.shown.isTabs)
                #expect(scene.recorder.seen == [.onboarding, .main])
                try await Self.expectTheDefault(scene.theOneProgram(), in: scene)
            }
        }

        @Test("A retry while the launch's own pass is seeding waits for that same step, and then saves")
        func retry_whileTheLaunchIsSeeding() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await Self.refuseSeeds(app)
            try await GateRootScene.run(app, phase: .inactive) { scene in
                scene.tap("Skip setup")
                await Self.catalogRead(1, in: app.journal)
                try await Self.allowSeeds(scene)
                let hold = GateWriterHold(scene.stores.queue)
                scene.move(to: .active) // the lifter comes back: the launch retries the seed, which waits
                await app.journal.until("launch began seedCatalog", count: 2)
                scene.tap("Retry")
                // Lets the root's task reach the launch while its seed still waits. What follows holds in
                // either order: the step runs once, and the save comes after it.
                await Task.yield()
                await Task.yield()
                hold.free()
                await app.journal.until("programs.save done")
                #expect(app.journal.count(of: "launch began seedCatalog") == 2, "one step for both callers")
                #expect(app.journal.count(of: "launch failed seedCatalog") == 1)
                await gateObserved { scene.gate.destination == .main }
                #expect(scene.host.shown.isTabs)
                try await Self.expectTheDefault(scene.theOneProgram(), in: scene)
            }
        }
    }
#endif
