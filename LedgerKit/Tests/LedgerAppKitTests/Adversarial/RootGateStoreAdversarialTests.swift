import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import SwiftUI
import Testing

/// F08 S3 adversarial round 1 (G2), criteria 1, 2, 8 (revised) and 9: the gate as the app wires it,
/// `follow(_:in:)` over the real launch and the real database file, with every destination it ever held recorded
/// and every statement the database ran noted in order.
@Suite("Adversarial F08 S3 · the gate over the real launch", .timeLimit(.minutes(1)))
struct RootGateStoreAdversarialTests {
    /// What a launch's first pass meets.
    enum Pass: String, CaseIterable {
        case plain, slow, seedFails
    }

    nonisolated static let refuseSeed = """
    CREATE TRIGGER refuse_insert BEFORE INSERT ON exercise BEGIN SELECT RAISE(ABORT, 'no'); END;
    CREATE TRIGGER refuse_update BEFORE UPDATE ON exercise BEGIN SELECT RAISE(ABORT, 'no'); END;
    """

    /// Arranges the file for `pass`, with a program stored or not. A seed that fails with a program stored is a
    /// catalog upgrade that fails: the stored catalog is marked as an older version, and then refuses writes.
    static func arrange(_ app: GateApp, _ pass: Pass, hasProgram: Bool) async throws {
        try await app.arrange { queue in
            if hasProgram {
                try await GatePrograms.store([GatePrograms.make()], in: queue)
            }
            if pass == .seedFails {
                try await queue.write { database in
                    try database.execute(sql: "UPDATE exercise SET catalog_version = 0")
                    try database.execute(sql: refuseSeed)
                }
            }
        }
    }

    @Test(
        "For each first pass, with and without a program: nothing until the pass returns, then the one right screen",
        arguments: Pass.allCases,
        [false, true]
    )
    func firstPass_showsNothingThenTheRightScreen(_ pass: Pass, hasProgram: Bool) async throws {
        let app = GateApp("firstPass\(pass.rawValue)\(hasProgram)")
        defer { app.remove() }
        try await Self.arrange(app, pass, hasProgram: hasProgram)
        let composition = app.booted()
        let gate = RootGate()
        let recorder = GateDestinationRecorder(gate)
        let hold = try pass == .slow ? GateWriterHold(#require(composition.stores).queue) : nil
        let call = Task { await gate.follow(composition, in: .active) }
        if let hold {
            await app.journal.until("launch began seedCatalog")
            #expect(gate.destination == .loading, "the pass is running")
            #expect(app.journal.firstProgramStatement == nil, "a store was read while the pass ran")
            hold.free()
        }
        await gateObserved { gate.destination != .loading }
        let expected = hasProgram ? RootGate.Destination.main : .onboarding
        #expect(recorder.seen == [.loading, expected], "\(recorder.seen)")
        #expect(composition.isCatalogSeeded == (pass != .seedFails))
        #expect(app.journal.count(of: "launch failed seedCatalog") == (pass == .seedFails ? 1 : 0))
        Self.expectOneReadAfterThePass(app.journal)
        call.cancel()
        await call.value
        #expect(recorder.seen == [.loading, expected], "a cancelled call changed the gate: \(recorder.seen)")
    }

    /// Criterion 9: one read of the active program, and no statement on a program table before the launch's
    /// last step (the settings) began.
    static func expectOneReadAfterThePass(_ journal: GateJournal, sourceLocation: SourceLocation = #_sourceLocation) {
        let entries = journal.entries
        #expect(journal.activeProgramReads.count == 1, "\(journal.activeProgramReads)", sourceLocation: sourceLocation)
        let settings = entries.firstIndex(of: "launch began loadSettings") ?? Int.max
        let firstRead = journal.firstProgramStatement ?? -1
        #expect(
            settings < firstRead,
            "settings began at \(settings), first read at \(firstRead)",
            sourceLocation: sourceLocation
        )
    }

    @Test(
        "A composition that never booted is asked nothing and decides nothing",
        arguments: [ScenePhase.active, .background]
    )
    func idle_decidesNothing(_ phase: ScenePhase) async {
        let app = GateApp("idle\(phase)")
        defer { app.remove() }
        let composition = app.composition()
        let gate = RootGate()
        await gate.follow(composition, in: phase)
        #expect(gate.destination == .loading)
        #expect(composition.state == .idle)
        #expect(app.journal.entries.isEmpty, "\(app.journal.entries)")
        #expect(!FileManager.default.fileExists(atPath: app.directory.path(percentEncoded: false)))
    }

    @Test("A database that cannot open decides nothing; once it opens on a later foreground the gate follows it")
    func databaseUnavailable_decidesNothing_thenFollows() async throws {
        let app = GateApp()
        defer { app.remove() }
        try FileManager.default.createDirectory(at: app.databaseURL, withIntermediateDirectories: true)
        let composition = app.composition()
        composition.boot()
        let gate = RootGate()
        let recorder = GateDestinationRecorder(gate)
        for phase in [ScenePhase.active, .background, .active] {
            await gate.follow(composition, in: phase) // returns: there is no store to follow
            #expect(composition.state == .databaseUnavailable)
            #expect(gate.destination == .loading)
        }
        try FileManager.default.removeItem(at: app.databaseURL)
        let call = Task { await gate.follow(composition, in: .active) }
        await gateObserved { gate.destination != .loading }
        #expect(composition.state == .ready)
        #expect(recorder.seen == [.loading, .onboarding])
        call.cancel()
        await call.value
    }
}

