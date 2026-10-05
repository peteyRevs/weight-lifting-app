import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 2 (close-out): does the contract, as the fix round left it, bite on clients the
/// implementer could not have read? `LateWrongSessionClient` is a second client written from the revised
/// documentation; its faults are the edges of the `invalidEndDate` rule, one judge for each snapshot the
/// contract added, and shapes of overlap fault that round 1's clients did not have.
@Suite("Adversarial F10 S1 · the contract after the fix round", .tags(.sync), .timeLimit(.minutes(1)))
struct SessionContractRoundTwoAdversarialTests {
    typealias Contract = WorkoutSessionClientContract

    /// What this suite's overlap checks say of a client with `fault`: the first complaint of round 1's five
    /// and round 2's three.
    static func overlapComplaint(about fault: SeamLateFault?) async throws -> String? {
        var found: [String?] = []
        let started = [
            Seam.overlapFault, Seam.lateJoinFault, Seam.endRaceFault, Seam.applyVersusEndFault,
            Seam.invalidEndRaceFault
        ]
        for check in started {
            let client = LateWrongSessionClient(fault)
            try await client.start(Seam.session(1))
            try await found.append(check(client))
        }
        for check in [Seam.startRaceFault, Seam.startVersusApplyFault, Seam.reactionFault] {
            try await found.append(check(LateWrongSessionClient(fault)))
        }
        return found.compactMap(\.self).first
    }

    @Test("A second client written from the revised documentation keeps the clauses, the scripts and this suite")
    func independentClient_keepsTheContract() async throws {
        #expect(await Contract.violations { LateWrongSessionClient() } == [])
        for seed in UInt64(1) ... 12 {
            #expect(try await Contract.scriptViolation(seed: seed, on: LateWrongSessionClient()) == nil)
        }
        for seed in SeamSeed.all.prefix(25) {
            let divergence = try await FakeSessionDifferentialAdversarialTests.divergence(
                seed: seed.value,
                on: LateWrongSessionClient()
            )
            #expect(divergence == nil, "\(seed)")
        }
        #expect(try await Self.overlapComplaint(about: nil) == nil)
    }

    @Test("The contract rejects a client with one fault of round 2", arguments: SeamLateFault.sequential)
    func faultyClient_isRejectedByAClauseOrAScript(_ fault: SeamLateFault) async throws {
        var complaints = await Contract.violations { LateWrongSessionClient(fault) }
        for seed in UInt64(1) ... 12 where complaints.isEmpty {
            let difference = try await Contract.scriptViolation(seed: seed, on: LateWrongSessionClient(fault))
            complaints = [difference].compactMap(\.self)
        }
        #expect(!complaints.isEmpty, "the contract accepts a client that \(fault)")
    }

    /// The clause for an end the engine ignores never tries an end the engine takes afterwards, so a client
    /// that keeps refusing passes it; the scripts make that call and reject the client.
    static let leftToTheScripts: Set<SeamLateFault> = [.invalidEndSticks]

    @Test(
        "The named clauses alone reject a client with one fault of round 2",
        arguments: SeamLateFault.sequential.filter { !leftToTheScripts.contains($0) }
    )
    func faultyClient_isRejectedByAClause(_ fault: SeamLateFault) async {
        let clauses = await Contract.violations { LateWrongSessionClient(fault) }
        #expect(!clauses.isEmpty, "every clause accepts a client that \(fault)")
    }

    /// The differential's scripts offer no snapshot whose only fault is a set's date, so it is not asked
    /// about that judge; `start_unstartableSnapshot_throwsNotStartable_andChangesNothing` holds the fake to it.
    @Test(
        "This suite's oracle rejects a client with one fault of round 2",
        arguments: SeamLateFault.sequential.filter { $0 != .judgesAllButSetDates }
    )
    func faultyClient_isRejectedByTheOracle(_ fault: SeamLateFault) async throws {
        var found: String?
        for seed in SeamSeed.all.prefix(25) where found == nil {
            found = try await FakeSessionDifferentialAdversarialTests.divergence(
                seed: seed.value,
                on: LateWrongSessionClient(fault)
            )
        }
        #expect(found != nil, "25 seeded scripts accept a client that \(fault)")
    }

    /// As in round 1: a fault that needs two calls inside the client at once gets ten runs, and one
    /// complaint is enough; a contract that cannot see the fault complains in none. It fails for four
    /// faults, F10-S1-7: no clause races a start against an apply (`startPublishesLate`), has a subscriber
    /// act on the update it was just given (`startCommitsLate`), overlaps events that buzz
    /// (`dropsHapticsUnderOverlap`), or overlaps an end the engine ignores with one it takes
    /// (`judgesAnEndByWhatIsLiveLater`).
    @Test(
        "The clauses reject a client whose round 2 fault shows only when calls overlap",
        arguments: SeamLateFault.racy
    )
    func racyClient_isRejectedByAClause(_ fault: SeamLateFault) async {
        var complaints: [String] = []
        for _ in 0 ..< 10 where complaints.isEmpty {
            complaints = await Contract.violations { LateWrongSessionClient(fault) }
        }
        #expect(!complaints.isEmpty, "in ten runs, every clause accepted a client that \(fault)")
    }

    @Test(
        "This suite's overlap checks reject a client whose round 2 fault shows only when calls overlap",
        arguments: SeamLateFault.racy
    )
    func racyClient_isRejectedByThisSuitesOverlapChecks(_ fault: SeamLateFault) async throws {
        var found: String?
        for _ in 0 ..< 10 where found == nil {
            found = try await Self.overlapComplaint(about: fault)
        }
        #expect(found != nil, "in ten runs, the overlap checks accepted a client that \(fault)")
    }
}
