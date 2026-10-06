import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, re-entrancy: a caller that is cancelled before, during or after its call (a
/// screen that closes, a scene-phase task). Its event is stored once or not at all, never half: the log, the
/// host's memory, every stream and history agree afterwards. The host's documentation promises more ("a
/// caller that is cancelled still gets its event stored, and only waits"), and that is what is expected here.
@Suite("Adversarial F10 S2 · callers that are cancelled", .tags(.sync), .timeLimit(.minutes(1)))
struct HostCancellationAdversarialTests {
    typealias Backing = SiegeRig.Backing

    enum Moment: String, Sendable, CaseIterable, CustomStringConvertible {
        /// The task is cancelled before it has run.
        case before
        /// The task is cancelled while its store call is in flight.
        case during
        /// The task is cancelled once its call has returned.
        case after

        var description: String {
            rawValue
        }
    }

    /// Makes `call` on the scene's host from a task that is cancelled at `moment`, parking `held` meanwhile
    /// when the moment is `.during`, and returns how the call ended.
    static func cancelled(
        _ call: SeamCall,
        at moment: Moment,
        holding held: SiegeCall,
        in scene: SiegeScene
    ) async -> SeamOutcome {
        if moment == .during {
            await scene.siege.hold(held)
        }
        let task = Task { await Seam.outcome(of: call, on: scene.host) }
        switch moment {
        case .before:
            task.cancel()
        case .during:
            await scene.siege.waitUntilHeld()
            task.cancel()
            await scene.siege.release()
        case .after:
            _ = await task.value
            task.cancel()
        }
        return await task.value
    }

    @Test("A cancelled apply is stored once, returned and published once", arguments: Backing.allCases, Moment.allCases)
    func apply_cancelledCaller_isStoredOnce(backing: Backing, moment: Moment) async throws {
        let scene = try await SiegeScene.make(backing)
        let expected = try #require(scene.update(after: scene.nextLog))
        let outcome = await Self.cancelled(.apply(scene.nextLog), at: moment, holding: .append, in: scene)
        #expect(outcome == .state(expected.state ?? scene.live))
        #expect(await scene.siege.stored.count { $0.event == scene.nextLog } == 1)
        #expect(try await scene.host.current() == expected.state)
        #expect(try await scene.rig.replayed(scene.live.id) == expected.state)
        #expect(await scene.heard() == [expected])
    }

    @Test("A cancelled finish saves the workout once and ends it once", arguments: Backing.allCases, Moment.allCases)
    func finish_cancelledCaller_savesOnce(backing: Backing, moment: Moment) async throws {
        let scene = try await SiegeScene.make(backing)
        let finished = try #require(scene.finished)
        let outcome = await Self.cancelled(.finish(SiegeScene.end), at: moment, holding: .materialize, in: scene)
        #expect(outcome == .state(finished))
        #expect(try await scene.rig.history() == [scene.rig.asStored(finished)].compactMap(\.self))
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(try await scene.host.current() == nil)
        #expect(await scene.heard().map(\.state) == [finished])
    }

    @Test(
        "A cancelled discard drops the log once and ends the workout once",
        arguments: Backing.allCases,
        Moment.allCases
    )
    func discard_cancelledCaller_dropsOnce(backing: Backing, moment: Moment) async throws {
        let scene = try await SiegeScene.make(backing)
        let outcome = await Self.cancelled(.discard(SiegeScene.end), at: moment, holding: .compact, in: scene)
        #expect(outcome == .returned)
        #expect(try await scene.rig.history().isEmpty)
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(try await scene.host.current() == nil)
        #expect(await scene.heard().map(\.state?.phase) == [.discarded])
    }

    @Test("A cancelled start is stored once and is the live workout", arguments: Backing.allCases, Moment.allCases)
    func start_cancelledCaller_startsOnce(backing: Backing, moment: Moment) async throws {
        let scene = try await SiegeScene.make(backing)
        try await scene.host.discard(endedAt: SiegeScene.end)
        let outcome = await Self.cancelled(.start(Seam.session(2)), at: moment, holding: .append, in: scene)
        #expect(outcome == .returned)
        #expect(try await scene.host.current() == Seam.session(2))
        #expect(try await scene.rig.log(Seam.workout(2)).map(\.event) == [.started(Seam.session(2))])
    }

    @Test(
        "A launch step whose caller is cancelled while it reads the store still recovers",
        arguments: Backing.allCases
    )
    func recovery_cancelledCaller_stillRecovers(backing: Backing) async throws {
        let logs = [SiegeLogs.log(1, SiegeLogs.twoSets(in: 1)), SiegeLogs.finished(2), SiegeLogs.discarded(3)]
        let rig = try await SiegeLogs.rig(backing, logs)
        let host = await rig.host()
        await rig.siege.hold(.envelopes)
        let launch = Task { await SiegeLogs.launch(host) }
        await rig.siege.waitUntilHeld()
        launch.cancel()
        await rig.siege.release()
        #expect(await launch.value == SiegeLogs.name(1))
        #expect(try await host.current() == WorkoutEngine.replay(logs[0]))
        #expect(try await rig.history().map(\.id) == [Seam.workout(2)])
        #expect(try await rig.uncompacted() == [Seam.workout(1)])
        #expect(await host.needsRecovery == false)
    }

    /// Criterion 10: "An ended subscriber is dropped when a publication finds it ended."
    @Test("Subscribers that stop reading or drop their stream cost the others nothing", arguments: Backing.allCases)
    func updates_subscribersThatLeave_costTheOthersNothing(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        for stream in scene.streams.prefix(4) {
            #expect(await Seam.buffered(stream) == [WorkoutSessionUpdate(state: scene.live)])
        }
        for _ in 0 ..< 200 {
            _ = await scene.host.updates()
        }
        let first = try #require(scene.update(after: scene.nextLog))
        try await scene.host.apply(scene.nextLog)
        let marked = try await scene.host.apply(Seam.markEvent(3))
        let expected = [WorkoutSessionUpdate(state: scene.live), first, WorkoutSessionUpdate(state: marked)]
        #expect(await Seam.buffered(scene.streams[5]) == expected)
        #expect(await Seam.buffered(scene.host.updates()) == [WorkoutSessionUpdate(state: marked)])
        #expect(await Seam.buffered(scene.streams[0]).isEmpty, "a stream that ended stays ended")
    }

    @Test(
        "current() from a cancelled task on a host that has not recovered never answers \"no workout\"",
        arguments: Backing.allCases
    )
    func current_cancelledCallerBeforeRecovery_isNeverWrong(backing: Backing) async throws {
        let log = SiegeLogs.log(1, SiegeLogs.twoSets(in: 1))
        let rig = try await SiegeLogs.rig(backing, [log])
        let host = await rig.host()
        let reading = Task { try await host.current() }
        reading.cancel()
        let answer = await reading.result
        #expect(try answer.get() == WorkoutEngine.replay(log))
        #expect(try await host.current() == WorkoutEngine.replay(log))
    }
}
