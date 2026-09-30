import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Wall-clock ordering (ADR-004 rule 2) under realistic clock skew. Devices still converge (tested in
/// the convergence properties); these tests ask whether they converge on what the lifter did.
///
/// Envelopes are stamped with the hybrid logical clock of ADR-004's amendment (2026-09-29), as the host
/// stamps them (F10/F17). The last test keeps the raw-clock stamps HLC replaces, as documentation of
/// that precondition.
@Suite("WorkoutEngine · clock skew (adversarial)", .tags(.domain))
struct ClockSkewAdversarialTests {
    typealias Adv = EngineAdv

    static let addedID = SetID(EventBuilders.uuid(0xADD))

    /// "+ Add set" on exercise 1, with `addedID`.
    static let addSet = WorkoutEvent.setAdded(
        exerciseIndex: 1,
        set: LoggedSet(id: addedID, weight: pounds("60"), reps: Reps(clamping: 8), kind: .added)
    )

    /// "Done" on the added set, ticked at `doneAt` seconds by the ticking device's clock.
    static func logAddedSet(doneAt seconds: Double) -> WorkoutEvent {
        .setLogged(
            exerciseIndex: 1,
            setID: addedID,
            weight: pounds("60"),
            reps: Reps(clamping: 8),
            doneAt: engineTime(seconds)
        )
    }

    static let unlogSet = WorkoutEvent.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0))

    @Test(
        "'No lost sets': the phone logs a set the watch added, its clock 10 s behind — the set stays done."
    )
    func logOfPeerAddedSet_behindClock_isKept() throws {
        var phone = HLCDevice(Adv.phone)
        var watch = HLCDevice(Adv.watch)
        let start = phone.record(.started(EventBuilders.seedSession()), clock: 0)
        watch.receive(start)
        // Real time: the watch adds at 100; the phone sees it and logs it at 105, but its clock reads 95.
        let add = watch.record(Self.addSet, clock: 100)
        phone.receive(add)
        let log = phone.record(Self.logAddedSet(doneAt: 95), clock: 95)
        #expect(log.wallClock == add.wallClock.addingTimeInterval(0.001), "HLC stamps it after the add it saw")
        // The phone applied them in causal order and showed the set done.
        #expect(Adv.state(after: [start, add, log]).map { $0.exercises[1].sets.last?.isDone } == true)
        let merged = try #require(WorkoutEngine.replay([start, add, log]))
        #expect(merged.exercises[1].sets.last?.isDone == true, "the logged set was lost on replay")
    }

    @Test("A device's own later un-log survives replay when its clock stepped back between the two (NTP correction).")
    func ownUnlogAfterClockStepBack_isKept() throws {
        var phone = HLCDevice(Adv.phone)
        let start = phone.record(.started(EventBuilders.seedSession()), clock: 0)
        let log = phone.record(Adv.logged(0, 0, doneAt: 100), clock: 100)
        let unlog = phone.record(Self.unlogSet, clock: 98)
        #expect(log < unlog, "HLC keeps the device's own seq order")
        // Live, the phone applied seq 2 then seq 3: the set is undone.
        #expect(Adv.row(Adv.state(after: [start, log, unlog]), 0, 0)?.isDone == false)
        // After a relaunch the phone replays its own log (ADR-004 rule 6).
        let replayed = try #require(WorkoutEngine.replay([start, log, unlog]))
        #expect(replayed.exercises[0].sets[0].isDone == false, "resume flipped the lifter's own un-log")
    }

    @Test("Cross-device: the phone un-logs a set it saw the watch log; a phone clock 5 s behind cannot resurrect it.")
    func unlogOfPeerLog_behindClock_isKept() throws {
        var phone = HLCDevice(Adv.phone)
        var watch = HLCDevice(Adv.watch)
        let start = phone.record(.started(EventBuilders.seedSession()), clock: 0)
        watch.receive(start)
        let log = watch.record(Adv.logged(0, 0, doneAt: 100), clock: 100)
        phone.receive(log)
        let unlog = phone.record(Self.unlogSet, clock: 95)
        let merged = try #require(WorkoutEngine.replay([start, log, unlog]))
        #expect(merged.exercises[0].sets[0].isDone == false, "the phone's un-log was reordered before the log it undid")
    }

    @Test(
        """
        HLC precondition violated (the raw skewed clocks of the three tests above): devices still converge, \
        but on stamp order, so each causally later action loses.
        """
    )
    func withoutHLCPrecondition_rawSkewedStamps_convergeOnStampOrder() throws {
        let added = Adv.env(Self.addSet, Adv.watch, seq: 1, at: 100)
        let logAdded = Adv.env(Self.logAddedSet(doneAt: 95), Adv.phone, seq: 2, at: 95)
        let ownLog = Adv.env(Adv.logged(0, 0, doneAt: 100), seq: 2, at: 100)
        let ownUnlog = Adv.env(Self.unlogSet, seq: 3, at: 98)
        let peerLog = Adv.env(Adv.logged(0, 0, doneAt: 100), Adv.watch, seq: 1, at: 100)
        let peerUnlog = Adv.env(Self.unlogSet, Adv.phone, seq: 2, at: 95)
        // The log of the added set sorts before the add: it hits no row, and the set is never done.
        let lostLog = try PartitionRaceAdversarialTests.expectConvergence([Adv.start(), added, logAdded])
        #expect(lostLog.exercises[1].sets.last?.isDone == false)
        // Each un-log sorts before the log it undid, so the set is done again.
        for log in [[Adv.start(), ownLog, ownUnlog], [Adv.start(), peerLog, peerUnlog]] {
            let lostUnlog = try PartitionRaceAdversarialTests.expectConvergence(log)
            #expect(lostUnlog.exercises[0].sets[0].isDone == true)
        }
    }
}
