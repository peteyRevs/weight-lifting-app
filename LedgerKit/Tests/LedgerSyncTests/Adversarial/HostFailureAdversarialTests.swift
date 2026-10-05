import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 2: a store that refuses an append, or stores it and loses the
/// answer. "If the store refuses the append, the call throws and nothing changes: no state, no clock, no
/// `seq`, no update." Expected stamps are the brief's formula computed here.
@Suite("Adversarial F10 S2 · an append that fails", .tags(.sync), .timeLimit(.minutes(1)))
struct HostFailureAdversarialTests {
    typealias Backing = SiegeRig.Backing

    @Test("A refused append changes nothing: no state, no seq, no clock, no update", arguments: Backing.allCases)
    func apply_appendRefused_changesNothing(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        let before = try await scene.rig.log(scene.live.id)
        // The refused call reads a clock far ahead; had it moved the host's clock, the next stamp would show it.
        scene.rig.clock.advance(5000)
        await scene.siege.fail(.append)
        #expect(await SiegeScene.outcome(.apply(scene.nextLog), on: scene.host) == "append refuse")
        #expect(try await scene.host.current() == scene.live)
        #expect(try await scene.rig.log(scene.live.id) == before)
        scene.rig.clock.advance(-5000)
        let after = try await scene.host.apply(scene.nextLog)
        let log = try await scene.rig.log(scene.live.id)
        let newest = try #require(before.last)
        #expect(log.map(\.seq) == [1, 2, 3, 4])
        #expect(log.last?.wallClock == max(scene.rig.clock.now, newest.wallClock.addingTimeInterval(0.001)))
        #expect(after == scene.update(after: scene.nextLog)?.state)
        #expect(await scene.heard() == [scene.update(after: scene.nextLog)].compactMap(\.self))
    }

    @Test("An append that is stored and reported as failed counts once", arguments: Backing.allCases)
    func apply_appendAnswerLost_theEventIsAppliedOnce(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        await scene.siege.fail(.append, .loseAnswer)
        #expect(await SiegeScene.outcome(.apply(scene.nextLog), on: scene.host) == "append loseAnswer")
        let expected = try #require(scene.update(after: scene.nextLog)?.state)
        #expect(try await scene.rig.replayed(scene.live.id) == expected)
        #expect(try await scene.host.current() == expected, "memory follows the store")
        let marked = try await scene.host.apply(Seam.markEvent(1))
        let log = try await scene.rig.log(scene.live.id)
        #expect(log.map(\.seq) == [1, 2, 3, 4, 5])
        #expect(log.count(where: { $0.event == scene.nextLog }) == 1)
        #expect(try await scene.rig.replayed(scene.live.id) == marked)
        let heard = await scene.heard()
        #expect(heard.map(\.state) == [expected, marked], "each change reaches a stream once")
    }

    @Test("A start whose append is refused starts nothing, and the next start is seq 1", arguments: Backing.allCases)
    func start_appendRefused_startsNothing(backing: Backing) async throws {
        let rig = try await SiegeRig.make(backing)
        let host = await rig.host()
        let stream = await host.updates()
        await rig.siege.fail(.append)
        #expect(await SiegeScene.outcome(.start(Seam.session(1)), on: host) == "append refuse")
        #expect(try await host.current() == nil)
        #expect(try await rig.uncompacted().isEmpty)
        try await host.start(Seam.session(2))
        #expect(try await rig.log(Seam.workout(2)).map(\.seq) == [1])
        #expect(await Seam.buffered(stream).map(\.state) == [nil, Seam.session(2)])
    }

    @Test("A start that is stored and reported as failed is the live workout", arguments: Backing.allCases)
    func start_appendAnswerLost_theWorkoutIsLive(backing: Backing) async throws {
        let rig = try await SiegeRig.make(backing)
        let host = await rig.host()
        await rig.siege.fail(.append, .loseAnswer)
        #expect(await SiegeScene.outcome(.start(Seam.session(1)), on: host) == "append loseAnswer")
        let second = await Seam.outcome(of: .start(Seam.session(2)), on: host)
        #expect(second == .refused(.workoutInProgress(Seam.workout(1))))
        #expect(try await host.current() == Seam.session(1))
        #expect(try await rig.uncompacted() == [Seam.workout(1)], "no second log")
        let logged = try await host.apply(Seam.logged(0, 0, in: 1))
        #expect(try await rig.log(Seam.workout(1)).map(\.seq) == [1, 2])
        #expect(try await rig.replayed(Seam.workout(1)) == logged)
    }

    @Test("A finish whose append is refused leaves the workout live and usable", arguments: Backing.allCases)
    func finish_appendRefused_theWorkoutStaysLive(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        await scene.siege.fail(.append)
        #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host) == "append refuse")
        #expect(try await scene.host.current() == scene.live)
        #expect(try await scene.rig.history().isEmpty)
        #expect(try await scene.storedEvents().contains(.finished(endedAt: SiegeScene.end)) == false)
        let after = try await scene.host.apply(scene.nextLog)
        #expect(try await scene.rig.replayed(scene.live.id) == after)
        #expect(await scene.heard().map(\.state) == [after])
    }

    @Test(
        "A finish that is stored and reported as failed is saved once, with one ending update",
        arguments: Backing.allCases
    )
    func finish_appendAnswerLost_theWorkoutIsSavedOnce(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        let finished = try #require(scene.finished)
        await scene.siege.fail(.append, .loseAnswer)
        #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host) == "append loseAnswer")
        #expect(try await scene.rig.replayed(scene.live.id) == finished, "the end is in the log")
        // Whatever the lifter does next, the workout that ended is saved and never applied to again.
        #expect(await SiegeScene.outcome(.apply(scene.nextLog), on: scene.host) == "noLiveWorkout")
        #expect(try await scene.host.current() == nil)
        #expect(try await scene.rig.history() == [scene.rig.asStored(finished)].compactMap(\.self))
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(await scene.heard().map(\.state) == [finished])
        #expect(await scene.siege.stored.count(where: { $0.event.isTerminal }) == 1)
    }
}
