import LedgerDomain
import LedgerTestSupport
import Testing

/// The clauses must be able to fail: each fault below is one a host could plausibly have, and the contract
/// has to name the clause it breaks. Without a fault, the same client keeps every clause.
@Suite("WorkoutSessionClient · the contract notices a faulty client", .tags(.sync), .timeLimit(.minutes(1)))
struct WorkoutSessionClientContractFaultTests {
    typealias Contract = WorkoutSessionClientContract
    typealias Fault = FaultyWorkoutSession.Fault

    @Test("With no fault the stand-in keeps every clause and every script")
    func noFault_keepsTheContract() async throws {
        #expect(await Contract.violations { FaultyWorkoutSession(nil) } == [])
        for seed in WorkoutSessionClientContractTests.seeds.prefix(20) {
            #expect(try await Contract.scriptViolation(seed: seed, on: FaultyWorkoutSession(nil)) == nil)
        }
    }

    @Test("The clause a fault breaks reports it", arguments: Fault.allCases)
    func fault_breaksItsClause(_ fault: Fault) async {
        let violations = await Contract.violations { FaultyWorkoutSession(fault) }
        #expect(
            violations.contains { $0.hasPrefix(fault.brokenClause) },
            "\(fault) should break “\(fault.brokenClause)”; the contract reported \(violations)"
        )
    }

    @Test("A seeded script notices each fault within twenty seeds", arguments: Fault.allCases)
    func fault_isNoticedByAScript(_ fault: Fault) async throws {
        var noticed = false
        for seed in WorkoutSessionClientContractTests.seeds.prefix(20) where !noticed {
            noticed = try await Contract.scriptViolation(seed: seed, on: FaultyWorkoutSession(fault)) != nil
        }
        #expect(noticed, "\(fault)")
    }
}
