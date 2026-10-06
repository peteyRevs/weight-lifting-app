import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1: "never lost, never doubled". `SiegeTrial` runs a seeded script of starts,
/// applies, finishes and discards on `LocalWorkoutSessionActor` while store calls are refused, lose their
/// answers or kill the process, the system clock moves, and the app is relaunched; the host is judged against
/// `WorkoutEngine.replay` of what its stores hold. A failing case names its seed and the steps before it.
@Suite("Adversarial F10 S2 · never lost, never doubled", .tags(.sync, .property), .timeLimit(.minutes(1)))
struct HostNeverLostAdversarialTests {
    @Test(
        "A seeded siege over the in-memory stores: the host follows its store",
        arguments: SessionLane.cut(SeamSeed.all, to: 20)
    )
    func siege_inMemoryStores_hostFollowsItsStore(seed: SeamSeed) async throws {
        let violation = try await SiegeTrial.violation(seed: seed.value, backing: .memory)
        #expect(violation == nil, "\(seed)")
    }

    @Test(
        "A seeded siege over the GRDB stores: the host follows its store",
        arguments: SessionLane.cut(SeamSeed.all.prefix(100), to: 6)
    )
    func siege_database_hostFollowsItsStore(seed: SeamSeed) async throws {
        let violation = try await SiegeTrial.violation(seed: seed.value, backing: .database)
        #expect(violation == nil, "\(seed)")
    }

    /// The siege's own teeth: over a store that loses an envelope, never saves or never compacts, no host can
    /// be right, and a siege must say so.
    @Test("A siege over a store that does not do what it says reports it", arguments: SiegeSabotage.allCases)
    func siege_sabotagedStore_isReported(sabotage: SiegeSabotage) async throws {
        var reported = 0
        for seed in SeamSeed.all.prefix(20) {
            let report = try await SiegeTrial.run(seed: seed.value, backing: .memory, sabotage: sabotage)
            reported += report.issue == nil ? 0 : 1
        }
        #expect(reported == 20, "\(sabotage) was reported by \(reported) of 20 sieges")
    }

    @Test("The sieges reach what they claim: faults that fire, workouts saved, logs dropped")
    func sieges_reachFaultsSavesAndDrops() async throws {
        var total = SiegeTrial.Report()
        for seed in SeamSeed.all.prefix(40) {
            let report = try await SiegeTrial.run(seed: seed.value, backing: .memory)
            total.faults += report.faults
            total.envelopes += report.envelopes
            total.saves += report.saves
            total.drops += report.drops
        }
        #expect(total.faults > 100, "\(total)")
        #expect(total.envelopes > 600, "\(total)")
        #expect(total.saves > 40, "\(total)")
        #expect(total.drops > 60, "\(total)")
    }
}
