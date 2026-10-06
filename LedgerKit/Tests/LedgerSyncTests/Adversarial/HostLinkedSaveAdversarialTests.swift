import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criterion 5: "A finish is: store `finished`, then one transaction (the workout,
/// its records, the misses, the program updates, the log dropped), then the ending update. Over the database
/// a workout can no longer be in history and still shown as live … and recovery's row "saved, not compacted"
/// remains only for stores that are not one database." A linked rig passes the save that drops the log on to
/// its stores as one call, as the app's database takes it; an unlinked one is a host over stores that are not
/// one database.
@Suite("Adversarial F10 S3 · the host saves and drops in one call", .tags(.sync, .property), .timeLimit(.minutes(1)))
struct HostLinkedSaveAdversarialTests {
    typealias Backing = SiegeRig.Backing

    @Test(
        "A seeded siege of a host whose save drops the log, in memory: the host follows its store",
        arguments: SessionLane.cut(SeamSeed.all, to: 12)
    )
    func siege_linkedInMemoryStores_hostFollowsItsStore(seed: SeamSeed) async throws {
        let violation = try await SiegeTrial.violation(seed: seed.value, backing: .memory, linked: true)
        #expect(violation == nil, "\(seed)")
    }

    @Test(
        "A seeded siege of a host whose save drops the log, over the database: the host follows its store",
        arguments: SessionLane.cut(SeamSeed.all.prefix(100), to: 6)
    )
    func siege_linkedDatabase_hostFollowsItsStore(seed: SeamSeed) async throws {
        let violation = try await SiegeTrial.violation(seed: seed.value, backing: .database, linked: true)
        #expect(violation == nil, "\(seed)")
    }

    /// A scene whose stores take the save as one call.
    static func linked(_ backing: Backing) async throws -> SiegeScene {
        try await SiegeScene.make(backing, linked: true)
    }

    @Test(
        "Over stores that are one database a finish is an append and one save: no compaction of its own",
        arguments: Backing.allCases
    )
    func finish_overOneDatabase_isAnAppendAndOneSave(backing: Backing) async throws {
        let scene = try await Self.linked(backing)
        await scene.siege.forgetCalls()
        let finished = try await scene.host.finish(endedAt: SiegeScene.end)
        let writes = await scene.siege.calls.filter(SiegeLogs.writes.contains)
        #expect(writes == [.append, .materialize])
        let isSaved = try await scene.rig.history() == [scene.rig.asStored(finished)].compactMap(\.self)
        #expect(isSaved, "in history as it was returned")
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(await scene.heard().map(\.state?.phase) == [.finished])
    }

    @Test("Over stores that are not one database a finish still saves, then compacts", arguments: Backing.allCases)
    func finish_overStoresThatAreNotOneDatabase_savesThenCompacts(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        await scene.siege.forgetCalls()
        _ = try await scene.host.finish(endedAt: SiegeScene.end)
        #expect(await scene.siege.calls.filter(SiegeLogs.writes.contains) == [.append, .materialize, .compact])
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(try await scene.rig.history().count == 1)
    }

    @Test(
        "A save that fails over one database leaves no history row and the whole log, and the retry saves once",
        arguments: Backing.allCases
    )
    func finish_saveFailsOverOneDatabase_nothingIsHalfDone(backing: Backing) async throws {
        let scene = try await Self.linked(backing)
        let finished = try #require(scene.finished)
        await scene.siege.fail(.materialize, times: 2)
        for _ in 0 ..< 2 {
            #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host) == "materialize refuse")
            #expect(try await scene.rig.history().isEmpty, "no history row")
            let isWhole = try await scene.rig.replayed(scene.live.id) == finished
            #expect(isWhole, "the log whole, its end in it")
            let isShown = try await scene.host.current() == scene.live
            #expect(isShown, "every reader sees the workout as it stood")
        }
        let retried = try await scene.host.finish(endedAt: SiegeScene.end.addingTimeInterval(99))
        #expect(retried.endedAt == SiegeScene.end)
        #expect(try await scene.rig.history().map(\.id) == [finished.id])
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(await scene.heard().map(\.state?.phase) == [.finished])
    }

