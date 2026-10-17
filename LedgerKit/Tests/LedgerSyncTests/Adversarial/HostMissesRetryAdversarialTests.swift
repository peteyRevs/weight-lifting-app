import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criteria 4 and 6: the misses when the save is not the first attempt. The
/// recovery table has the launch step materialise with "misses from the program as stored now", and F05's
/// input 6 forbids writing a copy of the slots taken earlier, which "would clear misses recorded since".
@Suite("Adversarial F10 S2 · misses when the save is retried", .tags(.sync), .timeLimit(.minutes(1)))
struct HostMissesRetryAdversarialTests {
    typealias Backing = SiegeRig.Backing
    typealias Scenes = HostMissesAdversarialTests

    /// Records misses the lifter's program gained while the save waited.
    static func recordMissesSince(_ rig: SiegeRig) async throws -> Program {
        var program = try #require(try await rig.programs.active())
        program.days[0].slots[0].misses.formUnion([1, 2])
        program.days[0].slots[3].misses = [0]
        try await rig.programs.save(program)
        return program
    }

    @Test(
        "The launch step saves a killed finish with misses from the program as stored at the launch",
        arguments: Backing.allCases
    )
    func recovery_finishedLog_readsTheProgramAsStoredNow(backing: Backing) async throws {
        let scene = try await Scenes.scene(backing)
        await scene.siege.fail(.materialize, .dieBefore)
        _ = await Seam.outcome(of: .finish(SiegeScene.end), on: scene.host)
        let finished = try #require(try await scene.rig.replayed(scene.live.id))
        #expect(finished.phase == .finished)
        let program = try await Self.recordMissesSince(scene.rig)
        let relaunched = await scene.rig.host()
        #expect(await SiegeLogs.launch(relaunched) == "no workout")
        #expect(try await Scenes.misses(scene.rig.programs.active()) == Scenes.expected(on: program, after: finished))
        #expect(try await scene.rig.history().map(\.id) == [finished.id])
    }

    @Test("A finish retried after a failed compaction keeps the misses recorded since", arguments: Backing.allCases)
    func finish_retriedAfterAFailedCompaction_keepsLaterMisses(backing: Backing) async throws {
        let scene = try await Scenes.scene(backing)
        await scene.siege.fail(.compact)
        #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host) == "compact refuse")
        let finished = try #require(try await scene.rig.replayed(scene.live.id))
        let program = try await Self.recordMissesSince(scene.rig)
        _ = try await scene.host.finish(endedAt: SiegeScene.end)
        let after = try await Scenes.misses(scene.rig.programs.active())
        #expect(after == Scenes.expected(on: program, after: finished))
        #expect(after[program.days[0].slots[0].id] == [1, 2] && after[program.days[0].slots[3].id] == [0, 4])
    }

    @Test(
        "A finish that cannot read the program throws and publishes nothing; the retry saves with the misses",
        arguments: Backing.allCases
    )
    func finish_programCannotBeRead_isRetriedWithMisses(backing: Backing) async throws {
        let scene = try await Scenes.scene(backing)
        let standing = try #require(try await scene.host.current())
        let wanted = try await Scenes.expected(on: scene.rig.programs.active(), after: standing)
        await scene.siege.fail(.activeProgram)
        #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host) == "activeProgram refuse")
        #expect(try await scene.rig.history().isEmpty, "never saved without its misses")
        #expect(try await scene.host.current() == standing)
        let finished = try await scene.host.finish(endedAt: SiegeScene.end.addingTimeInterval(60))
        #expect(finished.endedAt == SiegeScene.end)
        #expect(try await Scenes.misses(scene.rig.programs.active()) == wanted)
        #expect(try await scene.rig.history().map(\.id) == [standing.id])
    }
}
