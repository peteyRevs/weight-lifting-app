import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2: minimal repros for the host-contract questions (findings 12–14). Fix round 2 answered each
/// (orchestrator decisions E, F and B), and the final fix round simplified the loop (re-plan 2026-09-29,
/// decision 3); every test asserts the answer on a host model, and keeps the wrong reading as a control
/// that shows the rule is load-bearing.
@Suite("WorkoutEngine · host contract (adversarial, round 2)", .tags(.domain))
struct HostContractAdversarialTests {
    typealias Adv = EngineAdv

    static let unlog = WorkoutEvent.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0))

    /// What `relaunchThenUnlog` observed.
    struct Relaunch {
        /// The set is done after a replay of the phone's log.
        let done: Bool
        /// The phone's own screen shows it done.
        let shown: Bool
        /// The un-log's stamp, and the largest stamp stored before it.
        let unlogStamp: Date
        let newestStored: Date
    }

    /// The phone logs set (0, 0) at 100 s, is killed and relaunched, its clock steps back 5 s, and it
    /// un-logs the set 2 s later.
    static func relaunchThenUnlog(_ policy: HostPolicy) async throws -> Relaunch {
        var phone = SimHost(Adv.phone, offset: 0, policy: policy)
        _ = try await phone.create(.started(EventBuilders.seedSession()), real: 0)
        _ = try await phone.create(Adv.logged(0, 0, doneAt: 100), real: 100)
        await phone.relaunch()
        let newestStored = try #require(await phone.log.map(\.wallClock).max())
        phone.offset -= 5
        let unlogged = try await phone.create(Self.unlog, real: 102)
        let replayed = await WorkoutEngine.replay(phone.log)
        return Relaunch(
            done: Adv.row(replayed, 0, 0)?.isDone == true,
            shown: Adv.row(phone.state, 0, 0)?.isDone == true,
            unlogStamp: unlogged.wallClock,
            newestStored: newestStored
        )
    }

    @Test(
        """
        Finding 12 / decision E: on relaunch the HLC's newest is the largest stored wallClock, so the un-log \
        after a 5 s step back sorts after the log and the set stays undone; a host that forgets it loses the un-log
        """
    )
    func hlcAfterRelaunch_mustBeRecoveredFromTheLog() async throws {
        let recovered = try await Self.relaunchThenUnlog(HostPolicy(recoverClock: true))
        #expect(recovered.unlogStamp > recovered.newestStored, "the first stamp after relaunch sorts after the log")
        #expect(!recovered.done)
        #expect(!recovered.shown)
        // Control: the rule is load-bearing. Started empty, the clock stamps 97 s < 100 s.
        let forgotten = try await Self.relaunchThenUnlog(HostPolicy(recoverClock: false))
        #expect(forgotten.unlogStamp < forgotten.newestStored)
        #expect(forgotten.done, "the lifter's un-log is lost on every device")
        // Final fix round (decision 3): the host reduces its own envelope, so its screen shows the un-log
        // that its own log, and every peer's, replays without: the precondition's breach made visible.
        #expect(!forgotten.shown, "the phone's own screen shows the un-log its log has lost")
    }

    @Test(
        """
        Finding 13 / decision 3: the documented loop (rebuild with replay whenever something is new) shows \
        replay's 185; reducing in arrival order (the control) shows 200
        """
    )
    func arrivalOrderReduce_divergesFromReplay() async throws {
        let target = Adv.env(
            .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 0), weight: pounds("200"), reps: nil),
            Adv.watch, seq: 1, at: 10
        )
        let log = Adv.env(Adv.logged(0, 0, pounds: "185", doneAt: 20), seq: 2, at: 20)
        var host = SimHost(Adv.phone, offset: 0)
        try await host.receive([Adv.start(), log])
        try await host.receive([target])
        #expect(Adv.row(host.state, 0, 0)?.weight == pounds("185"))
        #expect(host.replayMismatches == 0)
        // Control: the loop the round-1 docs described, reducing each new envelope in arrival order.
        let phone = Adv.state(after: [Adv.start(), log, target])
        let watch = Adv.state(after: [Adv.start(), target, log])
        #expect(Adv.row(phone, 0, 0)?.weight == pounds("200"))
        #expect(Adv.row(watch, 0, 0)?.weight == pounds("185"))
        #expect(Adv.row(WorkoutEngine.replay([Adv.start(), log, target]), 0, 0)?.weight == pounds("185"))
    }

    @Test(
        """
        Finding 13 / decision 3: a batch is rebuilt once, so one +30s is +30 s; rebuilding for one envelope \
        and then reducing a later one of the same batch (the control) applies it twice
        """
    )
    func rebuildThenReduceInOneBatch_appliesTwice() async throws {
        let applied = [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10)]
        let early = Adv.env(
            .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 1), weight: nil, reps: nil),
            Adv.watch,
            seq: 1,
            at: 5
        )
        let extend = Adv.env(Adv.extend(shown: true, tappedAt: 20), Adv.watch, seq: 2, at: 20)
        var host = SimHost(Adv.phone, offset: 0)
        try await host.receive(applied)
        try await host.receive([early, extend])
        #expect(host.state?.rest?.endsAt == engineTime(190))
        #expect(host.replayMismatches == 0)
        // Control, per envelope: rebuild when it sorts before the newest applied, else reduce.
        let store = InMemoryWorkoutEventStore()
        var state = try await WorkoutEngine.replay(store.append(applied))
        var newest = applied.max()
        for envelope in try await store.append([early, extend]) {
            if let current = newest, current < envelope {
                state = WorkoutEngine.reduce(state, envelope).0
            } else {
                state = await WorkoutEngine.replay(store.envelopes(for: Adv.workoutID))
            }
            newest = max(newest ?? envelope, envelope)
        }
        #expect(state?.rest?.endsAt == engineTime(220))
    }

    @Test(
        """
        Finding 14 / decision B: with the watch's clock 20 s ahead, a +30s tapped on the phone with 10 s left \
        is stamped after the rest's end, yet extends to 180 s as the lifter saw it, on both devices
        """
    )
    func hlcDraggedStamp_turnsAnExtendIntoARestart() async throws {
        var phone = SimHost(Adv.phone, offset: 0)
        var watch = SimHost(Adv.watch, offset: 20)
        try await watch.receive([phone.create(.started(EventBuilders.seedSession()), real: 0)])
        // Real 100 s: the phone logs bench set 1; the automatic 150 s rest ends at 250 s by the phone's clock.
        try await watch.receive([phone.create(Adv.logged(0, 0, doneAt: 100), real: 100)])
        // Real 232 s: the lifter turns the watch crown for set 2's weight; the watch stamps 252 s.
        let crown = WorkoutEvent.setTargetChanged(
            exerciseIndex: 0,
            setID: Adv.sid(0, 1),
            weight: pounds("190"),
            reps: nil
        )
        let turned = try await watch.create(crown, real: 232)
        #expect(turned.wallClock == engineTime(252))
        try await phone.receive([turned])
        // Real 240 s: the phone shows 10 s of rest left; the lifter taps +30s, and the phone says so.
        let rest = try #require(phone.state?.rest)
        #expect(rest.remaining(at: phone.now(240)) == .seconds(10))
        let event = WorkoutEvent.restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: phone.now(240))
        let tap = try await phone.create(event, real: 240)
        #expect(tap.wallClock == turned.wallClock.addingTimeInterval(0.001), "the stamp runs 12 s ahead of the phone")
        #expect(tap.wallClock > rest.endsAt, "stamped after the rest's end, as in finding 14")
        // Rule 9 as the lifter saw it: endsAt 280 s, total 180 s, on both devices; the ring keeps its place.
        let expected = RestTimer(endsAt: engineTime(280), total: .seconds(180))
        #expect(phone.state?.rest == expected)
        try await watch.receive([tap])
        #expect(watch.state?.rest == expected)
        let fraction = try #require(phone.state?.rest?.fraction(at: phone.now(240)))
        #expect(abs(fraction - 40.0 / 180.0) < 1e-12, "the ring jumped to \(fraction)")
    }
}
