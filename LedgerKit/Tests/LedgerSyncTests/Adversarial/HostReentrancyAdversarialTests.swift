import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, re-entrancy: an actor lets another call in at every `await`, and this one
/// awaits its store. `SiegeStorm` sends starts, applies, ends and subscriptions from six tasks at once over
/// stores that give way inside every call, and judges the result against what the store took.
@Suite("Adversarial F10 S2 · many callers at once", .tags(.sync, .property), .timeLimit(.minutes(1)))
struct HostReentrancyAdversarialTests {
    typealias Backing = SiegeRig.Backing

    @Test(
        "A storm of calls over the in-memory stores leaves one history",
        arguments: SessionLane.cut(SeamSeed.all.prefix(120), to: 30)
    )
    func storm_inMemoryStores_isOneHistory(seed: SeamSeed) async throws {
        let violation = try await SiegeStorm.violation(seed: seed.value, backing: .memory)
        #expect(violation == nil, "\(seed)")
    }

    @Test(
        "A storm of calls over the GRDB stores leaves one history",
        arguments: SessionLane.cut(SeamSeed.all.prefix(60), to: 10)
    )
    func storm_database_isOneHistory(seed: SeamSeed) async throws {
        let violation = try await SiegeStorm.violation(seed: seed.value, backing: .database)
        #expect(violation == nil, "\(seed)")
    }

    @Test("The storms reach what they claim: workouts that end, calls refused, streams opened in flight")
    func storms_coverTheRules() async throws {
        var ended = 0, refused = 0, opened = 0, returned = 0
        for seed in SeamSeed.all.prefix(30) {
            let rig = try await SiegeRig.make(.memory, yields: 2)
            let host = await rig.host()
            let heard = await SiegeStorm.run(SiegeStorm.script(seed: seed.value), on: host)
            let outcomes = heard.flatMap(\.outcomes).map(\.outcome)
            ended += await rig.siege.stored.count { $0.event.isTerminal }
            refused += outcomes.count {
                if case .refused = $0 {
                    true
                } else {
                    false
                }
            }
            returned += outcomes.count { $0 == .returned || $0.state != nil }
            opened += heard.flatMap(\.streams).count
        }
        #expect(
            ended > 30 && refused > 100 && returned > 300 && opened > 40,
            "\(ended) \(refused) \(returned) \(opened)"
        )
    }

    @Test(
        "Two starts at once: the first to reach the host wins, the other names its workout",
        arguments: Backing.allCases
    )
    func start_twoAtOnce_exactlyOneSucceeds(backing: Backing) async throws {
        let rig = try await SiegeRig.make(backing)
        let host = await rig.host()
        _ = try await host.current()
        await rig.siege.hold(.append)
        async let first = Seam.outcome(of: .start(Seam.session(1)), on: host)
        await rig.siege.waitUntilHeld()
        async let second = Seam.outcome(of: .start(Seam.session(2)), on: host)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        await rig.siege.release()
        #expect(await first == .returned)
        #expect(await second == .refused(.workoutInProgress(Seam.workout(1))))
        #expect(await rig.siege.stored.map(\.event) == [.started(Seam.session(1))])
        #expect(try await host.current() == Seam.session(1))
    }

    @Test("An apply, a current() and a new stream that arrive while a finish is saving", arguments: Backing.allCases)
    func finish_whileSaving_othersWaitOrSeeTheWorkoutAsItStood(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        let ending = try #require(scene.update(after: .finished(endedAt: SiegeScene.end)))
        await scene.siege.hold(.materialize)
        async let finish = Seam.outcome(of: .finish(SiegeScene.end), on: scene.host)
        await scene.siege.waitUntilHeld()
        let current = try await scene.host.current()
        let late = await scene.host.updates()
        async let apply = Seam.outcome(of: .apply(scene.nextLog), on: scene.host)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        await scene.siege.release()
        #expect(await finish == .state(ending.state ?? scene.live))
        #expect(await apply == .refused(.noLiveWorkout), "an apply that loses to the end")
        #expect(current == scene.live, "the state of the last update, until the ending one")
        #expect(await Seam.buffered(late) == [WorkoutSessionUpdate(state: scene.live), ending])
        #expect(await scene.heard() == [ending])
        #expect(await scene.siege.stored.contains { $0.event == scene.nextLog } == false)
    }
}
