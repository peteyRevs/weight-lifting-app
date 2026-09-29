import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · replay (rule 12)", .tags(.domain))
struct ReplayTests {
    /// A two-device log of 61 envelopes from a fixed seed.
    private func fixedLog() -> [EventEnvelope] {
        var random = RandomWorkout(seed: 4242)
        return random.log(steps: 60)
    }

    @Test("Criterion 7: a log shuffled 100 times replays to the identical state every time")
    func criterion7_shuffled100Times_sameState() throws {
        let log = fixedLog()
        let expected = try #require(WorkoutEngine.replay(log))
        var rng = SeededGenerator(seed: 7)
        for _ in 0 ..< 100 {
            #expect(WorkoutEngine.replay(log.shuffled(using: &rng)) == expected)
        }
    }

    @Test("Criterion 8: a log with every envelope duplicated replays like the deduplicated log")
    func criterion8_duplicatedLog_equalsDedupedReplay() {
        let log = fixedLog()
        var rng = SeededGenerator(seed: 8)
        let doubled = (log + log).shuffled(using: &rng)
        #expect(WorkoutEngine.replay(log) != nil)
        #expect(WorkoutEngine.replay(doubled) == WorkoutEngine.replay(log))
        #expect(WorkoutEngine.foldOrder(doubled).count == log.count)
    }

    @Test(
        "replay of any arrival order with duplicates equals reducing the sorted log in sequence",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func replay_equalsSequentialReduce(seed: PropertySeed) {
        var random = RandomWorkout(seed: seed)
        let log = random.log(steps: 40)
        let arrival = random.shuffled(log + log.prefix(10))
        #expect(WorkoutEngine.replay(arrival) == Engine.fold(log.sorted()))
    }

    @Test("Resume (ADR-004 rule 6): replaying the persisted envelopes after a crash restores the live state")
    func resume_midWorkout_restoresState() {
        let log = fixedLog()
        var live: WorkoutState?
        var persisted: [EventEnvelope] = []
        for envelope in log.sorted().prefix(30) {
            let (next, effects) = WorkoutEngine.reduce(live, envelope)
            live = next
            persisted += effects.compactMap {
                if case let .persist(stored) = $0 {
                    stored
                } else {
                    nil
                }
            }
        }
        // The app is killed here; on relaunch it replays its store and carries on.
        var resumed = WorkoutEngine.replay(persisted)
        #expect(resumed == live)
        for envelope in log.sorted().dropFirst(30) {
            resumed = WorkoutEngine.reduce(resumed, envelope).0
        }
        #expect(resumed == WorkoutEngine.replay(log))
    }

    @Test("Dedupe keeps one envelope per (device, seq), and the order puts the first started in front")
    func foldOrder_dedupesAndLeadsWithStarted() {
        let started = Engine.started()
        let first = Engine.envelope(.restSkipped, 5, from: Engine.watch, seq: 1)
        let second = Engine.envelope(.restSkipped, 6, from: Engine.watch, seq: 2)
        let order = WorkoutEngine.foldOrder([second, first, second, started, first])
        #expect(order == [started, first, second])
        // With no usable started there is no workout to fold (fix round 1, findings 2 and 3).
        #expect(WorkoutEngine.foldOrder([second, first]).isEmpty)
    }

    @Test("Findings 2 and 3: only a usable started leads, and only its workout's envelopes are deduped and kept")
    func foldOrder_leadsWithUsableStarted_andKeepsOnlyItsWorkout() {
        var ended = EventBuilders.seedSession()
        ended.phase = .finished
        let other = WorkoutID(EventBuilders.uuid(0xF101))
        let unusable = EventBuilders.envelope(.started(ended), device: Engine.watch, seq: 1, at: Engine.at(-20))
        let early = Engine.envelope(Engine.logged(0, 0, at: -10), -10, from: Engine.watch, seq: 2)
        // Same key as `late`, in another workout, and sorting before it.
        let stray = EventBuilders.envelope(
            .restSkipped,
            device: Engine.watch,
            seq: 3,
            at: Engine.at(-5),
            workoutID: other
        )
        let late = Engine.envelope(Engine.logged(0, 1, at: 5), 5, from: Engine.watch, seq: 3)
        let log = [late, stray, Engine.started(), early, unusable]
        #expect(WorkoutEngine.foldOrder(log) == [Engine.started(), unusable, early, late])
        #expect(WorkoutEngine.replay(log) == Engine.fold([Engine.started(), early, late]))
        #expect(WorkoutEngine.replay(log)?.doneSets == 2)
    }
}
