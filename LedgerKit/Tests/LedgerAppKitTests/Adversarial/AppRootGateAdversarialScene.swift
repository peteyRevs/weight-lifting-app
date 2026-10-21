#if os(iOS)
    import Foundation
    import GRDB
    @testable import LedgerAppKit
    import LedgerDomain
    import LedgerPersistence
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// A booted app with its real root hosted in a window: the composition over a database file, the gate the
    /// root draws, every destination the gate held, and the probes' journal. Onboarding's store, which the root
    /// makes, reads the composition's real stores through the probes.
    ///
    /// **The rule of these hosted suites (round 2, finding F8-S3-4): no root is alive while its gate can move
    /// to onboarding.** Onboarding's store keeps the dependencies of the task that makes it. A root whose gate
    /// moves to onboarding while the test is suspended draws onboarding in SwiftUI's own update, in no task:
    /// the store is then made outside the test's scope, and swift-dependencies records a warning that belongs
    /// to no test, which fails the bundle. Neither a wait that gives up its turn nor taking the root out of
    /// its window prevents it (both measured). So a root is hosted over a gate that has already answered
    /// onboarding, where its first layout is the test's, or over a store that holds a program, where the
    /// root's own task can only move it to the tabs. A return to onboarding is a new root over a new gate
    /// (`GateShell`).
    final class GateRootScene {
        let app: GateApp
        let composition: AppComposition
        let stores: LedgerStores
        let gate: RootGate
        let recorder: GateDestinationRecorder
        let host: GateHost
        let hold: GateSaveHold

        private init(
            _ app: GateApp,
            _ composition: AppComposition,
            _ gate: RootGate,
            _ hold: GateSaveHold,
            _ phase: ScenePhase
        ) throws {
            self.app = app
            self.composition = composition
            stores = try #require(composition.stores)
            self.gate = gate
            self.hold = hold
            recorder = GateDestinationRecorder(gate)
            host = GateHost(AppRoot(standingIn: composition, gate: gate), phase: phase)
        }

        /// Boots `app` and hosts its root in `phase` for as long as `body` runs. With `isAnswered` the gate has
        /// followed the launch's first pass before the root is hosted, so the root's first layout draws its
        /// screen; without, the root is hosted with a new gate, as the app hosts it.
        static func run(
            _ app: GateApp,
            phase: ScenePhase = .active,
            isAnswered: Bool = true,
            _ body: (GateRootScene) async throws -> Void
        ) async throws {
            let booted = app.booted()
            let answer = isAnswered ? await GateAnswers.followed(booted, in: phase) : RootGate()
            let saveHold = GateSaveHold()
            try await withGateDependencies(booted, app.journal, hold: saveHold) {
                let scene = try GateRootScene(app, booted, answer, saveHold, phase)
                defer { scene.host.close() }
                try await body(scene)
            }
        }

        /// Makes the next save wait, and returns what lets it go.
        func holdNextSave() -> GateWaiter {
            let waiter = GateWaiter()
            hold.waiter = waiter
            return waiter
        }

        /// A double tap on the pinned button VoiceOver reads as `label`.
        func tap(_ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
            let before = host.shown
            #expect(host.activate(label), "no enabled \"\(label)\" in \(before)", sourceLocation: sourceLocation)
        }

        /// Expects onboarding's stores to have read the settings through the probe `count` times: once when
        /// each onboarding screen appeared and once for each save. A read that ran outside the test's
        /// dependency scope never reaches the probe.
        func expectSettingsReads(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) {
            let reads = app.journal.count(of: "settings.load begins")
            #expect(reads == count, "settings reads through the probe", sourceLocation: sourceLocation)
        }

        /// Changes the scene's phase, as the system does, and lets SwiftUI apply it.
        func move(to phase: ScenePhase) {
            host.scene.phase = phase
            host.settle()
        }

        /// How many live rows `table` holds.
        func rows(_ table: String) async throws -> Int {
            try await stores.queue.read { database in
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table) WHERE deleted_at IS NULL") ?? -1
            }
        }

        /// Expects `table` to hold `count` live rows.
        func expectRows(_ table: String, _ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async throws {
            let stored = try await rows(table)
            #expect(stored == count, "live rows of \(table)", sourceLocation: sourceLocation)
        }

        /// The one stored program, which must be the active one.
        func theOneProgram(sourceLocation: SourceLocation = #_sourceLocation) async throws -> Program {
            try await expectRows("program", 1, sourceLocation: sourceLocation)
            return try #require(try await stores.programs.active(), "no active program", sourceLocation: sourceLocation)
        }

        /// The block the Domain's generator writes for the request over the stored catalog, with `saved`'s ids
        /// in the order the generator draws them: the weeks, then each day followed by its slots.
        func generated(_ request: ProgramTemplates.Request, withIDsOf saved: Program) async throws -> Program {
            var ids = (saved.weeks.map(\.id.rawValue)
                + saved.days.flatMap { [$0.id.rawValue] + $0.slots.map(\.id.rawValue) }).makeIterator()
            return try await ProgramTemplates.program(
                request,
                catalog: stores.exercises.all(),
                id: saved.id,
                newID: { ids.next() ?? UUID() }
            )
        }
    }
#endif
