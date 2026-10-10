@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S5 criterion 7: the pump when the cover closes, and when its tasks are cancelled and started
/// again ("a tap made while no pump runs waits for the next one").
extension WorkoutPumpAdversarialTests {
    /// FINDING F10-S5-1: "Minimize" drops the taps that were still waiting. The workout goes on after a
    /// Minimize, so a check tapped just before it is a set the lifter did and the log never gets; no alert
    /// says so. `WorkoutStore.leave` empties the queue for every exit, the store's own text says nothing is
    /// dropped but behind a refusal, and criterion 7 says none is lost.
    @Test("Taps made before Minimize are applied: minimizing does not end the workout")
    func minimize_keepsTheTapsMadeBeforeIt() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        await bench.session.holdEveryApply()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment), .log(exerciseIndex: 0, setID: first))
        await bench.drainReleasing {
            bench.store.send(.minimize)
        }
        #expect(bench.store.exit == .route(.minimized))
        let truth = try #require(await bench.session.current())
        #expect(truth.exercises[0].sets[0].weight == .pounds(190), "the tap whose call was waiting went through")
        #expect(truth.doneSets == 1, "the check tapped before Minimize logs its set")
        bench.following.cancel()
    }

    @Test("Taps made before Discard are not applied once it is tapped, whatever was waiting")
    func discard_dropsTheTapsMadeBeforeIt() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        await bench.session.holdEveryApply()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment), .log(exerciseIndex: 0, setID: first))
        await bench.drainReleasing {
            bench.store.send(.finish)
            bench.store.send(.discard)
        }
        #expect(await bench.session.applied.count == 1, "only the call that was already under way")
        #expect(bench.store.dialog == nil)
        bench.following.cancel()
    }

    @Test("The pump's task cancelled while a call waits: no alert, nothing applied twice, and a new pump carries on")
    func pumpCancelled_whileACallWaits() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        await bench.session.holdEveryApply()
        await bench.session.throwWhenCancelled()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
        let pump = Task { await bench.store.pump() }
        await eventually("the call to wait") { bench.session.waiting.value > 0 }
        pump.cancel()
        await bench.session.release()
        await pump.value
        #expect(bench.store.dialog == nil, "a call cancelled with the cover is no failure")
        #expect(bench.store.exit == nil)
        #expect(await bench.session.applied.isEmpty)

        await bench.session.holdEveryApply(false)
        let next = Task { await bench.store.pump() }
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
        await eventually("the new pump to apply the tap") {
            bench.store.shown?.exercises[0].sets[0].weight == .pounds(190)
        }
        #expect(await bench.session.applied.count == 1)
        next.cancel()
        bench.following.cancel()
    }

    /// FINDING F10-S5-2: a tap that waited for the next pump is planned on the workout as the cover last
    /// drew it, however long ago. When the cover's tasks start again the pump runs before the session's
    /// first update has arrived, so the tap is planned on the old workout: here it logs the set over the
    /// watch's log of it, at the weight and reps the page showed before. (Latent today: no screen takes the
    /// cover's view away and brings it back with the same store; the queue is kept for exactly that case.)
    @Test("A tap that waited for the next pump is not planned on the workout as it was before the cover went away")
    func pumpRestarted_plansOnTheNewestWorkout() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        let pump = Task { await bench.store.pump() }
        await bench.settled()
        pump.cancel()
        bench.following.cancel()
        await pump.value
        await bench.following.value
        // The cover's view is away. A tap made as it went waits; meanwhile the watch logs that set.
        bench.tap(.log(exerciseIndex: 0, setID: first))
        try await bench.session.elsewhere(.setLogged(
            exerciseIndex: 0, setID: first, weight: .pounds(300), reps: .one,
            doneAt: Fixtures.now.addingTimeInterval(60)
        ))
        // The view is back: `WorkoutRoot` starts its tasks again, in its order.
        let following = Task { await bench.store.follow() }
        let next = Task { await bench.store.pump() }
        await bench.settled()
        await giveWay()
        let truth = try #require(await bench.session.current())
        #expect(truth.exercises[0].sets[0].weight == .pounds(300), "the watch's set was logged over by a stale tap")
        #expect(await bench.session.applied.isEmpty, "the set was logged already: the tap comes to nothing")
        next.cancel()
        following.cancel()
    }

    /// FINDING F10-S5-3: the answer the store keeps for the next tap (`ahead`) is given up only when the
    /// stream shows that very workout. A follow that starts again begins with the session's newest workout,
    /// and when another hand changed it meanwhile the kept answer is never shown, so every later tap is
    /// planned on it instead of on the page: "+" on a row the page reads 300 lb sends 195.
    @Test("After the cover's follow starts again, a tap is planned on the workout the page shows")
    func followRestarted_forgetsTheOldAnswer() async throws {
        let bench = try await Bench.make()
        let first = bench.set(0, 0)
        await bench.session.keepStreamsBehind()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
        await bench.store.drain()
        bench.following.cancel()
        await bench.following.value
        try await bench.session.elsewhere(.setTargetChanged(
            exerciseIndex: 0,
            setID: first,
            weight: .pounds(300),
            reps: nil
        ))
        await bench.session.keepStreamsBehind(false)
        let following = Task { await bench.store.follow() }
        await bench.settled()
        #expect(bench.store.model.page?.card?.rows.first?.weight == "300")
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment))
        await bench.store.drain()
        #expect(await bench.weight(0, 0) == "305", "one step from what the page showed")
        following.cancel()
    }

    /// Round 2: with the store's date standing still every un-log falls in the very moment of its set's log,
    /// inside criterion 18's guard, and the storms would send none. Their clock moves (`Bench.make(ticking:)`)
    /// by 0 to 0.4 s for each tap, so some un-logs are second touches and some are not.
    @Test("The storms un-log sets when their clock moves: some un-logs pass the guard and some are held by it")
    func storms_exerciseTheUnlog() async throws {
        var (standing, moving, far) = (0, 0, 0)
        let isUnlog = { (event: WorkoutEvent) in
            if case .setUnlogged = event {
                return true
            }
            return false
        }
        for seed in UInt64(1) ... 16 {
            let taps = Self.taps(seed: seed, in: EventBuilders.seedSession())
            standing += try await Self.oneAtATime(taps).applied.count(where: isUnlog)
            moving += try await Self.oneAtATime(taps, ticking: seed).applied.count(where: isUnlog)
            far += try await Self.oneAtATime(taps, ticking: seed, by: 10 ... 10).applied.count(where: isUnlog)
        }
        print("un-logs in 16 storms: \(standing) standing, \(moving) moving, \(far) ten seconds apart")
        #expect(standing == 0, "an un-log in the moment of the log is a second touch")
        #expect(moving >= 8, "\(moving) un-logs in 16 storms")
        #expect(far > moving, "no un-log of the storms fell inside the guard")
    }
}
