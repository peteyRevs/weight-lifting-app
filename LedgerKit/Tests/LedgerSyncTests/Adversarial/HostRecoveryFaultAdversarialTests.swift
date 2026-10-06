import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 6 beyond its table: a save that throws with other logs waiting, a
/// store that cannot be read, two live logs, and calls that arrive before or during the launch step
/// (criterion 1: "the first protocol call starts it, and every call waits for it").
@Suite("Adversarial F10 S2 · recovery under faults and callers", .tags(.sync), .timeLimit(.minutes(1)))
struct HostRecoveryFaultAdversarialTests {
    typealias Backing = SiegeRig.Backing

    static let live = SiegeLogs.log(1, SiegeLogs.twoSets(in: 1))

    @Test(
        "A save that throws keeps that log, carries on with the others, and the next pass finishes",
        arguments: Backing.allCases
    )
    func recovery_saveThrows_keepsTheLogAndCarriesOn(backing: Backing) async throws {
        let logs = [Self.live, SiegeLogs.finished(2), SiegeLogs.discarded(3), SiegeLogs.finished(4)]
        let rig = try await SiegeLogs.rig(backing, logs)
        let host = await rig.host()
        await rig.siege.fail(.materialize)
        #expect(await SiegeLogs.launch(host) == "materialize refuse")
        let saved = try await Set(rig.history().map(\.id))
        let kept = try await rig.uncompacted()
        #expect(saved.count == 1 && saved.isSubset(of: [Seam.workout(2), Seam.workout(4)]), "\(saved)")
        #expect(kept == Set([1, 2, 4].map(Seam.workout)).subtracting(saved), "the discarded log went all the same")
        #expect(await host.needsRecovery)
        #expect(try await host.current() == WorkoutEngine.replay(Self.live), "the live workout is resumed")
        #expect(await SiegeLogs.launch(host) == SiegeLogs.name(1))
        #expect(try await Set(rig.history().map(\.id)) == [Seam.workout(2), Seam.workout(4)])
        #expect(try await rig.uncompacted() == [Seam.workout(1)])
        #expect(await host.needsRecovery == false)
    }

    @Test(
        "A store that cannot be read: the step and current() throw, and the next call reads again",
        arguments: Backing.allCases
    )
    func recovery_storeCannotBeRead_theNextCallReadsAgain(backing: Backing) async throws {
        let rig = try await SiegeLogs.rig(backing, [Self.live])
        let host = await rig.host()
        await rig.siege.fail(.uncompactedWorkoutIDs, times: 2)
        #expect(await SiegeLogs.launch(host) == "uncompactedWorkoutIDs refuse")
        #expect(await host.needsRecovery)
        await #expect(throws: SiegeError.self) { try await host.current() }
        #expect(try await host.current() == WorkoutEngine.replay(Self.live))
        #expect(await host.needsRecovery == false)
    }

    @Test(
        "A stream opened while the store cannot be read is told of the workout once it can",
        arguments: Backing.allCases
    )
    func updates_storeCannotBeRead_isToldLater(backing: Backing) async throws {
        let rig = try await SiegeLogs.rig(backing, [Self.live])
        let host = await rig.host()
        await rig.siege.fail(.uncompactedWorkoutIDs)
        let stream = await host.updates()
        let resumed = try await host.current()
        #expect(resumed == WorkoutEngine.replay(Self.live))
        let heard = await Seam.buffered(stream)
        #expect(heard.last?.state == resumed, "\(heard.map(Seam.brief))")
        let isSilent = heard.allSatisfy(\.haptics.isEmpty)
        #expect(isSilent, "a resumed workout plays nothing")
    }

    /// Only a peer can bring two (F17); the host's documentation resumes the one that started last and keeps
    /// the other.
    @Test("Two live logs: the later start is resumed, the other is kept and comes back", arguments: Backing.allCases)
    func recovery_twoLiveLogs_resumesTheLaterStart(backing: Backing) async throws {
        let later = SiegeLogs.log(2, SiegeLogs.twoSets(in: 2), startedAt: Seam.at(500))
        let rig = try await SiegeLogs.rig(backing, [Self.live, later])
        let host = await rig.host()
        #expect(await SiegeLogs.launch(host) == SiegeLogs.name(2))
        #expect(try await rig.uncompacted() == [Seam.workout(1), Seam.workout(2)])
        #expect(try await rig.history().isEmpty)
        _ = try await host.finish(endedAt: SiegeScene.end)
        #expect(try await rig.history().map(\.id) == [Seam.workout(2)])
        #expect(try await rig.uncompacted() == [Seam.workout(1)], "the other log is never dropped unseen")
        let relaunched = await rig.host()
        #expect(await SiegeLogs.launch(relaunched) == SiegeLogs.name(1))
    }

    @Test("Before the launch step has run, the first call of each kind recovers first", arguments: Backing.allCases)
    func firstCall_beforeTheLaunchStep_recoversFirst(backing: Backing) async throws {
        let expected = try #require(WorkoutEngine.replay(Self.live))
        let calls: [SeamCall] = [
            .start(Seam.session(2)), .apply(Seam.logged(0, 2, in: 1, at: 420)), .finish(SiegeScene.end),
            .discard(SiegeScene.end)
        ]
        for call in calls {
            let rig = try await SiegeLogs.rig(backing, [Self.live, SiegeLogs.finished(3)])
            let host = await rig.host()
            var oracle = SeamOracle(live: expected)
            #expect(await Seam.outcome(of: call, on: host) == oracle.perform(call).outcome, "\(call)")
            #expect(try await host.current() == oracle.live, "\(call)")
            #expect(try await rig.history().contains { $0.id == Seam.workout(3) }, "\(call): the waiting save ran")
        }
        let rig = try await SiegeLogs.rig(backing, [Self.live])
        let host = await rig.host()
        #expect(await Seam.buffered(host.updates()) == [WorkoutSessionUpdate(state: expected)])
    }

    @Test("Calls that arrive while the launch step reads the store wait for it", arguments: Backing.allCases)
    func calls_duringRecovery_waitForIt(backing: Backing) async throws {
        let expected = try #require(WorkoutEngine.replay(Self.live))
        let rig = try await SiegeLogs.rig(backing, [Self.live])
        let host = await rig.host()
        await rig.siege.hold(.envelopes)
        async let launch = SiegeLogs.launch(host)
        await rig.siege.waitUntilHeld()
        async let current = host.current()
        async let stream = host.updates()
        async let start = Seam.outcome(of: .start(Seam.session(2)), on: host)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        await rig.siege.release()
        #expect(await launch == SiegeLogs.name(1))
        #expect(try await current == expected, "never \"no workout\" while a log waits to be read")
        #expect(await start == .refused(.workoutInProgress(Seam.workout(1))))
        #expect(await Seam.buffered(stream) == [WorkoutSessionUpdate(state: expected)])
        #expect(try await rig.uncompacted() == [Seam.workout(1)])
    }
}
