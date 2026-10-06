import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 6's row "a log with rows this version cannot read | live: resumes
/// from what it reads; ended: keeps it", on the GRDB store with a row of a later payload version, and what
/// the protocol documents for it: `finish` throws `incompleteLog` and the workout stays live; a discard ends
/// it and keeps the log.
@Suite("Adversarial F10 S2 · a log with rows this version cannot read", .tags(.sync), .timeLimit(.minutes(1)))
struct HostIncompleteLogAdversarialTests {
    static let workout = Seam.workout(1)

    /// A database whose log of workout 1 is `log` with the row of `seq` unreadable.
    static func rig(_ log: [EventEnvelope], unreadable seq: UInt64) async throws -> SiegeRig {
        let rig = try await SiegeLogs.rig(.database, [log])
        try await rig.makeUnreadable(workout, seq: seq)
        #expect(try await rig.events.unreadableCount(for: workout) == 1)
        return rig
    }

    static let live = SiegeLogs.log(1, SiegeLogs.twoSets(in: 1) + [Seam.logged(0, 2, in: 1, at: 420)])

    @Test("A live log with an unreadable row in the middle is resumed from the rows it can read")
    func recovery_liveLogWithAnUnreadableRow_resumesFromTheRest() async throws {
        let rig = try await Self.rig(Self.live, unreadable: 3)
        let readable = Self.live.filter { $0.seq != 3 }
        let host = await rig.host()
        #expect(try await host.resumeFromStore() == WorkoutEngine.replay(readable))
        #expect(try await rig.events.envelopes(for: Self.workout).count == 3)
        #expect(await host.needsRecovery == false)
    }

    @Test("finish on such a log throws incompleteLog, stores no end, and the workout goes on and survives a relaunch")
    func finish_incompleteLog_storesNoEndAndStaysLive() async throws {
        let rig = try await Self.rig(Self.live, unreadable: 3)
        let host = await rig.host()
        let before = try #require(try await host.resumeFromStore())
        let stream = await host.updates()
        #expect(await Seam.outcome(of: .finish(SiegeScene.end), on: host) == .refused(.incompleteLog(Self.workout)))
        #expect(try await rig.log(Self.workout).contains { $0.event.isTerminal } == false, "no end in the log")
        #expect(try await host.current() == before)
        #expect(try await rig.history().isEmpty)
        let event = Seam.logged(1, 0, in: 1, at: 600)
        let after = try await host.apply(event)
        #expect(after == Seam.update(after: event, on: before)?.state)
        #expect(await rig.siege.stored.last?.seq == 5, "the unreadable row's seq is taken")
        #expect(await Seam.buffered(stream).map(\.state) == [before, after])
        let relaunched = await rig.host()
        #expect(try await relaunched.resumeFromStore() == after, "nothing the lifter logged is lost")
    }

    @Test("A discard ends such a workout and keeps its log for a version that reads it")
    func discard_incompleteLog_endsTheWorkoutAndKeepsTheLog() async throws {
        let rig = try await Self.rig(Self.live, unreadable: 3)
        let host = await rig.host()
        let before = try #require(try await host.resumeFromStore())
        let stream = await host.updates()
        try await host.discard(endedAt: SiegeScene.end)
        #expect(try await host.current() == nil)
        let ending = Seam.update(after: .discarded(endedAt: SiegeScene.end), on: before)
        #expect(await Seam.buffered(stream) == [WorkoutSessionUpdate(state: before), ending].compactMap(\.self))
        #expect(try await rig.uncompacted() == [Self.workout], "the log is kept")
        #expect(try await rig.events.unreadableCount(for: Self.workout) == 1)
        #expect(try await rig.history().isEmpty)
        #expect(await host.needsRecovery == false)
        try await host.start(Seam.session(2))
        let relaunched = await rig.host()
        #expect(try await relaunched.resumeFromStore() == Seam.session(2))
        #expect(try await rig.uncompacted() == [Self.workout, Seam.workout(2)])
        #expect(await relaunched.needsRecovery == false)
    }

    @Test(
        "An ended log with an unreadable row is kept at launch: not saved, not dropped, no failure",
        arguments: [SiegeLogs.finished(1), SiegeLogs.discarded(1)]
    )
    func recovery_endedLogWithAnUnreadableRow_isKept(log: [EventEnvelope]) async throws {
        let rig = try await Self.rig(log, unreadable: 2)
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == "no workout")
        #expect(try await rig.uncompacted() == [Self.workout])
        #expect(try await rig.history().isEmpty)
        #expect(await Set(rig.siege.calls).isDisjoint(with: SiegeLogs.writes))
        #expect(await host.needsRecovery == false, "a later foreground could do no more")
        try await host.start(Seam.session(2))
        #expect(try await host.current() == Seam.session(2))
    }

    @Test("A log whose started row is unreadable replays to nothing and is kept")
    func recovery_unreadableStart_isKept() async throws {
        let rig = try await Self.rig(Self.live, unreadable: 1)
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == "no workout")
        #expect(try await rig.uncompacted() == [Self.workout])
        #expect(await host.needsRecovery == false)
    }

    @Test("The row a finish wrote is unreadable: the workout resumes as live, and its next seq is above that row")
    func recovery_unreadableEnd_resumesAndTakesTheNextSeq() async throws {
        let rig = try await Self.rig(SiegeLogs.finished(1), unreadable: 4)
        let host = await rig.host()
        let resumed = try #require(try await host.resumeFromStore())
        #expect(resumed == WorkoutEngine.replay(SiegeLogs.log(1, SiegeLogs.twoSets(in: 1))))
        try await host.apply(Seam.logged(0, 2, in: 1, at: 420))
        #expect(await rig.siege.stored.last?.seq == 5)
        #expect(await Seam.outcome(of: .finish(SiegeScene.end), on: host) == .refused(.incompleteLog(Self.workout)))
    }
}
