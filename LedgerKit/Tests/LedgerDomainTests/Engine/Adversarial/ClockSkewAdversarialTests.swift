import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Wall-clock ordering (ADR-004 rule 2) under realistic clock skew. Devices still converge (tested in
/// the convergence properties); these tests ask whether they converge on what the lifter did.
@Suite("WorkoutEngine · clock skew (adversarial)", .tags(.domain))
struct ClockSkewAdversarialTests {
    typealias Adv = EngineAdv

    @Test(
        "'No lost sets': the phone logs a set the watch added, its clock 10 s behind — the set stays done."
    )
    func logOfPeerAddedSet_behindClock_isKept() throws {
        let id = SetID(EventBuilders.uuid(0xADD))
        let added = LoggedSet(id: id, weight: pounds("60"), reps: Reps(clamping: 8), kind: .added)
        // Real time: watch adds at 100; the phone sees it and logs it at 105, but its clock reads 95.
        let add = Adv.env(.setAdded(exerciseIndex: 1, set: added), Adv.watch, seq: 1, at: 100)
        let log = Adv.env(.setLogged(
            exerciseIndex: 1,
            setID: id,
            weight: pounds("60"),
            reps: Reps(clamping: 8),
            doneAt: engineTime(95)
        ), Adv.phone, seq: 2, at: 95)
        // The phone applied them in causal order and showed the set done.
        #expect(Adv.state(after: [Adv.start(), add, log]).map { $0.exercises[1].sets.last?.isDone } == true)
        let merged = try #require(WorkoutEngine.replay([Adv.start(), add, log]))
        #expect(merged.exercises[1].sets.last?.isDone == true, "the logged set was lost on replay")
    }

    @Test("A device's own later un-log survives replay when its clock stepped back between the two (NTP correction).")
    func ownUnlogAfterClockStepBack_isKept() throws {
        let log = Adv.env(Adv.logged(0, 0, doneAt: 100), seq: 2, at: 100)
        let unlog = Adv.env(.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)), seq: 3, at: 98)
        // Live, the phone applied seq 2 then seq 3: the set is undone.
        #expect(Adv.row(Adv.state(after: [Adv.start(), log, unlog]), 0, 0)?.isDone == false)
        // After a relaunch the phone replays its own log (ADR-004 rule 6).
        let replayed = try #require(WorkoutEngine.replay([Adv.start(), log, unlog]))
        #expect(replayed.exercises[0].sets[0].isDone == false, "resume flipped the lifter's own un-log")
    }

    @Test("Cross-device: the phone un-logs a set it saw the watch log; a phone clock 5 s behind resurrects it.")
    func unlogOfPeerLog_behindClock_isKept() throws {
        let log = Adv.env(Adv.logged(0, 0, doneAt: 100), Adv.watch, seq: 1, at: 100)
        let unlog = Adv.env(.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)), Adv.phone, seq: 2, at: 95)
        let merged = try #require(WorkoutEngine.replay([Adv.start(), log, unlog]))
        #expect(merged.exercises[0].sets[0].isDone == false, "the phone's un-log was reordered before the log it undid")
    }
}
