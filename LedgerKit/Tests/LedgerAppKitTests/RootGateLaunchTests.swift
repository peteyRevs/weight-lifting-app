import Dependencies
@testable import FeatureOnboarding
import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import Testing

/// The gate over the real launch (F08 S3): a composition on a database file in a temporary directory, followed
/// by the call the root's task makes (`RootGate.follow(_:in:)`), with onboarding's own store saving into it.
@Suite("RootGate over the launch", .timeLimit(.minutes(1)))
struct RootGateLaunchTests {
    /// The step's events in `log`, spelled "began" and "failed", in order.
    static func events(of step: LaunchStep, in log: [Harness.Entry]) -> [String] {
        log.compactMap { entry in
            switch entry {
            case .event(.began(step)): "began"
            case .event(.failed(step)): "failed"
            default: nil
            }
        }
    }

    /// The row count of each table that a saved program writes.
    static func programRows(_ stores: LedgerStores?) throws -> [String: Int] {
        try #require(stores).queue.read { database in
            try ["program", "program_week", "day_template", "slot"].reduce(into: [:]) { rows, table in
                rows[table] = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)")
            }
        }
    }

    @Test("Criterion 1: a fresh database answers onboarding, and only once the launch's pass has seeded the catalog")
    func freshDatabase_showsOnboarding_afterTheLaunchsPass() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        let gate = RootGate()
        let follow = Task { await gate.follow(composition, in: .active) }
        defer { follow.cancel() }
        #expect(gate.destination == .loading)
        #expect(!composition.isCatalogSeeded, "the launch's pass has not run yet")

        #expect(await gate.answer() == .onboarding)
        #expect(composition.isCatalogSeeded, "the gate answered after the seed")
        #expect(Self.events(of: .loadSettings, in: harness.log) == ["began"], "and after the settings")
    }

    @Test("Criteria 3, 5 and 6: onboarding's Skip setup on the real database flips the gate, and the week is week 1")
    func skipSetup_onTheRealDatabase_flipsToMain() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        let gate = RootGate()
        let follow = Task { await gate.follow(composition, in: .active) }
        defer { follow.cancel() }
        #expect(await gate.answer() == .onboarding)

        // Wednesday 2026-09-16 (`Fixtures.now`), weeks starting Monday (the stored settings' default).
        await withTestDependencies { composition.bind(&$0) } operation: {
            let store = OnboardingStore()
            store.send(.skipSetup)
            await store.save(prepareRetry: {})
        }

        #expect(await gate.change(from: .onboarding) == .main)
        let saved = try #require(await composition.stores?.programs.active())
        #expect(saved.isActive)
        #expect(saved.goal == .both)
        #expect(saved.daysPerWeek == 4)
        #expect(saved.startDate == CivilDate(year: 2026, month: 9, day: 14))
        let weeks = WeekCalendar(startDate: saved.startDate, weekStart: .monday, calendar: Fixtures.calendar)
        #expect(weeks.weekIndex(for: Fixtures.now) == 0)
        #expect(try Self.programRows(composition.stores) == [
            "program": 1, "program_week": 8, "day_template": 4, "slot": 16
        ])
    }

    @Test("Criterion 4: the gate keeps following: a deleted program shows onboarding, a saved one the tabs")
    func deletedAndSavedAgain_isFollowed() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let (composition, gate) = try await harness.bootedWithAProgram()
        #expect(gate.destination == .main)
        let programs = try #require(composition.stores).programs
        let follow = Task { await gate.follow(composition, in: .active) }
        defer { follow.cancel() }

        try await programs.delete(Fixtures.defaultProgramID)
        #expect(await gate.change(from: .main) == .onboarding)

        try await programs.save(Fixtures.defaultProgram())
        #expect(await gate.change(from: .onboarding) == .main)
    }

    @Test("Criterion 2: a relaunch on a database that holds a program answers the tabs first, never onboarding")
    func relaunch_withAProgram_answersMainFirst() async throws {
        let harness = Harness()
        defer { harness.remove() }
        _ = try await harness.bootedWithAProgram()

        let relaunched = harness.booted()
        let gate = RootGate()
        let follow = Task { await gate.follow(relaunched, in: .active) }
        defer { follow.cancel() }
        #expect(gate.destination == .loading)
        #expect(await gate.answer() == .main)
    }

    @Test("Criterion 9: while the database is not open the gate reads nothing; once it opens, the same call follows it")
    func databaseNotOpen_staysLoading_untilItOpens() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let neverBooted = RootGate()
        await neverBooted.follow(harness.composition(), in: .active)
        #expect(neverBooted.destination == .loading, "a process hosting tests opens nothing")

        // Product decision #29: a directory where the file belongs cannot be opened.
        try FileManager.default.createDirectory(at: harness.databaseURL, withIntermediateDirectories: true)
        let composition = harness.booted()
        let gate = RootGate()
        await gate.follow(composition, in: .active)
        #expect(composition.state == .databaseUnavailable)
        #expect(gate.destination == .loading)

        // The lifter comes back and the file can be opened: the launch opens it, and the gate follows it.
        try FileManager.default.removeItem(at: harness.databaseURL)
        let follow = Task { await gate.follow(composition, in: .active) }
        defer { follow.cancel() }
        #expect(await gate.answer() == .onboarding)
        #expect(composition.state == .ready)
        #expect(composition.isCatalogSeeded)
    }

    @Test("Criterion 5: when the seed fails the gate still answers; Retry's call seeds again, and returns either way")
    func failedSeed_isRetriedByTheCallRetryMakes() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try harness.arrange { database in
            try database
                .execute(sql: "CREATE TRIGGER refuse BEFORE INSERT ON exercise BEGIN SELECT RAISE(ABORT, 'no'); END")
        }
        let composition = harness.booted()
        let gate = RootGate()
        let follow = Task { await gate.follow(composition, in: .active) }
        defer { follow.cancel() }
        #expect(await gate.answer() == .onboarding, "a failed seed does not hold the root on the ground colour")
        #expect(!composition.isCatalogSeeded)
        #expect(Self.events(of: .seedCatalog, in: harness.log) == ["began", "failed"])

        // What `MainRoot` passes to onboarding as `prepareRetry`: the launch's seed step again.
        await composition.retrySeed()
        #expect(!composition.isCatalogSeeded, "it returned although the seed failed again")
        #expect(Self.events(of: .seedCatalog, in: harness.log) == ["began", "failed", "began", "failed"])
        #expect(gate.destination == .onboarding)

        try await #require(composition.stores).queue.write { try $0.execute(sql: "DROP TRIGGER refuse") }
        await composition.retrySeed()
        #expect(composition.isCatalogSeeded, "Retry's call ran the seed step again")
        #expect(Self.events(of: .loadSettings, in: harness.log) == ["began"], "and nothing that had succeeded")
        #expect(Self.events(of: .resumeWorkout, in: harness.log) == ["began"], "nor the workout's recovery")
        await composition.retrySeed()
        #expect(
            Self.events(of: .seedCatalog, in: harness.log) == ["began", "failed", "began", "failed", "began"],
            "seeded: a further call runs nothing"
        )

        try await #require(composition.stores).programs.save(Fixtures.defaultProgram())
        #expect(await gate.change(from: .onboarding) == .main)
    }
}

