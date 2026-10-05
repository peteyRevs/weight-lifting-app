import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 5 and the ends that cross: a discard whose compaction fails, a
/// discard after a failed save, a finish after a failed discard, and a workout the store can never save.
@Suite("Adversarial F10 S2 · a discard that fails, and ends that cross", .tags(.sync), .timeLimit(.minutes(1)))
struct HostDiscardFailureAdversarialTests {
    typealias Backing = SiegeRig.Backing

    static func failedDiscard(_ backing: Backing) async throws -> SiegeScene {
        let scene = try await SiegeScene.make(backing)
        await scene.siege.fail(.compact)
        #expect(await SiegeScene.outcome(.discard(SiegeScene.end), on: scene.host) == "compact refuse")
        return scene
    }

    static func expectDiscardedOnce(_ scene: SiegeScene) async throws {
        let discarded = try #require(scene.update(after: .discarded(endedAt: SiegeScene.end)))
        #expect(try await scene.rig.history().isEmpty, "nothing reaches history")
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(try await scene.host.current() == nil)
        #expect(await scene.heard() == [discarded])
        #expect(await scene.siege.saved.isEmpty, "a discarded workout is never written")
    }

    @Test(
        "A discard whose compaction fails: the end waits, nothing is published, and no workout can start",
        arguments: Backing.allCases
    )
    func discard_compactionFails_theEndWaits(backing: Backing) async throws {
        let scene = try await Self.failedDiscard(backing)
        #expect(try await scene.rig.replayed(scene.live.id)?.phase == .discarded)
        #expect(try await scene.host.current() == scene.live)
        #expect(await scene.heard().isEmpty)
        let other = await Seam.outcome(of: .start(Seam.session(2)), on: scene.host)
        #expect(other == .refused(.workoutInProgress(scene.live.id)))
    }

    @Test("Calling discard again completes it: one ending update, nothing in history", arguments: Backing.allCases)
    func discard_afterAFailedCompaction_completesOnce(backing: Backing) async throws {
        let scene = try await Self.failedDiscard(backing)
        try await scene.host.discard(endedAt: SiegeScene.end.addingTimeInterval(60))
        try await Self.expectDiscardedOnce(scene)
        #expect(await Seam.outcome(of: .discard(SiegeScene.end), on: scene.host) == .refused(.noLiveWorkout))
    }

    @Test("A finish after a failed discard never saves the workout", arguments: Backing.allCases)
    func finish_afterAFailedDiscard_savesNothing(backing: Backing) async throws {
        let scene = try await Self.failedDiscard(backing)
        #expect(await Seam.outcome(of: .finish(SiegeScene.end), on: scene.host) == .refused(.noLiveWorkout))
        try await Self.expectDiscardedOnce(scene)
    }

    @Test("The launch step completes a failed discard, without a haptic", arguments: Backing.allCases)
    func recovery_afterAFailedDiscard_dropsTheLog(backing: Backing) async throws {
        let scene = try await Self.failedDiscard(backing)
        #expect(try await scene.host.resumeFromStore() == nil)
        #expect(try await scene.rig.history().isEmpty)
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(await scene.heard().map(\.state?.phase) == [.discarded])
        #expect(await scene.heard().allSatisfy(\.haptics.isEmpty))
    }

    /// The protocol's documentation: "before any `apply` or `discard`, which then throw `noLiveWorkout`". So a
    /// lifter whose "Save workout" failed and who then taps "Discard" gets the workout saved. The end is in
    /// the log and ADR-004 makes it terminal, so nothing else is possible without rewriting the log; the
    /// screen (S7) must not offer Discard there.
    @Test(
        "(documents) A discard after a failed save saves the workout and throws noLiveWorkout",
        arguments: Backing.allCases
    )
    func discard_afterAFailedSave_savesTheWorkout(backing: Backing) async throws {
        let scene = try await HostEndFailureAdversarialTests.failedFinish(backing)
        #expect(await Seam.outcome(of: .discard(SiegeScene.end), on: scene.host) == .refused(.noLiveWorkout))
        try await HostEndFailureAdversarialTests.expectSavedOnce(scene)
        #expect(await scene.heard().map(\.state) == [scene.finished])
    }

    @Test("An apply that carries the end meets a failed save as finish does", arguments: Backing.allCases)
    func applyFinished_saveFails_waitsLikeFinish(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        await scene.siege.fail(.materialize)
        let ending = WorkoutEvent.finished(endedAt: SiegeScene.end)
        #expect(await SiegeScene.outcome(.apply(ending), on: scene.host) == "materialize refuse")
        #expect(try await scene.host.current() == scene.live)
        #expect(await scene.heard().isEmpty)
        #expect(try await scene.host.finish(endedAt: SiegeScene.end) == scene.finished)
        try await HostEndFailureAdversarialTests.expectSavedOnce(scene)
        #expect(await scene.heard().map(\.state) == [scene.finished])
    }
}
