import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 6: the recovery table, row by row. Each test leaves a log in the store
/// as a killed app would, builds a host, runs the launch step and reads the stores.
@Suite("Adversarial F10 S2 · recovery, row by row", .tags(.sync), .timeLimit(.minutes(1)))
struct HostRecoveryAdversarialTests {
    typealias Backing = SiegeRig.Backing

    @Test("Nothing stored: the step does nothing", arguments: Backing.allCases)
    func recovery_nothingStored_doesNothing(backing: Backing) async throws {
        let rig = try await SiegeLogs.rig(backing, [])
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == "no workout")
        #expect(try await host.current() == nil)
        #expect(await host.needsRecovery == false)
        #expect(await Set(rig.siege.calls).isDisjoint(with: SiegeLogs.writes))
    }

    @Test("A live log is resumed with the same sets, cursor and rest: no haptic, no write", arguments: Backing.allCases)
    func recovery_liveLog_resumesSilently(backing: Backing) async throws {
        let log = SiegeLogs.log(1, SiegeLogs.twoSets(in: 1))
        let rig = try await SiegeLogs.rig(backing, [log])
        let expected = try #require(WorkoutEngine.replay(log))
        #expect(expected.rest != nil && expected.cursor == Cursor(exerciseIndex: 0, setIndex: 2))
        let host = await rig.host()
        #expect(try await host.resumeFromStore() == expected)
        #expect(try await host.current() == expected)
        #expect(await Seam.buffered(host.updates()) == [WorkoutSessionUpdate(state: expected)])
        #expect(await Set(rig.siege.calls).isDisjoint(with: SiegeLogs.writes))
        #expect(try await rig.log(Seam.workout(1)) == log.sorted())
        #expect(await host.needsRecovery == false)
    }

    @Test("A finished log that was never saved is saved and compacted", arguments: Backing.allCases)
    func recovery_finishedLog_savesAndCompacts(backing: Backing) async throws {
        let log = SiegeLogs.finished(1)
        let rig = try await SiegeLogs.rig(backing, [log])
        let finished = try #require(WorkoutEngine.replay(log))
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == "no workout")
        #expect(try await rig.history() == [rig.asStored(finished)].compactMap(\.self))
        #expect(try await rig.uncompacted().isEmpty)
        #expect(try await host.current() == nil)
        #expect(await Seam.buffered(host.updates()) == [WorkoutSessionUpdate(state: nil)])
    }

    @Test(
        "A workout saved but not compacted is saved again with no change, then compacted",
        arguments: Backing.allCases
    )
    func recovery_savedNotCompacted_changesNothing(backing: Backing) async throws {
        let log = SiegeLogs.finished(1)
        let rig = try await SiegeLogs.rig(backing, [log])
        let finished = try #require(WorkoutEngine.replay(log))
        try await rig.workouts.materialize(finished, slotUpdates: [])
        let before = try await rig.history()
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == "no workout")
        #expect(try await rig.history() == before)
        #expect(before.count == 1)
        #expect(try await rig.uncompacted().isEmpty)
    }

    @Test("A discarded log is compacted, and nothing reaches history", arguments: Backing.allCases)
    func recovery_discardedLog_dropsIt(backing: Backing) async throws {
        let rig = try await SiegeLogs.rig(backing, [SiegeLogs.discarded(1)])
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == "no workout")
        #expect(try await rig.history().isEmpty)
        #expect(await rig.siege.saved.isEmpty)
        #expect(try await rig.uncompacted().isEmpty)
    }

    /// Three logs the engine replays to nothing: no `started`; a `started` for another workout; a `started`
    /// whose snapshot has ended.
    static var emptyLogs: [[EventEnvelope]] {
        var ended = Seam.session(7)
        ended.phase = .finished
        ended.endedAt = Seam.at(9)
        return [
            Array(SiegeLogs.finished(5).dropFirst()),
            [EventBuilders.envelope(.started(Seam.session(8)), seq: 1, at: Seam.at(0), workoutID: Seam.workout(6))],
            [EventBuilders.envelope(.started(ended), seq: 1, at: Seam.at(0), workoutID: Seam.workout(7))]
        ]
    }

    @Test("A log that replays to nothing is kept: no workout, no failure, no write", arguments: Backing.allCases)
    func recovery_logThatReplaysToNothing_isKept(backing: Backing) async throws {
        let rig = try await SiegeLogs.rig(backing, Self.emptyLogs)
        #expect(try await rig.truth().empty.count == 3)
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == "no workout")
        #expect(try await rig.uncompacted() == [Seam.workout(5), Seam.workout(6), Seam.workout(7)])
        #expect(try await rig.history().isEmpty)
        #expect(await Set(rig.siege.calls).isDisjoint(with: SiegeLogs.writes))
        #expect(await host.needsRecovery == false, "nothing a later foreground could do")
        try await host.start(Seam.session(1))
        #expect(try await host.current() == Seam.session(1))
    }

    @Test("Logs of every kind at once: each gets its row", arguments: Backing.allCases)
    func recovery_severalLogsAtOnce_eachGetsItsRow(backing: Backing) async throws {
        let live = SiegeLogs.log(1, SiegeLogs.twoSets(in: 1))
        let logs = [live, SiegeLogs.finished(2), SiegeLogs.discarded(3), SiegeLogs.finished(4)] + Self.emptyLogs
        let rig = try await SiegeLogs.rig(backing, logs)
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == SiegeLogs.name(1))
        #expect(try await host.current() == WorkoutEngine.replay(live))
        #expect(try await Set(rig.history().map(\.id)) == [Seam.workout(2), Seam.workout(4)])
        #expect(try await rig.uncompacted() == Set([1, 5, 6, 7].map(Seam.workout)))
        #expect(await Set(rig.siege.dropped) == Set([2, 3, 4].map(Seam.workout)))
        #expect(await rig.siege.dropped.count == 3, "each ended log is dropped once")
        #expect(await host.needsRecovery == false)
    }

    @Test("The step run twice, and twice at once, changes nothing", arguments: Backing.allCases)
    func recovery_runTwice_changesNothing(backing: Backing) async throws {
        let live = SiegeLogs.log(1, SiegeLogs.twoSets(in: 1))
        let rig = try await SiegeLogs.rig(backing, [live, SiegeLogs.finished(2), SiegeLogs.discarded(3)], yields: 2)
        let host = await rig.host()
        async let first = SiegeLogs.launch(host)
        async let second = SiegeLogs.launch(host)
        async let stream = host.updates()
        #expect(await [first, second] == [SiegeLogs.name(1), SiegeLogs.name(1)])
        let history = try await rig.history()
        #expect(await SiegeLogs.launch(host) == SiegeLogs.name(1))
        #expect(try await rig.history() == history)
        #expect(history.map(\.id) == [Seam.workout(2)])
        #expect(try await rig.uncompacted() == [Seam.workout(1)])
        #expect(await Seam.buffered(stream) == [WorkoutSessionUpdate(state: WorkoutEngine.replay(live))])
    }
}
