import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerTestSupport
import Observation
import Testing

/// F08 S2/S3 port, G2 (2026-10-18): the UI-test program seam (`-LEDGER_UITEST_PROGRAM seed`, criterion 20,
/// ruling R2) driven through the root's own call, `RootGate.follow(_:in:)`, as the app's `.task(id: scenePhase)`
/// drives it: a phase change that cancels the first pass at each of its steps, with the next pass started
/// before or after the cancelled one has returned (SwiftUI does not wait for it), and calls that overlap.
/// The implementer's `UITestProgramTests.cancelledCall_doesNotCount` calls the seam alone on a task that starts
/// cancelled; these go through the gate, whose first answer must already be the tabs.
@Suite("Adversarial F08 S2/S3 port · the UI test's program through the root's call", .timeLimit(.minutes(1)))
struct UITestProgramAdversarialTests {
    /// Holds the first pass's task, so the launch's event handler can cancel it at a step.
    @Observable
    final class FirstPass {
        var task: Task<Void, Never>?
        /// The launch's events seen while the first pass ran, and whether the step's event cancelled it.
        var events: [LaunchEvent] = []
        var isCancelledAtTheStep = false
        var isDone = false
    }

    /// The live programs on the composition's database: rows, not `active()`, so a second program shows.
    static func livePrograms(_ composition: AppComposition) async throws -> Int {
        try await #require(composition.stores).queue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM program WHERE deleted_at IS NULL") ?? -1
        }
    }

    @Test(
        "A phase change during the first pass: the gate shows the ground, then the tabs over one seed program",
        arguments: [LaunchStep.seedCatalog, .loadSettings, .activateCompanionSession], [false, true]
    )
    func phaseChange_duringTheFirstPass_opensOnTheTabs(at step: LaunchStep, awaitsTheCancelled: Bool) async throws {
        let harness = Harness("phaseChange\(step.rawValue)\(awaitsTheCancelled)")
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true)
        composition.boot()
        let gate = RootGate()
        let recorder = GateDestinationRecorder(gate)
        let first = FirstPass()
        harness.onEvent = { event in
            first.events.append(event)
            if event == .began(step), let task = first.task {
                task.cancel()
                first.isCancelledAtTheStep = true
            }
        }
        first.task = Task {
            await gate.follow(composition, in: .inactive)
            first.isDone = true
        }
        // Never an unbounded wait on the first pass: a pass that was not cancelled follows for ever.
        await until { first.isDone || gate.destination != .loading }
        #expect(first.isCancelledAtTheStep, "the step's event did not reach the first pass: \(first.events)")
        if awaitsTheCancelled {
            await until { first.isDone }
            #expect(gate.destination == .loading, "the cancelled pass decided something")
        }
        harness.onEvent = { _ in }
        // The new phase's call, as SwiftUI starts it once it has cancelled the old one.
        let second = Task { await gate.follow(composition, in: .active) }
        defer { second.cancel() }
        #expect(await gate.answer() == .main)
        first.task?.cancel()
        await first.task?.value
        #expect(recorder.seen == [.loading, .main], "onboarding flashed by, or the gate did not answer the tabs")
        #expect(try await Self.livePrograms(composition) == 1)
        let isTheSeed = try await #require(composition.stores).programs.active() == Fixtures.seedProgram()
        #expect(isTheSeed, "the active program is the spec's seed program")
    }

    @Test("Two calls that overlap, both before the one save has run, leave one program, the seed, active")
    func overlappingCalls_leaveOneProgram() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true)
        composition.boot()
        await composition.resume(in: .active)
        async let first: Void = composition.saveUITestProgramIfAsked()
        async let second: Void = composition.saveUITestProgramIfAsked()
        _ = await (first, second)
        #expect(try await Self.livePrograms(composition) == 1)
        #expect(try await composition.stores?.programs.active()?.id == Fixtures.seedProgram().id)

        // Neither call is left to count: a later pass saves nothing over a program the lifter (the test) removed.
        try await #require(composition.stores).programs.delete(Fixtures.seedProgram().id)
        await composition.saveUITestProgramIfAsked()
        #expect(try await Self.livePrograms(composition) == 0)
    }

    @Test("Two gates following one composition that asked (a second scene): one program, and each answers the tabs")
    func twoGates_oneComposition_oneProgram() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true)
        composition.boot()
        let gates = [RootGate(), RootGate()]
        let recorders = gates.map(GateDestinationRecorder.init)
        let calls = gates.map { gate in Task { await gate.follow(composition, in: .active) } }
        for gate in gates {
            #expect(await gate.answer() == .main)
        }
        #expect(recorders.map(\.seen) == [[.loading, .main], [.loading, .main]])
        #expect(try await Self.livePrograms(composition) == 1)
        for call in calls {
            call.cancel()
            await call.value
        }
    }

    @Test("The argument is read by position and once: the order beside -LEDGER_UITEST, and a repeat, as written")
    func arguments_readByPosition() throws {
        #expect(try UITestProgram.seeds(arguments: ["Ledger", "-LEDGER_UITEST_PROGRAM", "seed", "-LEDGER_UITEST"]))
        // The first occurrence decides; a second, malformed one is not read (pinned as the code reads it).
        #expect(try UITestProgram.seeds(arguments: [
            "Ledger", "-LEDGER_UITEST", "-LEDGER_UITEST_PROGRAM", "seed", "-LEDGER_UITEST_PROGRAM", "bogus"
        ]))
        // Another argument where the value belongs is refused, not taken for "no value".
        let misplaced = ["Ledger", "-LEDGER_UITEST", "-LEDGER_UITEST_PROGRAM", "-LEDGER_UITEST_NOW"]
        #expect(throws: UITestProgram.InvalidValue(value: "-LEDGER_UITEST_NOW")) {
            try UITestProgram.seeds(arguments: misplaced)
        }
        // A UI test's other launches never ask for it.
        #expect(try !UITestProgram.seeds(arguments: ["Ledger", "-LEDGER_UITEST", "-LEDGER_UITEST_NOW", "seed"]))
    }
}
