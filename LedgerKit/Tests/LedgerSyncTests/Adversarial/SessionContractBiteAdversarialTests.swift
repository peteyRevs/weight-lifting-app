import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1: does `WorkoutSessionClientContract` bite? The fake passes it and S2's host
/// must, so a wrong client it accepts is a hole four later pieces inherit. `WrongSessionClient` is a client
/// written from the protocol's documentation alone; without a fault the contract must accept it (it would
/// otherwise demand more than the documentation says), and with any one fault some clause or some script
/// must complain.
@Suite("Adversarial F10 S1 · does the session contract bite", .tags(.sync), .timeLimit(.minutes(1)))
struct SessionContractBiteAdversarialTests {
    typealias Contract = WorkoutSessionClientContract

    /// The seeds the scripts run for each client.
    static let seeds: [UInt64] = Array(1 ... 12)

    /// What the contract's two public entry points say about a client with `fault`: every clause's
    /// complaint, and the first script that differs.
    static func complaints(about fault: SeamFault?) async throws -> (clauses: [String], script: String?) {
        let clauses = await Contract.violations { WrongSessionClient(fault) }
        for seed in seeds {
            if let difference = try await Contract.scriptViolation(seed: seed, on: WrongSessionClient(fault)) {
                return (clauses, "seed \(seed): \(difference)")
            }
        }
        return (clauses, nil)
    }

    @Test("A client written from the documentation alone keeps every clause and every script")
    func independentClient_keepsTheContract() async throws {
        let (clauses, script) = try await Self.complaints(about: nil)
        #expect(clauses == [])
        #expect(script == nil)
    }

    @Test(
        "A client written from the documentation alone answers this suite's oracle too",
        arguments: SeamSeed.all.prefix(25)
    )
    func independentClient_answersAsTheOracle(seed: SeamSeed) async throws {
        let divergence = try await FakeSessionDifferentialAdversarialTests.divergence(
            seed: seed.value,
            on: WrongSessionClient()
        )
        #expect(divergence == nil, "\(seed)")
    }

    /// Round 1 failed here for one fault (F10-S1-5: a client that judges a snapshot by its phase and start
    /// alone); the contract's unstartable snapshots now include a rest that is too long and a set done at a
    /// date that is not finite.
    @Test("The contract rejects a client with one fault", arguments: SeamFault.sequential)
    func faultyClient_isRejectedByAClauseOrAScript(_ fault: SeamFault) async throws {
        let (clauses, script) = try await Self.complaints(about: fault)
        #expect(!clauses.isEmpty || script != nil, "the contract accepts a client that \(fault)")
    }

    /// Every fault, with no exception: round 1 left two to the scripts (F10-S1-5 and F10-S1-6), and the
    /// clauses now take their expected ended states from the engine.
    @Test("The named clauses alone reject a client with one fault", arguments: SeamFault.sequential)
    func faultyClient_isRejectedByAClause(_ fault: SeamFault) async {
        let clauses = await Contract.violations { WrongSessionClient(fault) }
        #expect(!clauses.isEmpty, "every clause accepts a client that \(fault)")
    }

    /// Whether a fault shows depends on the scheduler: two calls must be inside the client at once. A run
    /// where none overlap proves nothing, so the clauses get ten runs and one complaint is enough; a
    /// contract that cannot see the fault complains in none. Round 1 failed here for five faults (F10-S1-3
    /// and F10-S1-4); the ordering walk and the four overlap clauses of the fix round are what catch them.
    @Test("The clauses reject a client whose fault shows only when calls overlap", arguments: SeamFault.racy)
    func racyClient_isRejectedByAClause(_ fault: SeamFault) async {
        var complaints: [String] = []
        for _ in 0 ..< 10 where complaints.isEmpty {
            complaints = await Contract.violations { WrongSessionClient(fault) }
        }
        #expect(!complaints.isEmpty, "in ten runs, every clause accepted a client that \(fault)")
    }

    /// F10-S1-1, as ruled after round 1: the contract now holds a client to `invalidEndDate`. A client that
    /// returns from a finish or a discard whose date the engine ignores, the workout still live (what the
    /// protocol documented before the ruling), breaks the clause written for it, and only that one.
    @Test("F10-S1-1: the contract rejects a client that returns for an end date the engine ignores")
    func clientThatReturnsForANonFiniteEnd_isRejectedByTheContract() async {
        let clauses = await Contract.violations { WrongSessionClient(.nonFiniteEndReturns) }
        #expect(clauses.count == 1)
        #expect(clauses.first?.hasPrefix("finish and discard at a date the engine ignores throw") == true)
    }

    /// What this suite's own overlap checks say of a client with `fault`: the first complaint of the
    /// history check, the late-join check and the three races.
    static func overlapComplaint(about fault: SeamFault) async throws -> String? {
        var found: [String?] = []
        for check in [Seam.overlapFault, Seam.lateJoinFault, Seam.endRaceFault, Seam.applyVersusEndFault] {
            let client = WrongSessionClient(fault)
            try await client.start(Seam.session(1))
            try await found.append(check(client))
        }
        try await found.append(Seam.startRaceFault(on: WrongSessionClient(fault)))
        return found.compactMap(\.self).first
    }

    @Test(
        "This suite's overlap checks reject a client whose fault shows only when calls overlap",
        arguments: SeamFault.racy
    )
    func racyClient_isRejectedByThisSuitesOverlapChecks(_ fault: SeamFault) async throws {
        var found: String?
        for _ in 0 ..< 10 where found == nil {
            found = try await Self.overlapComplaint(about: fault)
        }
        #expect(found != nil, "in ten runs, the overlap checks accepted a client that \(fault)")
    }

    /// This suite's own differential must see the faults it claims to cover, or its green runs on the fake
    /// say little. It makes no call from a second task and cancels no subscriber, so it is not asked about
    /// the faults that need either.
    static let outsideTheDifferential: Set<SeamFault> = [.cancelEndsEveryone]

    @Test(
        "This suite's oracle rejects a client with one fault",
        arguments: SeamFault.sequential.filter { !outsideTheDifferential.contains($0) }
    )
    func faultyClient_isRejectedByTheOracle(_ fault: SeamFault) async throws {
        var found: String?
        for seed in SeamSeed.all.prefix(25) where found == nil {
            found = try await FakeSessionDifferentialAdversarialTests.divergence(
                seed: seed.value,
                on: WrongSessionClient(fault)
            )
        }
        #expect(found != nil, "25 seeded scripts accept a client that \(fault)")
    }
}
