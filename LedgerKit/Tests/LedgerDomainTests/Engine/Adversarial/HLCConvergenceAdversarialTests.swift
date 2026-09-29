import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2: ADR-004's hybrid-logical-clock amendment under randomized partitions, ±30 s clock skew,
/// clock steps back and relaunches, with hosts that store first and reduce only what `append` newly
/// stored (finding 4 and 5 decisions).
@Suite("WorkoutEngine · HLC convergence (adversarial, round 2)", .tags(.domain))
struct HLCConvergenceAdversarialTests {
    /// Seeds for the tests that count a hazard across many sessions.
    static let sample = Array(PropertySeed.all.prefix(100))

    @Test(
        """
        With HLC stamps: every host agrees with replay of its store after every delivery, all converge after \
        healing, each stamp sorts after everything its device held, and every lifter action that was the last \
        word on its set stands
        """,
        .tags(.property),
        arguments: PropertySeed.all
    )
    func hlc_convergesAndKeepsEveryAction(seed: PropertySeed) async throws {
        let scenario = try await HLCScenario.run(HostPolicy(), seed: seed)
        let expected = try #require(WorkoutEngine.replay(scenario.everything))
        for host in scenario.hosts {
            #expect(host.replayMismatches == 0, "\(host.device) left replay")
            #expect(host.causalViolations.isEmpty, "\(host.device) stamped \(host.causalViolations) too early")
            #expect(host.state == expected, "\(host.device) did not converge")
            #expect(try await host.store.append(scenario.everything).isEmpty, "\(host.device) missed an envelope")
        }
        #expect(scenario.lostActions(in: expected).isEmpty, "lost \(scenario.lostActions(in: expected))")
    }

    @Test("Control: with raw device clocks the same sessions still converge, but lose lifter actions")
    func rawClocks_loseActions() async throws {
        var (checked, lost, early) = (0, 0, 0)
        for seed in Self.sample {
            let scenario = try await HLCScenario.run(HostPolicy(hybridClock: false), seed: seed)
            let expected = try #require(WorkoutEngine.replay(scenario.everything))
            for host in scenario.hosts {
                #expect(host.state == expected)
                #expect(host.replayMismatches == 0)
                early += host.causalViolations.count
            }
            checked += scenario.lastWords.count
            lost += scenario.lostActions(in: expected).count
        }
        #expect(checked > 3 * Self.sample.count, "only \(checked) last-word actions to check")
        #expect(early > 0 && lost > 0, "the property has no teeth: \(early) early stamps, \(lost) lost actions")
    }

    /// A lost action needs the relaunched device's early stamp to land on a contested set, which random
    /// sessions rarely produce; `HostContractAdversarialTests` has the direct repro.
    @Test("Finding 12 (documents): a host that forgets its HLC on relaunch stamps before envelopes it held")
    func forgottenClockOnRelaunch_stampsEarly() async throws {
        var early = 0
        for seed in Self.sample {
            let scenario = try await HLCScenario.run(HostPolicy(recoverClock: false), seed: seed, steps: 40)
            early += scenario.hosts.map(\.causalViolations.count).reduce(0, +)
        }
        #expect(early > 0, "no relaunch stamped early in \(Self.sample.count) sessions")
    }

    @Test(
        "Finding 13 (documents): a host that reduces every newly stored envelope in arrival order leaves replay"
    )
    func naiveHostLoop_leavesReplay() async throws {
        var diverged = 0
        for seed in Self.sample {
            let scenario = try await HLCScenario.run(HostPolicy(), seed: seed)
            diverged += scenario.hosts.map(\.naiveMismatches).reduce(0, +)
        }
        #expect(diverged > 0, "the naive loop never left replay in \(Self.sample.count) sessions")
    }

    @Test("Finding 14 (documents): under ±30 s skew, some +30s taps on a rest the lifter sees running find it over")
    func dragStamps_judgeRunningRestsOver() async throws {
        var judgedOver = 0
        for seed in Self.sample {
            judgedOver += try await HLCScenario.run(HostPolicy(), seed: seed, steps: 40).extendsJudgedOver
        }
        #expect(judgedOver > 0, "no +30s was judged over in \(Self.sample.count) sessions")
    }
}