extension RootGateStoreAdversarialTests {
    @Test("A first pass in the background decides too: a workout can launch the app there")
    func backgroundFirstPass_decides() async {
        let app = GateApp()
        defer { app.remove() }
        let composition = app.booted()
        let gate = RootGate()
        let call = Task { await gate.follow(composition, in: .background) }
        await gateObserved { gate.destination != .loading }
        #expect(gate.destination == .onboarding)
        #expect(composition.isCatalogSeeded)
        call.cancel()
        await call.value
    }

    @Test(
        "Criterion 8: a second boot on the file a program was saved to shows nothing, then the tabs, never onboarding"
    )
    func relaunch_onTheSameFile_showsTheTabs() async throws {
        let app = GateApp()
        defer { app.remove() }
        let first = app.booted()
        let firstGate = RootGate()
        let firstCall = Task { await firstGate.follow(first, in: .active) }
        await gateObserved { firstGate.destination == .onboarding }
        try await #require(first.stores).programs.save(GatePrograms.make())
        await gateObserved { firstGate.destination == .main }
        firstCall.cancel()
        await firstCall.value
        try #require(first.stores).queue.close() // the process ends

        let mark = app.journal.entries.count
        let second = app.booted()
        let gate = RootGate()
        let recorder = GateDestinationRecorder(gate)
        #expect(gate.destination == .loading)
        let call = Task { await gate.follow(second, in: .active) }
        await gateObserved { gate.destination != .loading }
        #expect(recorder.seen == [.loading, .main], "\(recorder.seen)")
        let sinceRelaunch = app.journal.entries.dropFirst(mark)
        #expect(sinceRelaunch.count { $0.contains("FROM program WHERE is_active = 1") } == 1)
        call.cancel()
        await call.value
    }

    @Test("Audit of the sanctioned edits: their helper hands F09's two root tests a gate that shows the tabs")
    func sanctionedHelper_handsOverAGateOnTheTabs() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let (composition, gate) = try await harness.bootedWithAProgram()
        #expect(composition.state == .ready)
        #expect(gate.destination == .main, "root_ready_draws would draw \(gate.destination), not the shell")
        let active = try await composition.stores?.programs.active()
        #expect(active?.isActive == true)
    }

    /// The states the launch can be in when a lifter taps "Retry".
    enum Launch: String, CaseIterable {
        case idle, unavailable, seedFails, ready
    }

    /// `MainRoot` hands onboarding `composition.resume(in: .active)` as `prepareRetry`, which must return: while
    /// it runs, onboarding offers no way out. A call that never returned would end this test at the suite's
    /// time limit.
    @Test(
        "Criterion 5: the call Retry is wired to returns in every state of the launch, also to a cancelled caller",
        arguments: Launch.allCases
    )
    func retrysCall_alwaysReturns(_ launch: Launch) async throws {
        let app = GateApp("retrysCall\(launch.rawValue)")
        defer { app.remove() }
        if launch == .unavailable {
            try FileManager.default.createDirectory(at: app.databaseURL, withIntermediateDirectories: true)
        }
        if launch == .seedFails {
            try await Self.arrange(app, .seedFails, hasProgram: false)
        }
        let composition = app.composition()
        if launch != .idle {
            composition.boot()
        }
        for _ in 0 ..< 3 {
            await composition.resume(in: .active)
        }
        let cancelled = Task { await composition.resume(in: .active) }
        cancelled.cancel()
        await cancelled.value
        async let first: Void = composition.resume(in: .active)
        async let second: Void = composition.resume(in: .active)
        _ = await (first, second)
        let expected: [Launch: AppComposition.State] = [
            .idle: .idle, .unavailable: .databaseUnavailable, .seedFails: .ready, .ready: .ready
        ]
        #expect(composition.state == expected[launch])
        #expect(composition.isCatalogSeeded == (launch == .ready))
    }

    @Test("Two roots over one composition each decide, and the launch's steps still run once")
    func twoGates_oneComposition() async throws {
        let app = GateApp()
        defer { app.remove() }
        let composition = app.booted()
        let gates = [RootGate(), RootGate()]
        let recorders = gates.map(GateDestinationRecorder.init)
        let calls = gates.map { gate in Task { await gate.follow(composition, in: .active) } }
        await gateObserved { gates.allSatisfy { $0.destination == .onboarding } }
        #expect(app.journal.count(of: "launch began seedCatalog") == 1)
        #expect(app.journal.count(of: "launch began loadSettings") == 1)
        try await #require(composition.stores).programs.save(GatePrograms.make())
        await gateObserved { gates.allSatisfy { $0.destination == .main } }
        #expect(recorders.map(\.seen) == [[.loading, .onboarding, .main], [.loading, .onboarding, .main]])
        for call in calls {
            call.cancel()
            await call.value
        }
    }
}
