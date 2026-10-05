import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import Testing

/// What an app that died mid-workout left in its database (F10): the launch's pass recovers it before the gate
/// decides (the merge of `main` into F08 S3 put the recovery in the pass).
enum GateWorkouts {
    /// What the kill left.
    enum Left: String, CaseIterable, Sendable {
        /// A workout that was running: the recovery resumes it.
        case liveWorkout
        /// A workout whose end is in its log and which was not saved: the recovery saves it.
        case finishedUnsaved
        /// The same, on a database that still refuses the save: the recovery fails.
        case finishedCannotBeSaved
    }

    nonisolated static let refuseWorkouts =
        "CREATE TRIGGER refuse_workout BEFORE INSERT ON workout BEGIN SELECT RAISE(ABORT, 'no'); END"

    /// Arranges `app`'s file as a launch, a lifter with the seed program and a workout begun on Wednesday left it.
    static func arrange(_ app: GateApp, _ left: Left) async throws {
        let stores = try LedgerStores.open(
            at: app.databaseURL,
            kind: .phone,
            now: { GateApp.wednesday },
            newID: { GateApp.deviceUUID }
        )
        try await stores.seedCatalog()
        try await stores.programs.save(Fixtures.seedProgram())
        let host = LocalWorkoutSessionActor(
            events: stores.events,
            workouts: stores.workouts,
            programs: stores.programs,
            device: stores.deviceID,
            now: { GateApp.wednesday }
        )
        try await host.start(Fixtures.seedSession())
        if left != .liveWorkout {
            try await stores.queue.write { try $0.execute(sql: refuseWorkouts) }
            // The end reaches the log and the save is refused, as when the app dies between the two: the
            // failure is the arrangement.
            _ = try? await host.finish(endedAt: GateApp.wednesday.addingTimeInterval(600))
            if left == .finishedUnsaved {
                try await stores.queue.write { try $0.execute(sql: "DROP TRIGGER refuse_workout") }
            }
        }
        try stores.queue.close()
    }
}

/// F08 S3 adversarial round 2 (G2), criteria 1 and 2 with F10's recovery in the launch's pass: the gate, and
/// so the root, shows nothing at any step of the pass, the recovery included, also when the recovery fails.
@Suite("Adversarial F08 S3 · the gate and the workout's recovery", .timeLimit(.minutes(1)))
struct RootGateRecoveryAdversarialTests {
    typealias Left = GateWorkouts.Left

    @Test(
        "With a workout left by a kill, the gate shows nothing at each step of the pass, then the tabs",
        arguments: Left.allCases
    )
    func workoutLeft_theGateWaitsForTheRecovery(_ left: Left) async throws {
        let app = GateApp("workoutLeft\(left.rawValue)")
        defer { app.remove() }
        try await GateWorkouts.arrange(app, left)
        let composition = app.booted()
        let gate = RootGate()
        let recorder = GateDestinationRecorder(gate)
        var shownAtEachStep: [String] = []
        app.onEvent = { event in shownAtEachStep.append("\(GateApp.name(event)): \(gate.destination)") }
        let call = Task { await gate.follow(composition, in: .active) }
        await gateObserved { gate.destination != .loading }
        app.onEvent = nil
        let failure = left == .finishedCannotBeSaved ? ["failed resumeWorkout"] : []
        let steps = ["began seedCatalog", "began loadSettings", "began resumeWorkout"] + failure
            + ["began activateCompanionSession"]
        #expect(shownAtEachStep == steps.map { "\($0): loading" })
        #expect(recorder.seen == [.loading, .main], "\(recorder.seen)")
        call.cancel()
        await call.value

        // What the recovery did, so that the pass above is known to have had the work to do.
        let stores = try #require(composition.stores)
        let stored = try await stores.workouts.recent(limit: 5).map(\.id)
        let logs = try await stores.events.uncompactedWorkoutIDs()
        let needsRecovery = try await #require(composition.session).needsRecovery
        switch left {
        case .liveWorkout:
            let live = try await composition.session?.current()?.id
            #expect(live == Fixtures.sessionID)
            #expect(stored.isEmpty && logs == [Fixtures.sessionID] && !needsRecovery)
        case .finishedUnsaved:
            #expect(stored == [Fixtures.sessionID] && logs.isEmpty && !needsRecovery)
        case .finishedCannotBeSaved:
            #expect(stored.isEmpty && logs == [Fixtures.sessionID] && needsRecovery)
        }
    }

    @Test("A recovery that failed does not hold later calls on the ground; the next foreground runs it again")
    func recoveryThatFailed_isTheLaunchsToRetry() async throws {
        let app = GateApp()
        defer { app.remove() }
        try await GateWorkouts.arrange(app, .finishedCannotBeSaved)
        let composition = app.booted()
        let gate = RootGate()
        let recorder = GateDestinationRecorder(gate)
        await GateAnswers.answer(gate, from: composition)
        #expect(app.journal.count(of: "launch failed resumeWorkout") == 1)
        try await #require(composition.stores).queue.write { try $0.execute(sql: "DROP TRIGGER refuse_workout") }
        await composition.resume(in: .background) // not the foreground: nothing is retried
        #expect(app.journal.count(of: "launch began resumeWorkout") == 1)
        await composition.resume(in: .active)
        #expect(app.journal.count(of: "launch began resumeWorkout") == 2)
        #expect(app.journal.count(of: "launch failed resumeWorkout") == 1)
        let stored = try await #require(composition.stores).workouts.recent(limit: 5).map(\.id)
        #expect(stored == [Fixtures.sessionID])
        #expect(recorder.seen == [.loading, .main], "\(recorder.seen)")
    }
}
