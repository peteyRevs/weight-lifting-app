import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// G2, F10 S6 round 2: what fix round 1 added to the store. `missedHaptics` (a follow that starts again
/// plays what changed meanwhile), `newestRest` (the buzz at zero asks the session's newest answer), and
/// ruling 16 (a tick changes the rest panel and nothing else the cover's views read).
extension WorkoutRestAdversarialTests {
    /// A store on a `PumpSession` with haptics that can be held, and the first exercise's rows.
    struct Gated {
        let session: PumpSession
        let store: WorkoutStore
        let haptics = GatedHaptics()
        let rows: [LoggedSet]

        init() {
            let running = EventBuilders.seedSession()
            let client = PumpSession(live: running)
            session = client
            rows = running.exercises[0].sets
            store = withTestDependencies { [haptics] in
                $0.workoutSession = client
                $0.haptics = haptics
            } operation: {
                WorkoutStore()
            }
        }
    }

    static func logged(_ row: LoggedSet) -> WorkoutEvent {
        .setLogged(exerciseIndex: 0, setID: row.id, weight: row.weight, reps: row.reps, doneAt: Fixtures.now)
    }

    // MARK: missedHaptics

    @Test("A follow that starts again with nothing changed plays nothing; nor does a first follow, sets logged or not")
    func followAgain_nothingChanged_playsNothing() async throws {
        let gated = Gated()
        let (session, store, haptics, rows) = (gated.session, gated.store, gated.haptics, gated.rows)
        try await session.elsewhere(Self.logged(rows[0]))
        var following = Task { await store.follow() }
        await eventually("the first update") { store.shown?.doneSets == 1 }
        #expect(await haptics.played == [], "a first follow plays nothing old")
        // The lifter's own set, felt from its update; then the tasks start again, twice.
        store.send(.edit(.log(exerciseIndex: 0, setID: rows[1].id)))
        await store.drain()
        await eventually("the set on the page") { store.shown?.doneSets == 2 }
        for _ in 0 ..< 2 {
            following.cancel()
            await following.value
            following = Task { await store.follow() }
            await eventually("the follow to hear the session") { store.isHearingTheSession }
        }
        await giveWay()
        #expect(await haptics.played == [.setLogged], "the lifter's own set is not felt again")
        following.cancel()
    }

    @Test(
        "Sets logged by another hand while the follow was away are one buzz on its return, however many; an un-log none"
    )
    func followAgain_afterABurstElsewhere_oneBuzz() async throws {
        let gated = Gated()
        let (session, store, haptics, rows) = (gated.session, gated.store, gated.haptics, gated.rows)
        var following = Task { await store.follow() }
        await eventually("the first update") { store.shown != nil }
        following.cancel()
        await following.value
        for row in rows.prefix(4) {
            try await session.elsewhere(Self.logged(row))
        }
        following = Task { await store.follow() }
        await eventually("the four sets on the page") { store.shown?.doneSets == 4 }
        await giveWay()
        #expect(await haptics.played == [.setLogged], "one for the change, as the engine feels a change of state")
        following.cancel()
        await following.value
        try await session.elsewhere(.setUnlogged(exerciseIndex: 0, setID: rows[0].id))
        following = Task { await store.follow() }
        await eventually("the un-log on the page") { store.shown?.doneSets == 3 }
        await giveWay()
        #expect(await haptics.played == [.setLogged])
        following.cancel()
    }

