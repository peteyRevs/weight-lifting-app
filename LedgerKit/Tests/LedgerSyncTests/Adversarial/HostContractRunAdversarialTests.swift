import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 1: "The host keeps every clause and every seeded script of
/// `WorkoutSessionClientContract`: over in-memory stores, over the GRDB stores, and over stores that suspend
/// inside every call; and also when its recovery has not been started." The gate runs those three kinds of
/// store; here the two that suspend are this suite's own wrappers, over the fakes and over GRDB, and the
/// host is never told to recover.
@Suite("Adversarial F10 S2 · the contract over this suite's stores", .tags(.sync, .property), .timeLimit(.minutes(1)))
struct HostContractRunAdversarialTests {
    typealias Contract = WorkoutSessionClientContract
    typealias Backing = SiegeRig.Backing

    static func host(_ backing: Backing) async throws -> LocalWorkoutSessionActor {
        try await SiegeRig.make(backing, yields: 2).host()
    }

    @Test("Every clause holds over stores that give way inside every call", arguments: Backing.allCases)
    func clauses_overStoresThatGiveWay_hold(backing: Backing) async {
        let violations = await Contract.violations { try await Self.host(backing) }
        #expect(violations == [])
    }

    @Test(
        "The sequential and the concurrent script hold over stores that give way inside every call",
        arguments: Backing.allCases,
        HostContractBiteAdversarialTests.gateSeeds + HostContractBiteAdversarialTests.moreSeeds
    )
    func scripts_overStoresThatGiveWay_hold(backing: Backing, seed: UInt64) async throws {
        #expect(try await Contract.scriptViolation(seed: seed, on: Self.host(backing)) == nil)
        #expect(try await Contract.concurrentScriptViolation(seed: seed, on: Self.host(backing)) == nil)
    }

    @Test(
        "The S1 differential script holds on the host, whose events the stores can keep or not",
        arguments: SeamSeed.all.prefix(40)
    )
    func differential_onTheHost_answersAsTheEngineUntilAnEnd(seed: SeamSeed) async throws {
        // The S1 script logs weights no store can save (an eighth of a pound, a negative one), so the host
        // is compared with the oracle up to the first call the two may differ on: a finish of such a workout.
        let host = try await Self.host(.memory)
        var writer = SeamScriptWriter(seed: seed.value)
        var oracle = SeamOracle()
        for step in 0 ..< 60 {
            let call = writer.next(live: oracle.live)
            let expected = oracle.perform(call).outcome
            let actual = await Seam.outcome(of: call, on: host)
            if case .threw = actual, call.event.isTerminal {
                return
            }
            #expect(actual == expected, "\(seed) step \(step) \(call)")
            #expect(try await host.current() == oracle.live, "\(seed) step \(step) \(call)")
        }
    }
}
