import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criteria 4 and 5: the save or the compaction fails once the end is stored.
/// "If the save fails, `finish` throws, the log is kept, nothing is lost, and no ending update is published
/// until a save succeeds: a second `finish` retries it and publishes once, and so does the launch step."
/// Between the failure and the retry the protocol's documentation has every reader go on seeing the workout
/// as it stood, and a later `apply` or `discard` complete the end first.
@Suite("Adversarial F10 S2 · a save or a compaction that fails", .tags(.sync), .timeLimit(.minutes(1)))
struct HostEndFailureAdversarialTests {
    typealias Backing = SiegeRig.Backing

    /// A scene whose `finish` has just failed at `call`, `times` times in a row counting that one.
    static func failedFinish(
        _ backing: Backing,
        at call: SiegeCall = .materialize,
        times: Int = 1
    ) async throws -> SiegeScene {
        let scene = try await SiegeScene.make(backing)
        await scene.siege.fail(call, times: times)
        let outcome = await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host)
        #expect(outcome == "\(call.rawValue) refuse")
        return scene
    }

    /// The scene's workout is in history once, as the engine finished it at `SiegeScene.end`, and its log
    /// is gone.
    static func expectSavedOnce(_ scene: SiegeScene) async throws {
        let finished = try #require(scene.finished)
        #expect(try await scene.rig.history() == [scene.rig.asStored(finished)].compactMap(\.self))
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(try await scene.host.current() == nil)
        #expect(await scene.host.updates().first { _ in true } == WorkoutSessionUpdate(state: nil))
    }

    @Test(
        "A failed save: finish throws, the end is in the log, and every reader sees the workout as it stood",
        arguments: Backing.allCases
    )
    func finish_saveFails_nothingIsPublished(backing: Backing) async throws {
        let scene = try await Self.failedFinish(backing)
        #expect(try await scene.rig.replayed(scene.live.id) == scene.finished, "nothing is lost")
        #expect(try await scene.rig.history().isEmpty)
        #expect(try await scene.host.current() == scene.live)
        #expect(await scene.host.updates().first { _ in true } == WorkoutSessionUpdate(state: scene.live))
        let other = await Seam.outcome(of: .start(Seam.session(2)), on: scene.host)
        #expect(other == .refused(.workoutInProgress(scene.live.id)), "no second workout over an unsaved one")
        #expect(await scene.heard().isEmpty, "no ending update until a save succeeds")
        #expect(try await scene.rig.uncompacted() == [scene.live.id])
    }

    @Test(
        "A second finish retries the save, returns the first end date and publishes one ending update",
        arguments: Backing.allCases
    )
    func finish_afterAFailedSave_savesWithTheFirstEndDate(backing: Backing) async throws {
        let scene = try await Self.failedFinish(backing)
        let returned = try await scene.host.finish(endedAt: SiegeScene.end.addingTimeInterval(900))
        #expect(returned == scene.finished, "ended when the first call said")
        try await Self.expectSavedOnce(scene)
        #expect(await scene.heard() == [scene.update(after: .finished(endedAt: SiegeScene.end))].compactMap(\.self))
        #expect(await scene.siege.stored.count(where: { $0.event.isTerminal }) == 1, "one end in the log, ever")
        // And it stays ended: no call and no recovery publishes anything more.
        #expect(await Seam.outcome(of: .finish(SiegeScene.end), on: scene.host) == .refused(.noLiveWorkout))
        #expect(try await scene.host.resumeFromStore() == nil)
        #expect(await scene.heard().count == 1)
    }

    @Test("Three failed saves in a row publish nothing; the fourth finish saves once", arguments: Backing.allCases)
    func finish_saveFailsThreeTimes_thenSavesOnce(backing: Backing) async throws {
        let scene = try await Self.failedFinish(backing, times: 3)
        for _ in 0 ..< 2 {
            #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host) == "materialize refuse")
            #expect(try await scene.host.current() == scene.live)
        }
        #expect(await scene.heard().isEmpty)
        #expect(try await scene.host.finish(endedAt: SiegeScene.end) == scene.finished)
        try await Self.expectSavedOnce(scene)
        #expect(await scene.heard().map(\.state) == [scene.finished])
        #expect(await scene.siege.stored.count(where: { $0.event.isTerminal }) == 1)
    }

    @Test(
        "While the save keeps failing, an apply throws the store's error and stores nothing after the end",
        arguments: Backing.allCases
    )
    func apply_whileTheSaveFails_storesNothing(backing: Backing) async throws {
        let scene = try await Self.failedFinish(backing, times: 2)
        let before = try await scene.storedEvents()
        #expect(await SiegeScene.outcome(.apply(scene.nextLog), on: scene.host) == "materialize refuse")
        #expect(try await scene.storedEvents() == before)
        #expect(try await scene.host.current() == scene.live)
        #expect(await scene.heard().isEmpty)
    }

    @Test(
        "Once the store works, an apply completes the end first and is refused: the workout is saved without it",
        arguments: Backing.allCases
    )
    func apply_afterAFailedSave_completesTheEndAndIsRefused(backing: Backing) async throws {
        let scene = try await Self.failedFinish(backing)
        #expect(await Seam.outcome(of: .apply(scene.nextLog), on: scene.host) == .refused(.noLiveWorkout))
        try await Self.expectSavedOnce(scene)
        #expect(await scene.heard().map(\.state) == [scene.finished])
        #expect(await scene.siege.stored.contains { $0.event == scene.nextLog } == false)
    }

    @Test("The launch step completes a failed save: one ending update, without a haptic", arguments: Backing.allCases)
    func recovery_afterAFailedSave_savesAndPublishesOnce(backing: Backing) async throws {
        let scene = try await Self.failedFinish(backing)
        #expect(await scene.host.needsRecovery, "the foreground has work left")
        #expect(try await scene.host.resumeFromStore() == nil)
        try await Self.expectSavedOnce(scene)
        #expect(await scene.heard() == [WorkoutSessionUpdate(state: scene.finished)])
        #expect(await scene.host.needsRecovery == false)
        #expect(try await scene.host.resumeFromStore() == nil, "running it twice changes nothing")
        #expect(await scene.heard().count == 1)
    }

    @Test(
        "A compaction that fails after the save: the workout is in history once, and the retry ends it once",
        arguments: Backing.allCases
    )
    func finish_compactionFails_savedOnceAndEndedOnce(backing: Backing) async throws {
        let scene = try await Self.failedFinish(backing, at: .compact)
        let finished = try #require(scene.finished)
        #expect(try await scene.rig.history() == [scene.rig.asStored(finished)].compactMap(\.self))
        #expect(await scene.heard().isEmpty, "the ending update waits for the compaction")
        #expect(try await scene.host.current() == scene.live)
        #expect(try await scene.host.finish(endedAt: SiegeScene.end) == finished)
        try await Self.expectSavedOnce(scene)
        #expect(await scene.heard().map(\.state) == [finished])
    }
}
