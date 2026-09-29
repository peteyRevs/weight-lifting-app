import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Rule 12 and criteria 7–10 as properties over random 2–3-device histories with skewed clocks,
/// ties, partitions, duplicates and shuffled delivery (testing-strategy §2.1).
@Suite("WorkoutEngine · convergence properties (adversarial)", .tags(.domain, .property))
struct ConvergencePropertyAdversarialTests {
    /// A random history: connected, then partitioned, then (sometimes) connected again.
    static func scenario(_ seed: PropertySeed) -> (scenario: EngineScenario, generator: SeededGenerator) {
        var generator = seed.generator
        let devices = generator.chance(40)
            ? [EngineAdv.phone, EngineAdv.watch, EngineAdv.tablet]
            : [EngineAdv.phone, EngineAdv.watch].shuffled(using: &generator)
        let snapshot = EngineGen.session(using: &generator)
        var scenario = EngineScenario(devices: devices, snapshot: snapshot, using: &generator)
        scenario.start()
        for _ in 0 ..< Int.random(in: 0 ... 8, using: &generator) {
            let device = devices.randomElement(using: &generator) ?? EngineAdv.phone
            if let envelope = scenario.act(device, using: &generator) {
                scenario.deliver(envelope, to: devices.filter { $0 != device })
            }
        }
        for _ in 0 ..< Int.random(in: 1 ... 25, using: &generator) {
            scenario.act(devices.randomElement(using: &generator) ?? EngineAdv.phone, using: &generator)
        }
        return (scenario, generator)
    }

    @Test("Criterion 7: replay is identical for every shuffle of the log.", arguments: PropertySeed.all)
    func replay_isOrderInvariant(seed: PropertySeed) {
        var (scenario, generator) = Self.scenario(seed)
        let log = scenario.all
        let expected = WorkoutEngine.replay(log)
        for _ in 0 ..< 5 {
            #expect(WorkoutEngine.replay(log.shuffled(using: &generator)) == expected)
        }
    }

    @Test(
        "Criterion 8: duplicating any envelopes (any number of times) never changes replay.",
        arguments: PropertySeed.all
    )
    func replay_isDuplicateTolerant(seed: PropertySeed) {
        var (scenario, generator) = Self.scenario(seed)
        let log = scenario.all
        var noisy = log + log + log.filter { _ in generator.chance(50) }
        noisy.shuffle(using: &generator)
        #expect(WorkoutEngine.replay(noisy) == WorkoutEngine.replay(log))
    }

    @Test(
        "Criterion 9: after the partition heals, every device holds the same state as replay of all envelopes.",
        arguments: PropertySeed.all
    )
    func partition_converges(seed: PropertySeed) {
        var (scenario, generator) = Self.scenario(seed)
        scenario.heal(using: &generator)
        let expected = WorkoutEngine.replay(scenario.all)
        for device in scenario.devices {
            #expect(scenario.replicas[device]?.state == expected, "device \(device.rawValue) diverged")
        }
    }

    @Test(
        "ADR-004 rule 2: a device folding in-order arrivals with reduce matches replay after every arrival.",
        arguments: PropertySeed.all
    )
    func incremental_matchesReplayAtEveryStep(seed: PropertySeed) {
        var (scenario, generator) = Self.scenario(seed)
        var inbox = scenario.all.filter { _ in generator.chance(85) }
        inbox += inbox.filter { _ in generator.chance(15) }
        if generator.chance(50) {
            inbox.sort()
        } else {
            inbox.shuffle(using: &generator)
        }
        var replica = Replica()
        for envelope in inbox {
            replica.receive(envelope)
            #expect(replica.state == WorkoutEngine.replay(replica.envelopes), "after \(envelope.event)")
        }
    }

    @Test(
        "Rule 12: with the started first in order, folding the sorted, de-duplicated log with reduce equals replay.",
        arguments: PropertySeed.all
    )
    func sortedFold_equalsReplay(seed: PropertySeed) {
        let (scenario, _) = Self.scenario(seed)
        var seen = Set<EnvelopeKey>()
        let sorted = scenario.all.sorted().filter { seen.insert($0.key).inserted }
        guard let first = sorted.first, case .started = first.event else {
            return
        }
        #expect(EngineAdv.state(after: sorted) == WorkoutEngine.replay(sorted))
    }
}

// MARK: - The model oracle, on this pass's generator (criterion 10)

extension ConvergencePropertyAdversarialTests {
    @Test(
        "Criterion 10: WorkoutEngine.replay agrees with ModelOracle.replay on adversarial histories.",
        arguments: PropertySeed.all
    )
    func replay_matchesOracle(seed: PropertySeed) {
        let (scenario, _) = Self.scenario(seed)
        #expect(WorkoutEngine.replay(scenario.all) == ModelOracle.replay(scenario.all))
    }

    @Test(
        "Criterion 10: step by step in arrival order, reduce agrees with ModelOracle.apply.",
        arguments: PropertySeed.all
    )
    func reduce_matchesOracleStepByStep(seed: PropertySeed) {
        var (scenario, generator) = Self.scenario(seed)
        var inbox = scenario.all
        inbox.shuffle(using: &generator)
        var oracle = ModelOracle()
        var state: WorkoutState?
        for envelope in inbox {
            oracle.apply(envelope)
            state = WorkoutEngine.reduce(state, envelope).0
            #expect(state == oracle.state, "diverged at \(envelope.event)")
            if state != oracle.state {
                return
            }
        }
    }
}
