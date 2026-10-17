import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criterion 1: the host keeps every clause and every seeded script of `WorkoutSessionClientContract`,
/// the ones `FakeWorkoutSessionClient` keeps, over each kind of store, and whether the launch ran its recovery
/// or the first protocol call has to. Both are held to the engine, so the fake and the host publish the same.
///
/// The clauses whose calls overlap give a host with an `await` between a check and its commit the chance to
/// fail, not the certainty; the stores that give way inside every call (`HostStores.suspending`) are where it
/// would. The implementation notes hold the counts of repeated runs, on the default pool and on one thread.
///
/// Every clause runs on every set-up in every lane. The seeded scripts run `Seeds.hostSeeds` on every set-up:
/// twenty in the PR lane, every seed of the lane in the nightly one (F10 S3 criterion 9).
@Suite("LocalWorkoutSessionActor · the contract", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorContractTests {
    typealias Contract = WorkoutSessionClientContract
    typealias Seeds = WorkoutSessionClientContractTests

    @Test("The host keeps the contract clause", arguments: Contract.clauses, HostSetup.allCases)
    func host_keepsTheClause(_ clause: Contract.Clause, _ setup: HostSetup) async throws {
        let issue = try await clause.check(setup.host())
        #expect(issue == nil, "\(clause.name), \(setup): \(issue ?? "")")
    }

    @Test("violations(of:) finds nothing wrong with the host", arguments: HostSetup.allCases)
    func violations_ofTheHost_areNone(_ setup: HostSetup) async {
        #expect(await Contract.violations { try await setup.host() } == [])
    }

    @Test(
        "A seeded script on the host returns, throws and publishes what the rules say, as on the fake",
        .tags(.property),
        arguments: Seeds.hostSeeds,
        HostSetup.allCases
    )
    func sessionScripts_fakeAndActorPublishTheSame(seed: UInt64, _ setup: HostSetup) async throws {
        let issue = try await Contract.scriptViolation(seed: seed, on: setup.host())
        #expect(issue == nil, "seed \(seed), \(setup): \(issue ?? "")")
    }
}