/// The launch's pass with the live workout's recovery in it (F10 S2; review S3-SF2): the gate still answers
/// only when the whole pass has returned, and onboarding's "Retry" runs none of the recovery.
extension RootGateLaunchTests {
    @Test("Review SF2: with a workout to resume, the ground holds through its recovery, and the gate then answers")
    func liveWorkout_isRecoveredBeforeTheGateAnswers() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let first = try await WorkoutRelaunchTests.Launch(harness)
        let live = try await first.logTheFirstExercise(of: first.startUpperA())

        let relaunched = harness.booted()
        harness.clearLog()
        let gate = RootGate()
        // What the gate said as each step of the pass began: the recovery, then the step that follows it.
        var saidMeanwhile: [LaunchStep: RootGate.Destination] = [:]
        harness.onEvent = { event in
            if case let .began(step) = event {
                saidMeanwhile[step] = gate.destination
            }
        }
        let follow = Task { await gate.follow(relaunched, in: .active) }
        defer { follow.cancel() }
        #expect(await gate.answer() == .main)
        #expect(saidMeanwhile[.resumeWorkout] == .loading, "the recovery began under the ground colour")
        #expect(saidMeanwhile[.activateCompanionSession] == .loading, "and had ended before the gate answered")
        #expect(Self.events(of: .resumeWorkout, in: harness.log) == ["began"])
        #expect(try await relaunched.session?.current() == live, "the workout is live again")
    }

    @Test("Review SF2: Retry's call leaves the workout's recovery alone, which the launch's own pass runs again")
    func retrySeed_leavesTheWorkoutsRecoveryToTheLaunch() async throws {
        let harness = Harness()
        defer { harness.remove() }
        // A finished workout whose save a trigger refuses: its recovery has work left, launch after launch.
        let first = try await WorkoutRelaunchTests.Launch(harness)
        _ = try await first.logTheFirstExercise(of: first.startUpperA())
        try await first.refuse(WorkoutRelaunchTests.refuseSave)
        await #expect(throws: DatabaseError.self) {
            _ = try await first.session.finish(endedAt: Harness.now.addingTimeInterval(3600))
        }

        let relaunched = harness.booted()
        harness.clearLog()
        await relaunched.resume(in: .active)
        #expect(Self.events(of: .resumeWorkout, in: harness.log) == ["began", "failed"])

        await relaunched.retrySeed()
        #expect(Self.events(of: .resumeWorkout, in: harness.log) == ["began", "failed"], "Retry ran no recovery")
        #expect(Self.events(of: .seedCatalog, in: harness.log) == ["began"], "and no seed: the catalog is seeded")

        // Control: the wider call, which Retry made before, runs the failed recovery again.
        await relaunched.resume(in: .active)
        #expect(Self.events(of: .resumeWorkout, in: harness.log) == ["began", "failed", "began", "failed"])
    }
}