    /// The transaction committed and its answer was lost: the store holds the workout and no log, and the host
    /// cannot know. The protocol has it go on showing the workout until a later call completes the end.
    @Test(
        "A save whose answer is lost over one database: saved once, and the next finish ends it once",
        arguments: Backing.allCases
    )
    func finish_answerLostOverOneDatabase_isSavedOnce(backing: Backing) async throws {
        let scene = try await Self.linked(backing)
        await scene.siege.fail(.materialize, .loseAnswer)
        #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host) == "materialize loseAnswer")
        let saved = try await scene.rig.history()
        #expect(saved.count == 1, "the transaction went through")
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(await scene.heard().isEmpty, "no ending update yet")
        let again = try await scene.host.finish(endedAt: SiegeScene.end)
        #expect(again.phase == .finished)
        let isUnchanged = try await scene.rig.history() == saved
        #expect(isUnchanged, "saving again changed nothing")
        #expect(try await scene.host.current() == nil)
        #expect(await scene.heard().map(\.state?.phase) == [.finished])
    }

    /// F10-S2-1 after S3: nothing of the wedge changed. What S3 took away is the half-saved state beside it:
    /// while the end waits, no row of history and no slot of the program has changed, linked or not.
    @Test(
        "(documents) A workout the database can never save still wedges the session, and changes nothing meanwhile",
        arguments: Backing.allCases,
        [true, false]
    )
    func finish_neverSavable_wedgesAsBeforeAndChangesNothing(backing: Backing, linked: Bool) async throws {
        let swap = try await HostProgramUpdateAdversarialTests.swapped(backing, linked: linked)
        let set = swap.standing.exercises[4].sets[0]
        let standing = try await swap.scene.host.apply(.setLogged(
            exerciseIndex: 4, setID: set.id, weight: .pounds(0.125), reps: set.reps, doneAt: Seam.at(950)
        ))
        let program = try await swap.scene.rig.programs.active()
        for call in [SeamCall.finish(SiegeScene.end), .discard(SiegeScene.end), .finish(SiegeScene.end)] {
            let outcome = await SiegeScene.outcome(call, on: swap.scene.host)
            #expect(outcome.hasPrefix("inexactWeight"), "\(call): \(outcome.prefix(60))")
        }
        let start = await Seam.outcome(of: .start(Seam.session(2)), on: swap.scene.host)
        #expect(start == .refused(.workoutInProgress(standing.id)))
        let isUntouched = try await swap.scene.rig.programs.active() == program
        #expect(isUntouched, "the swap and the misses wait with the workout")
        #expect(try await swap.scene.rig.history().isEmpty)
        #expect(try await swap.scene.rig.replayed(standing.id)?.phase == .finished, "the end is in the log, whole")
    }

    /// Where the process dies around the save, and what the next launch must find.
    static let kills: [(call: SiegeCall, fault: SiegeFault)] = [
        (.append, .dieAfter), (.materialize, .dieBefore), (.materialize, .dieAfter), (.compact, .dieBefore)
    ]

    @Test(
        "Killed at each point around the save, linked or not: the relaunch leaves it in history once, with no log",
        arguments: Backing.allCases,
        [true, false]
    )
    func kill_aroundTheSave_theRelaunchCompletesIt(backing: Backing, linked: Bool) async throws {
        for kill in Self.kills {
            let scene = try await SiegeScene.make(backing, linked: linked)
            let finished = try #require(scene.finished)
            await scene.siege.fail(kill.call, kill.fault)
            _ = await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host)
            let inHistory = try await !scene.rig.history().isEmpty
            let hasLog = try await !scene.rig.uncompacted().isEmpty
            let name = "\(kill.call.rawValue) \(kill.fault.rawValue), \(linked ? "linked" : "not linked")"
            if linked, await scene.siege.hasDied {
                #expect(
                    inHistory != hasLog,
                    "\(name): in history \(inHistory), a log \(hasLog): one, never both or neither"
                )
            }
            await scene.siege.heal()
            let relaunched = await scene.rig.host()
            #expect(await SiegeLogs.launch(relaunched) == "no workout", "\(name)")
            let isSaved = try await scene.rig.history() == [scene.rig.asStored(finished)].compactMap(\.self)
            #expect(isSaved, "\(name): in history once, as the engine finished it")
            #expect(try await scene.rig.uncompacted().isEmpty, "\(name)")
            #expect(await relaunched.needsRecovery == false, "\(name)")
        }
    }
}