    /// **As built, for F18** (ruling 21 records that `follow()` awaits the haptics client, so a client must
    /// return at once; the phone's does). What a client that does not would meet: `follow()` does not stop
    /// at its task's cancellation. It goes on with what its stream had buffered, and when it ends it marks
    /// the store as not hearing the session. A follow cancelled while it waits in a slow `play` overlaps
    /// the follow that replaces it: the new one plays the set the old one had not shown (`missedHaptics`),
    /// the old one then shows and plays it too, and at its end the pump is told the store hears nothing, so
    /// taps wait until the follow starts yet again. A check of `Task.isCancelled` in the loop ends all
    /// three. When F18 builds its client, this test changes with it.
    @Test("As built (F18): a follow cancelled inside a slow haptic plays a set twice and leaves the taps waiting")
    func followCancelled_duringASlowHaptic_asBuilt() async throws {
        let gated = Gated()
        let (session, store, haptics, rows) = (gated.session, gated.store, gated.haptics, gated.rows)
        let first = Task { await store.follow() }
        await eventually("the first update") { store.shown != nil }
        await haptics.hold()
        try await session.elsewhere(Self.logged(rows[0]))
        await eventually("the first set on the page") { store.shown?.doneSets == 1 }
        try await session.elsewhere(Self.logged(rows[1]))
        await giveWay()
        // The first follow is still in the first set's haptic. The view goes and comes back.
        first.cancel()
        var second = Task { await store.follow() }
        await eventually("the second follow to show both sets") { store.shown?.doneSets == 2 }
        for _ in 0 ..< 4 {
            await haptics.release()
            await giveWay()
        }
        await first.value
        #expect(await haptics.played == [.setLogged, .setLogged, .setLogged], "two sets, three buzzes")
        #expect(!store.isHearingTheSession, "the follow that ended last says the store hears nothing")
        store.send(.edit(.stepReps(exerciseIndex: 0, setID: rows[2].id, .increment)))
        await store.drain()
        #expect(await session.applied.isEmpty, "a tap made now waits")
        // It is applied when the follow starts again, and nothing more is felt.
        second.cancel()
        await second.value
        second = Task { await store.follow() }
        await eventually("the follow to hear the session") { store.isHearingTheSession }
        await store.drain()
        #expect(await session.applied.count == 1)
        #expect(await haptics.played.count == 3)
        second.cancel()
    }

    // MARK: newestRest

