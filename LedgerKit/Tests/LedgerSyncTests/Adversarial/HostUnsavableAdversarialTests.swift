import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 4 where the save can never succeed: the store refuses the workout
/// itself (F05 input 8: a weight that is no whole number of 10⁻⁷ g, text holding U+0000), so every retry
/// fails as the first did. The brief speaks of a save that fails and is retried; it does not say what
/// becomes of a workout no retry can save.
@Suite("Adversarial F10 S2 · a workout the store can never save", .tags(.sync), .timeLimit(.minutes(1)))
struct HostUnsavableAdversarialTests {
    typealias Backing = SiegeRig.Backing

    /// The scene's workout with a set logged at an eighth of a pound, which the engine accepts, the event
    /// store keeps and `materialize` refuses (`inexactWeight`).
    static func unsavable(_ backing: Backing) async throws -> (scene: SiegeScene, standing: WorkoutState) {
        let scene = try await SiegeScene.make(backing)
        let set = scene.live.exercises[1].sets[0]
        let standing = try await scene.host.apply(.setLogged(
            exerciseIndex: 1,
            setID: set.id,
            weight: .pounds(0.125),
            reps: set.reps,
            doneAt: Seam.at(500)
        ))
        return (scene, standing)
    }

    @Test("The store keeps the event and refuses the workout", arguments: Backing.allCases)
    func fixture_isAcceptedByTheLogAndRefusedByHistory(backing: Backing) async throws {
        let (scene, standing) = try await Self.unsavable(backing)
        #expect(try await scene.rig.replayed(standing.id) == standing)
        let finished = try #require(Seam.update(after: .finished(endedAt: SiegeScene.end), on: standing)?.state)
        await #expect(throws: (any Error).self) {
            try await scene.rig.workouts.materialize(finished, slotUpdates: [])
        }
    }

    /// What happens today. Proposed (finding F10-S2-1): the lifter is never left with a workout that can be
    /// neither saved nor discarded nor replaced; when that is adopted this test fails and is rewritten.
    @Test(
        "(documents) After a finish the store refuses for good, discard throws too and nothing else can start",
        arguments: Backing.allCases
    )
    func finish_neverSavable_wedgesTheSessionUntilRelaunch(backing: Backing) async throws {
        let (scene, standing) = try await Self.unsavable(backing)
        for call in [SeamCall.finish(SiegeScene.end), .discard(SiegeScene.end), .apply(scene.nextLog)] {
            let outcome = await SiegeScene.outcome(call, on: scene.host)
            #expect(outcome.hasPrefix("inexactWeight"), "\(call): \(outcome)")
        }
        let start = await Seam.outcome(of: .start(Seam.session(2)), on: scene.host)
        #expect(start == .refused(.workoutInProgress(standing.id)))
        #expect(try await scene.host.current() == standing)
        #expect(try await scene.rig.replayed(standing.id)?.phase == .finished, "the end is stored: nothing is lost")
        #expect(try await scene.rig.history().isEmpty)
        #expect(await scene.heard().map(\.state) == [standing], "no ending update")
    }

    /// What happens today. Proposed (finding F10-S2-1): a launch step that can do no more about a log stops
    /// reporting work left; as it is, the step fails, with a fault-level log, on every return to the
    /// foreground for as long as the log exists, and the workout never reaches history.
    @Test(
        "(documents) After a relaunch the unsavable workout fails the launch step on every foreground",
        arguments: Backing.allCases
    )
    func recovery_neverSavable_failsOnEveryForeground(backing: Backing) async throws {
        let (scene, standing) = try await Self.unsavable(backing)
        _ = await Seam.outcome(of: .finish(SiegeScene.end), on: scene.host)
        let relaunched = await scene.rig.host()
        for _ in 0 ..< 3 {
            #expect(await SiegeLogs.launch(relaunched).hasPrefix("inexactWeight"))
            #expect(await relaunched.needsRecovery)
        }
        #expect(try await relaunched.current() == nil)
        #expect(try await scene.rig.uncompacted() == [standing.id], "the log is never dropped unsaved")
        #expect(try await scene.rig.history().isEmpty)
        try await relaunched.start(Seam.session(2))
        #expect(try await relaunched.current() == Seam.session(2), "a relaunch frees the lifter")
    }
}
