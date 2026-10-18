import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// The root's gate (F08 S3): which of loading, onboarding and the tabs it says, in the order it says them. Each
/// test follows a store as the root's task does and waits for the gate's own changes, so what a test sees
/// between two waits is what the root would draw between them.
@Suite("RootGate", .timeLimit(.minutes(1)))
struct RootGateTests {
    /// In-memory stores that hold the bundled catalog, so a program can be saved into them.
    static func seededStores() throws -> InMemoryStores {
        try InMemoryStores(seed: InMemoryStores.Seed(catalog: ExerciseCatalog.seed()))
    }

    @Test("A new gate has no answer, and a gate given no store keeps none")
    func noStore_staysLoading() async {
        let gate = RootGate()
        #expect(gate.destination == .loading)
        await gate.follow { nil }
        #expect(gate.destination == .loading)
    }

    @Test("Criterion 1: with no active program the first answer is onboarding")
    func noProgram_showsOnboarding() async {
        let programs = InMemoryProgramRepository()
        await RootGate.following(programs) { gate in
            #expect(await gate.answer() == .onboarding)
        }
    }

    @Test("Criterion 2: with an active program the first answer is the tabs, with no onboarding before it")
    func activeProgram_showsMain() async throws {
        let stores = try Self.seededStores()
        try await stores.programs.save(Fixtures.defaultProgram())
        await RootGate.following(stores.programs) { gate in
            #expect(gate.destination == .loading)
            #expect(await gate.answer() == .main)
        }
    }

    @Test("Criteria 3 and 4: saving a program flips to the tabs, deleting it flips back, and saving again flips again")
    func savingAProgram_flipsToMain() async throws {
        let stores = try Self.seededStores()
        let program = try Fixtures.defaultProgram()
        try await RootGate.following(stores.programs) { gate in
            #expect(await gate.answer() == .onboarding)

            try await stores.programs.save(program)
            #expect(await gate.change(from: .onboarding) == .main)

            try await stores.programs.delete(program.id)
            #expect(await gate.change(from: .main) == .onboarding)

            try await stores.programs.save(program)
            #expect(await gate.change(from: .onboarding) == .main)
        }
    }

    @Test(
        "Ruling O12: until the launch has returned the gate reads nothing and says nothing, then answers once",
        arguments: [false, true]
    )
    func untilTheLaunchReturns_staysLoading(hasProgram: Bool) async throws {
        let programs = try ScriptedPrograms(active: hasProgram ? Fixtures.defaultProgram() : nil)
        let launch = Latch()
        await RootGate.following(programs, after: launch) { gate in
            await launch.entered()
            #expect(gate.destination == .loading, "a slow first pass shows the ground colour")
            #expect(programs.observations == 0, "nothing is read before the launch has returned")

            launch.open()
            #expect(await gate.answer() == (hasProgram ? .main : .onboarding))
            #expect(programs.observations == 1, "criterion 9: one read decides")
        }
    }

    @Test("A program that cannot be read shows the tabs, never onboarding: before any answer, and after one")
    func streamThatEnds_showsMain() async {
        let unreadable = ScriptedPrograms()
        unreadable.fail()
        await RootGate.following(unreadable) { gate in
            #expect(await gate.answer() == .main)
        }

        let programs = ScriptedPrograms()
        await RootGate.following(programs) { gate in
            #expect(await gate.answer() == .onboarding)
            programs.fail()
            #expect(await gate.change(from: .onboarding) == .main)
        }
    }

    @Test("A follow cancelled before the launch returns leaves the gate loading and reads nothing")
    func cancelledBeforeTheLaunchReturns_staysLoading() async {
        let programs = ScriptedPrograms()
        let launch = Latch()
        let gate = RootGate()
        let follow = Task {
            await gate.follow {
                await launch.pass()
                return programs
            }
        }
        await launch.entered()
        follow.cancel()
        await follow.value
        #expect(gate.destination == .loading)
        #expect(programs.observations == 0)
    }

    @Test("A cancelled follow keeps what the gate said, and the next one never passes through loading")
    func cancelled_keepsItsDestination_untilTheNextAnswer() async throws {
        let programs = ScriptedPrograms()
        let gate = RootGate()
        let first = Task { await gate.follow { programs } }
        #expect(await gate.answer() == .onboarding)
        first.cancel()
        await first.value
        #expect(gate.destination == .onboarding, "a cancelled stream is not a program that cannot be read")

        // The scene's phase changed: the root starts the follow again, and the launch's pass runs first.
        let launch = Latch()
        let second = Task {
            await gate.follow {
                await launch.pass()
                return programs
            }
        }
        defer { second.cancel() }
        await launch.entered()
        #expect(gate.destination == .onboarding, "onboarding keeps its place while the gate reads again")
        try programs.set(Fixtures.defaultProgram())
        launch.open()
        #expect(await gate.change(from: .onboarding) == .main)
        #expect(programs.observations == 2, "each follow reads once")
    }

    @Test("A value the store gave just before the follow was cancelled is not applied (review S3-N1)")
    func valueGivenBeforeACancel_isNotApplied() async throws {
        let programs = ScriptedPrograms()
        let gate = RootGate()
        let follow = Task { await gate.follow { programs } }
        #expect(await gate.answer() == .onboarding)
        // No suspension between the two: the value is handed to the follow's task, which is then cancelled
        // before it runs again.
        try programs.set(Fixtures.defaultProgram())
        follow.cancel()
        await follow.value
        #expect(gate.destination == .onboarding, "a cancelled call changes nothing")
    }

    @Test("A read that failed is tried again by the next follow, which then shows what the store holds")
    func afterAFailedRead_theNextFollowReadsAgain() async {
        let programs = ScriptedPrograms()
        programs.fail()
        let gate = RootGate()
        await gate.follow { programs }
        #expect(gate.destination == .main, "the stream ended on a task nobody cancelled")

        programs.recover(active: nil)
        let next = Task { await gate.follow { programs } }
        defer { next.cancel() }
        #expect(await gate.change(from: .main) == .onboarding)
    }
}