    @Test("An answer ahead of the page that holds the same rest does not take the buzz at zero away")
    func answerAhead_sameRest_stillFelt() async throws {
        let bench = try await LaggingRestBench()
        let rows = bench.running.exercises[0].sets
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: rows[0].id)))
        await bench.store.drain()
        await eventually("the rest on the page") { bench.store.shownRest != nil }
        let keeper = Task { await bench.store.keepRestTime() }
        await giveWay()
        await bench.clock.base.advance(by: .seconds(149))
        await bench.session.keepStreamsBehind()
        bench.store.send(.edit(.stepReps(exerciseIndex: 0, setID: rows[1].id, .increment)))
        await bench.store.drain()
        #expect(bench.store.ahead != nil, "the stepper's answer is ahead of the page")
        await bench.clock.base.advance(by: .seconds(1))
        await keeper.value
        #expect(await bench.played() == [.setLogged, .restOver])
        bench.following.cancel()
    }

    @Test("+30s the session has taken and the page has not heard: nothing at the old end, the buzz at the new one")
    func extended_withThePageBehind_feltAtTheNewEnd() async throws {
        let bench = try await LaggingRestBench()
        let rows = bench.running.exercises[0].sets
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: rows[0].id)))
        await bench.store.drain()
        await eventually("the rest on the page") { bench.store.shownRest != nil }
        var keeper = Task { await bench.store.keepRestTime() }
        await giveWay()
        await bench.clock.base.advance(by: .seconds(149))
        await bench.session.keepStreamsBehind()
        bench.store.send(.edit(.extendRest))
        await bench.store.drain()
        await bench.clock.base.advance(by: .seconds(1))
        await keeper.value
        #expect(await bench.played() == [.setLogged], "the rest was extended: its old end is not felt")
        // The page hears; the root starts the task again for the longer rest.
        await bench.session.keepStreamsBehind(false)
        await eventually("the longer rest on the page") { bench.store.shownRest?.total == .seconds(180) }
        #expect(bench.store.restPanel?.status == "Resting")
        keeper = Task { await bench.store.keepRestTime() }
        await giveWay()
        await bench.clock.base.advance(by: .seconds(30))
        await keeper.value
        #expect(await bench.played() == [.setLogged, .restOver])
        #expect(bench.store.restPanel?.status == "Rest over")
        bench.following.cancel()
    }

    /// As built (the reviewer's note S6-R2-N1). Since ruling 18 a tap carries its own instant, but a rest's
    /// end is felt by what the session holds when it comes. "+30s" tapped two seconds before zero and still
    /// waiting behind a slow save at zero: the rest reaches "Rest over" and is felt; the save ends, the tap
    /// is applied at its own instant, the rest is extended and counts again; its new end is felt too. The
    /// same for "Skip rest": felt at zero, then the panel goes. Reported, not ruled.
    @Test("As built (S6-R2-N1): +30s tapped before zero and applied after it is felt at the old end and at the new")
    func extendTappedBeforeZero_appliedAfter_asBuilt() async throws {
        let bench = try await LaggingRestBench()
        let rows = bench.running.exercises[0].sets
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: rows[0].id)))
        await bench.store.drain()
        await eventually("the rest on the page") { bench.store.shownRest != nil }
        var keeper = Task { await bench.store.keepRestTime() }
        await giveWay()
        await bench.clock.base.advance(by: .seconds(148))
        await bench.session.holdEveryApply()
        bench.store.send(.edit(.stepReps(exerciseIndex: 0, setID: rows[1].id, .increment)))
        bench.store.send(.edit(.extendRest))
        let draining = Task { await bench.store.drain() }
        await eventually("the stepper's call held") { bench.session.waiting.value > 0 }
        await bench.clock.base.advance(by: .seconds(2))
        await keeper.value
        #expect(bench.store.restPanel?.status == "Rest over")
        #expect(await bench.played() == [.setLogged, .restOver], "felt at the old end")
        await bench.session.holdEveryApply(false)
        await bench.session.release()
        await draining.value
        await eventually("the longer rest on the page") { bench.store.shownRest?.total == .seconds(180) }
        #expect(bench.store.shownRest?.endsAt == Fixtures.now.addingTimeInterval(180), "extended, by the tap's instant")
        keeper = Task { await bench.store.keepRestTime() }
        await giveWay()
        #expect(bench.store.restPanel?.clock == "0:30")
        await bench.clock.base.advance(by: .seconds(30))
        await keeper.value
        #expect(await bench.played() == [.setLogged, .restOver, .restOver], "and at the new one")
        bench.following.cancel()
    }

    /// As built, for F17 (no second hand exists on one phone): an answer that comes back after the page
    /// has shown a later change by another hand stays as the store's "newest" workout (S5's `ahead`),
    /// though it is the older one. While it does, the buzz at zero asks it: a rest another hand extended
    /// meanwhile ends without a buzz.
    @Test("As built (F17): an answer older than the page, kept as the newest, takes the buzz of a peer's longer rest")
    func staleAnswer_takesThePeersBuzz_asBuilt() async throws {
        let bench = try await LaggingRestBench()
        let rows = bench.running.exercises[0].sets
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: rows[0].id)))
        await bench.store.drain()
        await eventually("the rest on the page") { bench.store.shownRest != nil }
        await bench.session.holdEveryAnswer()
        bench.store.send(.edit(.stepReps(exerciseIndex: 0, setID: rows[1].id, .increment)))
        let draining = Task { await bench.store.drain() }
        await eventually("the answer held") { bench.session.waiting.value > 0 }
        try await bench.session.elsewhere(
            .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: bench.now)
        )
        await eventually("the peer's longer rest on the page") { bench.store.shownRest?.total == .seconds(180) }
        await bench.session.release()
        await draining.value
        #expect(bench.store.ahead?.rest?.total == .seconds(150), "the older answer is kept as the newest")
        let keeper = Task { await bench.store.keepRestTime() }
        await giveWay()
        await bench.clock.base.advance(by: .seconds(180))
        await keeper.value
        #expect(bench.store.restPanel?.status == "Rest over")
        #expect(await bench.played() == [.setLogged])
        bench.following.cancel()
    }
}
