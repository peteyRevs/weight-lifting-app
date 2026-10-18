import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2/S3 criterion 20 (ruling R2): a UI test's program, `-LEDGER_UITEST_PROGRAM seed` beside
/// `-LEDGER_UITEST`, read as `UITestSaveFailures` reads its argument, and saved by the root's launch call after
/// the launch's pass and before the gate's first read.
@Suite("UITestProgram", .timeLimit(.minutes(1)))
struct UITestProgramTests {
    @Test("The seed program is asked for beside -LEDGER_UITEST, and only there")
    func seeds_isReadOnlyForAUITest() throws {
        #expect(try UITestProgram.seeds(arguments: ["Ledger", "-LEDGER_UITEST", "-LEDGER_UITEST_PROGRAM", "seed"]))
        #expect(try !UITestProgram.seeds(arguments: ["Ledger", "-LEDGER_UITEST"]))
        #expect(try !UITestProgram.seeds(arguments: ["Ledger", "-LEDGER_UITEST_PROGRAM", "seed"]))
        #expect(try !UITestProgram.seeds(arguments: ["Ledger"]))
    }

    @Test("A value that is missing or is not seed is refused", arguments: [nil, "", "Seed", "default", "1"])
    func seeds_refusesAnyOtherValue(value: String?) {
        let arguments = ["Ledger", "-LEDGER_UITEST", "-LEDGER_UITEST_PROGRAM"] + [value].compactMap(\.self)
        #expect(throws: UITestProgram.InvalidValue(value: value)) {
            try UITestProgram.seeds(arguments: arguments)
        }
    }

    @Test("Asked for, the gate's first answer is the tabs, over the seed program, active and saved once")
    func asked_theGateOpensOnTheTabs() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true)
        composition.boot()
        let gate = RootGate()
        let follow = Task { await gate.follow(composition, in: .active) }
        defer { follow.cancel() }
        #expect(await gate.answer() == .main)

        let programs = try #require(composition.stores).programs
        let seed = try Fixtures.seedProgram()
        let active = try #require(try await programs.active())
        let isTheSeed = active == seed
        #expect(isTheSeed, "the active program is the spec's seed program")

        // The program goes away; the launch call of a later pass (a return to the foreground) saves it no more.
        try await programs.delete(seed.id)
        #expect(await gate.change(from: .main) == .onboarding)
        await composition.saveUITestProgramIfAsked()
        #expect(try await programs.active() == nil, "the seed program is saved once in a process")
    }

    /// The root's first launch call is cancelled when the scene's phase changes during the first pass (the
    /// `Smoke` run that found it opened on onboarding): that call must not use up the one save.
    @Test("A call whose task is cancelled saves nothing and does not count: the next call saves the seed program")
    func cancelledCall_doesNotCount() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true)
        composition.boot()
        await composition.resume(in: .active)
        let programs = try #require(composition.stores).programs
        // Made on the main actor and cancelled before this test suspends, so it starts cancelled.
        let cancelled = Task { await composition.saveUITestProgramIfAsked() }
        cancelled.cancel()
        await cancelled.value
        #expect(try await programs.active() == nil, "control: the cancelled call saved nothing")
        await composition.saveUITestProgramIfAsked()
        #expect(try await programs.active()?.id == Fixtures.seedProgram().id)
    }

    @Test("Asked for over a database that has an active program, nothing is saved and that program stays")
    func asked_withAProgram_savesNothing() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true)
        composition.boot()
        await composition.resume(in: .active)
        let programs = try #require(composition.stores).programs
        try await programs.save(Fixtures.defaultProgram())
        #expect(await harness.gate(following: composition).destination == .main)
        #expect(try await programs.active()?.id == Fixtures.defaultProgramID)
    }

    @Test("Not asked for, a fresh database opens on onboarding")
    func notAsked_theGateOpensOnOnboarding() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        #expect(await harness.gate(following: composition).destination == .onboarding)
        #expect(try await #require(composition.stores).programs.active() == nil)
    }
}
