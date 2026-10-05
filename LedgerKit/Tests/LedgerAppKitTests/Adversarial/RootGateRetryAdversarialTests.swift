import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerTestSupport
import Testing

/// F08 S3 adversarial round 2 (G2), criterion 5 after the touch-up: "Retry" awaits `AppComposition.retrySeed()`,
/// which must run the seed step and nothing else of the launch, must return when the seed fails again, and must
/// be safe beside the launch's own pass. The call through the real root's "Retry" is
/// `AppRootOnboardingAdversarialTests`'.
@Suite("Adversarial F08 S3 · the call Retry makes", .timeLimit(.minutes(1)))
struct RootGateRetryAdversarialTests {
    /// What the launch noted since `mark`: its steps and the stand-ins' calls, without the database's statements.
    static func launchNotes(_ app: GateApp, since mark: Int) -> [String] {
        app.journal.entries.dropFirst(mark).filter { !$0.hasPrefix("sql ") }
    }

    static func dropTriggers(_ names: [String], in composition: AppComposition) async throws {
        let queue = try #require(composition.stores).queue
        try await queue.write { database in
            for name in names {
                try database.execute(sql: "DROP TRIGGER \(name)")
            }
        }
    }

    @Test(
        "After a pass whose seed failed, the call runs the seed step and nothing else, each time it is made",
        arguments: [false, true]
    )
    func retrySeed_runsTheSeedStepAlone(seedHeals: Bool) async throws {
        let app = GateApp("retrySeedAlone\(seedHeals)")
        defer { app.remove() }
        try await RootGateStoreAdversarialTests.arrange(app, .seedFails, hasProgram: false)
        let composition = app.booted()
        await composition.resume(in: .active)
        #expect(!composition.isCatalogSeeded)
        if seedHeals {
            try await Self.dropTriggers(["refuse_insert", "refuse_update"], in: composition)
        }
        let failing = ["launch began seedCatalog", "launch failed seedCatalog"]
        var mark = app.journal.entries.count
        await composition.retrySeed()
        #expect(Self.launchNotes(app, since: mark) == (seedHeals ? ["launch began seedCatalog"] : failing))
        #expect(composition.isCatalogSeeded == seedHeals)
        mark = app.journal.entries.count
        await composition.retrySeed()
        // Seeded, there is nothing left to run; still failing, a second tap on "Retry" asks again.
        #expect(Self.launchNotes(app, since: mark) == (seedHeals ? [] : failing))
        #expect(composition.state == .ready)
    }

    @Test("The call leaves a workout's recovery that failed to the launch: the next foreground runs it, not Retry")
    func retrySeed_leavesTheRecoveryToTheLaunch() async throws {
        let app = GateApp()
        defer { app.remove() }
        try await GateWorkouts.arrange(app, .finishedCannotBeSaved)
        let composition = app.booted()
        await composition.resume(in: .active)
        #expect(app.journal.count(of: "launch failed resumeWorkout") == 1)
        try await Self.dropTriggers(["refuse_workout"], in: composition)
        let mark = app.journal.entries.count
        await composition.retrySeed()
        await composition.retrySeed()
        #expect(Self.launchNotes(app, since: mark) == [], "Retry ran a step that is not the seed")
        let stores = try #require(composition.stores)
        #expect(try await stores.workouts.recent(limit: 5).isEmpty, "Retry saved the workout")
        await composition.resume(in: .active)
        #expect(Self.launchNotes(app, since: mark) == ["launch began resumeWorkout"])
        #expect(try await stores.workouts.recent(limit: 5).map(\.id) == [Fixtures.sessionID])
    }

    /// The launch's pass in the foreground, or the call "Retry" makes.
    static func call(_ isThePass: Bool, on composition: AppComposition) async {
        if isThePass {
            await composition.resume(in: .active)
        } else {
            await composition.retrySeed()
        }
    }

    /// Which of the two calls reaches the seed step first; the other arrives while it waits for the database.
    enum First: String, CaseIterable {
        case thePass, retry
    }

    @Test(
        "Retry's call beside the launch's pass, in either order, with the seed step waiting: the step runs once",
        arguments: First.allCases
    )
    func retrySeed_besideThePass_sharesTheSeedStep(_ first: First) async throws {
        let app = GateApp("besideThePass\(first.rawValue)")
        defer { app.remove() }
        let composition = app.booted()
        let hold = try GateWriterHold(#require(composition.stores).queue)
        let earlier = Task { await Self.call(first == .thePass, on: composition) }
        await app.journal.until("launch began seedCatalog") // the earlier call's seed waits for the database
        let later = Task { await Self.call(first != .thePass, on: composition) }
        // One turn for the later call to reach the step. What follows holds whichever of the two got there.
        await Task.yield()
        hold.free()
        await earlier.value
        await later.value
        await composition.resume(in: .active)
        #expect(composition.isCatalogSeeded)
        let notes = Self.launchNotes(app, since: 0)
        for step in ["seedCatalog", "loadSettings", "resumeWorkout", "activateCompanionSession"] {
            #expect(notes.count { $0 == "launch began \(step)" } == 1, "\(step): \(notes)")
        }
        #expect(!notes.contains { $0.hasPrefix("launch failed") }, "\(notes)")
    }
}
