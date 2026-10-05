import LedgerDomain
import LedgerTestSupport
import Testing

/// The clauses must be able to fail: each fault below is one a host could plausibly have, every clause has at
/// least one, and the contract has to name the clause a fault breaks. Without a fault, the same client keeps
/// every clause.
@Suite("WorkoutSessionClient · the contract notices a faulty client", .tags(.sync), .timeLimit(.minutes(1)))
struct WorkoutSessionClientContractFaultTests {
    typealias Contract = WorkoutSessionClientContract
    typealias Fault = FaultyWorkoutSession.Fault

    @Test("With no fault the stand-in keeps every clause and every script")
    func noFault_keepsTheContract() async throws {
        #expect(await Contract.violations { FaultyWorkoutSession(nil) } == [])
        for seed in WorkoutSessionClientContractTests.fixedSeeds {
            #expect(try await Contract.scriptViolation(seed: seed, on: FaultyWorkoutSession(nil)) == nil)
        }
    }

    @Test("Every clause has a fault that breaks it, and every fault names a clause")
    func everyClause_hasAFault() {
        for clause in Contract.clauses {
            let faults = Fault.allCases.filter { clause.name.hasPrefix($0.brokenClause) }
            #expect(!faults.isEmpty, "no fault breaks “\(clause.name)”")
        }
        for fault in Fault.allCases {
            #expect(Contract.clauses.count { $0.name.hasPrefix(fault.brokenClause) } == 1, "\(fault)")
        }
    }

    /// A fault that needs two calls inside the client at once shows only in a run where two did overlap,
    /// which no test can force. Such a fault gets ten runs and must be reported in one; a contract that
    /// cannot see it reports it in none. Every other fault must be reported by the first run.
    @Test("The clause a fault breaks reports it", arguments: Fault.allCases)
    func fault_breaksItsClause(_ fault: Fault) async {
        var violations: [String] = []
        var reported = false
        for _ in 0 ..< (fault.needsOverlap ? 10 : 1) where !reported {
            violations = await Contract.violations { FaultyWorkoutSession(fault) }
            reported = violations.contains { $0.hasPrefix(fault.brokenClause) }
        }
        #expect(reported, "\(fault) should break “\(fault.brokenClause)”; the contract reported \(violations)")
    }

    @Test(
        "A seeded script notices each fault a script can meet, within twenty seeds",
        arguments: Fault.allCases.filter(\.showsInAScript)
    )
    func fault_isNoticedByAScript(_ fault: Fault) async throws {
        var noticed = false
        for seed in WorkoutSessionClientContractTests.fixedSeeds where !noticed {
            noticed = try await Contract.scriptViolation(seed: seed, on: FaultyWorkoutSession(fault)) != nil
        }
        #expect(noticed, "\(fault)")
    }
}
