import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2: minimal repros for the host-contract questions (findings 12–14). These document the
/// behaviour under each reading of the contract; they pass, and the findings ask which reading holds.
@Suite("WorkoutEngine · host contract (adversarial, round 2)", .tags(.domain))
struct HostContractAdversarialTests {
    typealias Adv = EngineAdv

    static let unlog = WorkoutEvent.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0))

    /// The phone logs set (0, 0) at 100 s, is killed and relaunched, its clock steps back 5 s, and it
    /// un-logs the set 2 s later. Returns whether the set is done after a replay of its log.
    static func relaunchThenUnlog(_ policy: HostPolicy) async throws -> (done: Bool, shown: Bool) {
        var phone = SimHost(Adv.phone, offset: 0, policy: policy)
        _ = try await phone.create(.started(EventBuilders.seedSession()), real: 0)
        _ = try await phone.create(Adv.logged(0, 0, doneAt: 100), real: 100)
        await phone.relaunch()
        phone.offset -= 5
        _ = try await phone.create(Self.unlog, real: 102)
        let replayed = await WorkoutEngine.replay(phone.log)
        return (Adv.row(replayed, 0, 0)?.isDone == true, Adv.row(phone.state, 0, 0)?.isDone == true)
    }

    @Test(
        """
        Finding 12 (documents): the HLC's newest stamp must survive a relaunch. Forgotten, the un-log after \
        a 5 s step back sorts before the log and the set is done again; recovered from the log, it stays undone
        """
    )
    func hlcAfterRelaunch_mustBeRecoveredFromTheLog() async throws {
        let forgotten = try await Self.relaunchThenUnlog(HostPolicy(recoverClock: false))
        #expect(forgotten.done, "the lifter's un-log is lost on every device")
        #expect(forgotten.shown, "the phone's own screen flips back as it rebuilds")
        let recovered = try await Self.relaunchThenUnlog(HostPolicy(recoverClock: true))
        #expect(!recovered.done)
        #expect(!recovered.shown)
    }

    @Test(
        """
        Finding 13 (documents): reducing what append returns in arrival order (StoringHost) is not replay. \
        P logs 185 at 20 s while W, partitioned, set 200 at 10 s; on healing P shows 200, W and replay 185
        """
    )
    func arrivalOrderReduce_divergesFromReplay() async throws {
        let target = Adv.env(
            .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 0), weight: pounds("200"), reps: nil),
            Adv.watch, seq: 1, at: 10
        )
        let log = Adv.env(Adv.logged(0, 0, pounds: "185", doneAt: 20), seq: 2, at: 20)
        var phone = StoringHost()
        _ = try await phone.receive([Adv.start(), log])
        _ = try await phone.receive([target])
        var watch = StoringHost()
        _ = try await watch.receive([Adv.start(), target])
        _ = try await watch.receive([log])
        #expect(Adv.row(phone.state, 0, 0)?.weight == pounds("200"))
        #expect(Adv.row(watch.state, 0, 0)?.weight == pounds("185"))
        #expect(try await Adv.row(phone.replayed(), 0, 0)?.weight == pounds("185"))
    }

    @Test(
        """
        Finding 13 (documents): a host that rebuilds from its store for one envelope of a batch, then reduces \
        a later one of the same batch, applies that one twice (+60 s for one +30s)
        """
    )
    func rebuildThenReduceInOneBatch_appliesTwice() async throws {
        let store = InMemoryEventStore()
        let applied = [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10)]
        var state = try await WorkoutEngine.replay(store.append(applied))
        var newest = applied.max()
        let early = Adv.env(
            .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 1), weight: nil, reps: nil),
            Adv.watch,
            seq: 1,
            at: 5
        )
        let extend = Adv.env(.restExtended(amount: .seconds(30)), Adv.watch, seq: 2, at: 20)
        // Per envelope: rebuild when it sorts before the newest applied, else reduce.
        for envelope in try await store.append([early, extend]) {
            if let current = newest, current < envelope {
                state = WorkoutEngine.reduce(state, envelope).0
            } else {
                state = await WorkoutEngine.replay(store.envelopes(for: Adv.workoutID))
            }
            newest = max(newest ?? envelope, envelope)
        }
        #expect(state?.rest?.endsAt == engineTime(220))
        #expect(await WorkoutEngine.replay(store.envelopes(for: Adv.workoutID))?.rest?.endsAt == engineTime(190))
    }

    @Test(
        """
        Finding 14 (documents): with the watch's clock 20 s ahead, a +30s tapped on the phone with 10 s left \
        on its screen is stamped after the rest's end, so it restarts a 30 s rest instead of extending to 180 s
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
        // Real 240 s: the phone shows 10 s of rest left; the lifter taps +30s.
        let rest = try #require(phone.state?.rest)
        #expect(rest.remaining(at: phone.now(240)) == .seconds(10))
        // Stamped with the phone's raw clock (before the amendment), the same tap extends as the lifter expects.
        let raw = Adv.env(.restExtended(amount: .seconds(30)), seq: 3, at: 240)
        #expect(WorkoutEngine.reduce(phone.state, raw).0?.rest == RestTimer(
            endsAt: engineTime(280),
            total: .seconds(180)
        ))
        let tap = try await phone.create(.restExtended(amount: .seconds(30)), real: 240)
        #expect(tap.wallClock == turned.wallClock.addingTimeInterval(0.001), "the stamp runs 12 s ahead of the phone")
        // Rule 9 as the lifter saw it: endsAt 280 s, total 180 s. What the engine does at the stamp:
        let after = try #require(phone.state?.rest)
        #expect(after.total == .seconds(30))
        #expect(after.endsAt == tap.wallClock.addingTimeInterval(30))
        #expect(after.fraction(at: phone.now(240)) == 1, "the ring jumps back to full")
    }
}
