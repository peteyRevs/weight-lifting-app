import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2 round 2, F10 S5 criterion 14: "Minimize" while taps wait. The cover closes once they are applied and
/// answers nothing meanwhile. Attacked with a call that is held, more taps and more buttons while it waits,
/// the pump's task cancelled under it, the session's stream ending under it, and the cover asked for again.
@MainActor
@Suite("Workout minimize (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutMinimizeAdversarialTests {
    typealias Bench = PumpBench

    @Test("While Minimize waits nothing else answers: more taps, Minimize again, Finish and Discard change nothing")
    func minimizeWaiting_nothingElseAnswers() async throws {
        let bench = try await Bench.make()
        let (first, second) = (bench.set(0, 0), bench.set(0, 1))
        await bench.session.holdEveryApply()
        bench.tap(.stepWeight(exerciseIndex: 0, setID: first, .increment), .log(exerciseIndex: 0, setID: first))
        await bench.drainReleasing {
            guard bench.store.exitWhenDrained == nil else {
                return
            }
            bench.store.send(.minimize)
            #expect(bench.store.exit == nil, "a tap is still waiting")
            #expect(bench.store.model.header?.isEnabled == false && bench.store.model.page?.isEnabled == false)
            bench.store.send(.minimize)
            bench.tap(.log(exerciseIndex: 0, setID: second))
            bench.store.send(.finish)
            bench.store.send(.discard)
            #expect(bench.store.dialog == nil && bench.store.discardAttempt == 0 && !bench.store.isDiscarding)
        }
        #expect(bench.store.exit == .route(.minimized))
        let truth = try #require(await bench.session.current())
        #expect(truth.exercises[0].sets[0].weight == .pounds(190) && truth.doneSets == 1)
        #expect(await bench.session.applied.count == 2, "the two taps made before Minimize, each once")
        // The cover is closing: nothing more reaches the workout the lifter is no longer looking at.
        bench.tap(.log(exerciseIndex: 0, setID: second))
        await bench.store.drain()
        #expect(await bench.session.applied.count == 2)
        bench.following.cancel()
    }

    @Test("A call held for long under Minimize: the cover stays up, dimmed, and closes when the call returns")
    func minimize_overACallHeldForLong() async throws {
        let bench = try await Bench.make()
        await bench.session.holdEveryApply()
        bench.tap(.log(exerciseIndex: 0, setID: bench.set(0, 0)), .log(exerciseIndex: 0, setID: bench.set(0, 1)))
        let pump = Task { await bench.store.pump() }
        await eventually("the first call to wait") { bench.session.waiting.value > 0 }
        bench.store.send(.minimize)
        await giveWay()
        #expect(bench.store.exit == nil)
        #expect(bench.store.model.header?.isEnabled == false)
        await bench.session.release()
        await eventually("the second call to wait") { bench.session.waiting.value > 0 }
        #expect(bench.store.exit == nil, "one tap is still waiting")
        await bench.session.release()
        await eventually("the cover to close") { bench.store.exit != nil }
        #expect(bench.store.exit == .route(.minimized))
        #expect(await bench.session.current()?.doneSets == 2)
        pump.cancel()
        bench.following.cancel()
    }

    @Test("Minimize while a discard is under way changes nothing: the discard ends the workout")
    func minimize_whileADiscardRuns() async throws {
        let bench = try await Bench.make()
        bench.tap(.log(exerciseIndex: 0, setID: bench.set(0, 0)))
        bench.store.send(.finish)
        bench.store.send(.discard)
        bench.store.send(.minimize)
        #expect(bench.store.exit == nil && bench.store.exitWhenDrained == nil)
        await bench.store.drain()
        await bench.store.discard()
        #expect(bench.store.exit == .route(.discarded))
        #expect(await bench.session.applied.isEmpty, "the tap made before Discard is not applied")
        bench.following.cancel()
    }

    @Test("The pump's task cancelled while Minimize waits: no tap is sent twice, and the next pump closes the cover")
    func pumpCancelled_whileMinimizeWaits() async throws {
        let bench = try await Bench.make()
        let (first, second) = (bench.set(0, 0), bench.set(0, 1))
        await bench.session.holdEveryApply()
        bench.tap(.log(exerciseIndex: 0, setID: first), .log(exerciseIndex: 0, setID: second))
        let pump = Task { await bench.store.pump() }
        await eventually("the first call to wait") { bench.session.waiting.value > 0 }
        bench.store.send(.minimize)
        pump.cancel()
        await bench.session.holdEveryApply(false)
        await bench.session.release()
        await pump.value
        // The session finished the call that was under way; whatever was left waits for the next pump.
        let next = Task { await bench.store.pump() }
        await eventually("the cover to close") { bench.store.exit != nil }
        #expect(bench.store.exit == .route(.minimized))
        #expect(bench.store.dialog == nil)
        let applied = await bench.session.applied
        #expect(applied.count == 2, "each of the two checks once")
        #expect(await bench.session.current()?.doneSets == 2)
        next.cancel()
        bench.following.cancel()
    }

    /// FINDING F10-S5-7 (latent, low): when the session's updates end while "Minimize" waits for a tap, the
    /// cover can never be closed. The store shows the failed screen, whose only button, "Close", sends
    /// `.minimize`; `send` answers nothing while `exitWhenDrained` is set, and the drain that would clear it
    /// applies nothing once the store no longer hears the session. No host ends a stream (the key's stub
    /// does), so no lifter meets it today.
    @Test("When the session's updates end while Minimize waits, the failed screen's Close still closes the cover")
    func streamEnds_whileMinimizeWaits_closeStillCloses() async throws {
        let bench = try await Bench.make()
        await bench.session.holdEveryApply()
        bench.tap(.log(exerciseIndex: 0, setID: bench.set(0, 0)), .log(exerciseIndex: 0, setID: bench.set(0, 1)))
        let pump = Task { await bench.store.pump() }
        await eventually("the first call to wait") { bench.session.waiting.value > 0 }
        bench.store.send(.minimize)
        await bench.session.endStreams()
        await bench.following.value
        await bench.session.holdEveryApply(false)
        await bench.session.release()
        await giveWay()
        if bench.store.exit == nil {
            // The lifter is shown "Couldn't open this workout" and taps its "Close".
            bench.store.send(.minimize)
            await giveWay()
        }
        #expect(bench.store.exit != nil, "the cover is up for good: its one button answers nothing")
        pump.cancel()
    }

    @Test("The cover asked for again while Minimize waits: one cover, one Minimize, the tap applied once")
    func resumeAsked_whileMinimizeWaits() async throws {
        try await AdversarialWorld.run(.fake) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let store = try #require(rig.store)
            let live = try #require(try await world.live())
            await world.session.clearCalls()
            store.send(.edit(.log(exerciseIndex: 0, setID: live.exercises[0].sets[0].id)))
            store.send(.minimize)
            #expect(store.exit == nil)
            await rig.resume()
            await rig.start(world.source(day: 0))
            #expect(rig.covers == 1 && rig.isCoverUp && store.exit == nil)
            await store.drain()
            await rig.settle()
            #expect(rig.routes == [.minimized])
            #expect(await world.session.count(.apply) == 1)
            #expect(try await world.live()?.doneSets == 1)
        }
    }
}
