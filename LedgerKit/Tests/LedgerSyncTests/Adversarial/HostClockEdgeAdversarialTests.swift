import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 3 at its edges: a system clock that is not finite ("the host never
/// produces a stamp that is not finite: if it cannot, it reports an issue and throws, and it never answers
/// `notStartable` for a snapshot the engine would start"), and stored stamps that are not finite or lie far
/// in the future (ADR-004, "Recovery skips only non-finite stamps").
@Suite("Adversarial F10 S2 · the host's clock at its edges", .tags(.sync), .timeLimit(.minutes(1)))
struct HostClockEdgeAdversarialTests {
    typealias Backing = SiegeRig.Backing

    /// How `call` ended on a host whose clock may be broken: its `LedgerSyncError`, or anything else in words.
    static func outcome(_ call: SeamCall, on host: LocalWorkoutSessionActor) async -> String {
        switch await Seam.outcome(of: call, on: host) {
        case .returned, .state: "returned"
        case let .refused(error): "\(error)"
        case let .threw(error): error
        }
    }

    @Test(
        "With a clock that is not finite a start is refused as the host's fault, never as notStartable",
        arguments: Seam.nonFinite
    )
    func start_nonFiniteClock_throwsNoFiniteStamp(reading: Date) async throws {
        let rig = try await SiegeRig.make(.memory)
        let host = await rig.host()
        let stream = await host.updates()
        rig.clock.set(reading)
        #expect(await Self.outcome(.start(Seam.session(1)), on: host) == "\(LedgerSyncError.noFiniteStamp)")
        #expect(try await host.current() == nil)
        #expect(await rig.siege.stored.isEmpty)
        rig.clock.set(Seam.at(0))
        try await host.start(Seam.session(1))
        #expect(await rig.siege.stored.map(\.seq) == [1])
        #expect(await Seam.buffered(stream).map(\.state) == [nil, Seam.session(1)])
    }

    @Test("With a clock that is not finite every change is refused and nothing moves", arguments: Seam.nonFinite)
    func calls_nonFiniteClock_changeNothing(reading: Date) async throws {
        let scene = try await SiegeScene.make(.memory)
        let before = await scene.siege.stored
        scene.rig.clock.set(reading)
        for call in [SeamCall.apply(scene.nextLog), .finish(SiegeScene.end), .discard(SiegeScene.end)] {
            #expect(await Self.outcome(call, on: scene.host) == "\(LedgerSyncError.noFiniteStamp)", "\(call)")
        }
        #expect(try await scene.host.current() == scene.live)
        #expect(await scene.siege.stored == before)
        #expect(await scene.heard().isEmpty)
        scene.rig.clock.set(Seam.at(0))
        try await scene.host.apply(scene.nextLog)
        let last = try #require(await scene.siege.stored.last)
        let newest = try #require(before.last)
        #expect(last.seq == newest.seq + 1)
        #expect(last.wallClock == newest.wallClock.addingTimeInterval(0.001))
    }

    /// A stored envelope of this device, seq 4, whose stamp is `stamp`.
    static func stray(_ stamp: Date) -> EventEnvelope {
        EventBuilders.envelope(Seam.logged(1, 0, in: 1, at: 300), seq: 4, at: stamp, workoutID: Seam.workout(1))
    }

    @Test(
        "A stored stamp that is not finite is skipped: the next stamps are finite and above the largest finite one",
        arguments: Backing.allCases,
        Seam.nonFinite
    )
    func stamps_storedNonFiniteStamp_isSkipped(backing: Backing, stamp: Date) async throws {
        let log = SiegeLogs.log(1, SiegeLogs.twoSets(in: 1)) + [Self.stray(stamp)]
        let rig = try await SiegeLogs.rig(backing, [log])
        let host = await rig.host()
        let resumed = try #require(try await host.resumeFromStore())
        #expect(resumed == WorkoutEngine.replay(SiegeLogs.log(1, SiegeLogs.twoSets(in: 1))), "the engine ignores it")
        rig.clock.set(Seam.at(-50))
        let after = try await host.apply(HostClockAdversarialTests.event(1))
        let stored = try #require(await rig.siege.stored.last)
        #expect(stored.seq == 5, "its seq is taken")
        #expect(stored.wallClock == Seam.at(2).addingTimeInterval(0.001))
        #expect(try await rig.replayed(Seam.workout(1)) == after)
    }

    @Test(
        "A stored stamp centuries ahead is kept as the newest: the host's next action still sorts after it",
        arguments: Backing.allCases
    )
    func stamps_storedFarFutureStamp_nextActionSortsAfter(backing: Backing) async throws {
        let future = Date.distantFuture
        let peer = EventBuilders.envelope(
            Seam.logged(0, 2, in: 1, at: 300), device: EventBuilders.watch, seq: 1, at: future,
            workoutID: Seam.workout(1)
        )
        let rig = try await SiegeLogs.rig(backing, [SiegeLogs.log(1, SiegeLogs.twoSets(in: 1)) + [peer]])
        let host = await rig.host()
        let unlog = WorkoutEvent.setUnlogged(exerciseIndex: 0, setID: Seam.setID(0, 2, in: 1))
        let after = try await host.apply(unlog)
        let stored = try #require(await rig.siege.stored.last)
        #expect(stored.wallClock == future.addingTimeInterval(0.001))
        #expect(after.exercises[0].sets[2].isDone == false)
        #expect(try await rig.replayed(Seam.workout(1)) == after, "the un-log is not replayed before the log")
    }

    @Test(
        "A log that replays to nothing still counts for the clock: stamps continue above it",
        arguments: Backing.allCases
    )
    func stamps_keptLog_countsForTheClock(backing: Backing) async throws {
        let kept = Array(SiegeLogs.finished(5, startedAt: Seam.at(90000)).dropFirst())
        let rig = try await SiegeLogs.rig(backing, [kept])
        let host = await rig.host()
        try await host.start(Seam.session(1))
        let newest = try #require(kept.map(\.wallClock).max())
        #expect(await rig.siege.stored.map(\.wallClock) == [newest.addingTimeInterval(0.001)])
    }
}
