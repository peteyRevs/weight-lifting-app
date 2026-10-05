import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 criteria 1 to 4 and 7: `WorkoutSessionClientContract` on `FakeWorkoutSessionClient`, each clause and
/// each seeded script on a fresh fake. S2 runs the same clauses and scripts on the host, so a screen tested on
/// the fake meets the same updates in the app.
@Suite("WorkoutSessionClient · the contract on the fake", .tags(.sync), .timeLimit(.minutes(1)))
struct WorkoutSessionClientContractTests {
    typealias Contract = WorkoutSessionClientContract

    /// `LEDGER_PROPERTY_SEED_COUNT` seeds (PR lane 200, nightly 2,000); 200 when unset or invalid. A failing
    /// seed is named in the failure and added as a fixed case (testing-strategy §3 rule 5).
    static let seeds: [UInt64] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init)
        return (0 ..< max(1, configured ?? 200)).map(seed)
    }()

    /// Twenty seeds whatever the lane sets: the tests that ask what a handful of scripts reach, or notice,
    /// must not depend on how many seeds a run was given.
    static let fixedSeeds: [UInt64] = (0 ..< 20).map(seed)

    static func seed(_ number: Int) -> UInt64 {
        UInt64(number) &* 7919 &+ 17
    }

    @Test("FakeWorkoutSessionClient keeps the contract clause", arguments: Contract.clauses)
    func fake_keepsTheClause(_ clause: Contract.Clause) async throws {
        let issue = try await clause.check(FakeWorkoutSessionClient())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("violations(of:) asks for a fresh client per clause and finds nothing wrong with the fake")
    func violations_ofTheFake_areNone() async {
        #expect(await Contract.violations { FakeWorkoutSessionClient() } == [])
    }

    @Test(
        "A seeded script on the fake returns, throws and publishes what the rules say",
        .tags(.property),
        arguments: seeds
    )
    func fake_runsTheScriptByTheRules(seed: UInt64) async throws {
        let issue = try await Contract.scriptViolation(seed: seed, on: FakeWorkoutSessionClient())
        #expect(issue == nil, "seed \(seed): \(issue ?? "")")
    }

    @Test("The same seed writes the same script, and another seed another")
    func script_dependsOnItsSeedAlone() {
        let first = Contract.script(seed: 7).map(\.description)
        #expect(first == Contract.script(seed: 7).map(\.description))
        #expect(first != Contract.script(seed: 8).map(\.description))
        #expect(first.count == 80)
        #expect(Contract.script(seed: 7, count: 3).map(\.description) == Array(first.prefix(3)))
    }

    /// What a script's calls came to on a fake, by kind: a refusal by its error, anything else by its call.
    static func outcomes(seed: UInt64) async -> Set<String> {
        let fake = FakeWorkoutSessionClient()
        var kinds: Set<String> = []
        for step in Contract.script(seed: seed) {
            do {
                switch step {
                case let .start(snapshot): try await fake.start(snapshot)
                case let .apply(event): try await fake.apply(event)
                case let .finish(endedAt): _ = try await fake.finish(endedAt: endedAt)
                case let .discard(endedAt): try await fake.discard(endedAt: endedAt)
                }
                kinds.insert(String(step.description.prefix { $0 != "(" }))
            } catch {
                kinds.insert(String(String(describing: error).prefix { $0 != "(" }))
            }
        }
        return kinds
    }

    @Test("Twenty scripts reach every call and every refusal the rules name")
    func scripts_reachEveryCallAndRefusal() async {
        var kinds: Set<String> = []
        var events: Set<String> = []
        for seed in Self.fixedSeeds {
            await kinds.formUnion(Self.outcomes(seed: seed))
            events.formUnion(Contract.script(seed: seed).map(\.description).filter { $0.hasPrefix("apply") })
        }
        #expect(kinds == [
            "start", "apply", "finish", "discard",
            "workoutInProgress", "notStartable", "noLiveWorkout", "invalidEndDate"
        ])
        #expect(events == [
            "apply(.started)", "apply(.exerciseSelected)", "apply(.setLogged)", "apply(.setUnlogged)",
            "apply(.setTargetChanged)", "apply(.setAdded)", "apply(.allSetsRepeated)", "apply(.exerciseSwapped)",
            "apply(.restStarted)", "apply(.restExtended)", "apply(.restSkipped)", "apply(.finished)",
            "apply(.discarded)"
        ])
    }
}
