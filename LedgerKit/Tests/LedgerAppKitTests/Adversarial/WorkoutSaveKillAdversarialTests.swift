import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import SwiftUI
import Testing

/// F10 S3 adversarial round 1, criteria 4 and 5 through the composition, on a real database file. It replaces
/// what `WorkoutRelaunchAdversarialTests` pinned in S2, "killed after the save and before the compaction":
/// the save and the log's deletion are now one transaction, so over the database that state no longer exists.
/// What holds instead: a kill at any statement of the transaction leaves no history row, no program change and
/// the whole log, and the relaunch saves the workout and drops the log; a kill after the commit leaves the
/// row and no log. (The old state, which only stores that are not one database can reach, is
/// `HostRecoveryAdversarialTests`' and `HostLinkedSaveAdversarialTests`'.)
@Suite("Adversarial F10 S3 · killed around the save's one transaction", .timeLimit(.minutes(1)))
struct WorkoutSaveKillAdversarialTests {
    typealias Launch = WorkoutLaunch

    @Test(
        "Killed inside the save's one transaction, at each statement: no history row and the whole log",
        arguments: WorkoutLaunch.saveStatements
    )
    func kill_insideTheSaveTransaction_leavesNoRowAndTheWholeLog(statement: String) async throws {
        // A directory for each case: the cases run at once, and a harness is named after its function.
        let harness = Harness("killInsideTheSave \(statement)")
        defer { harness.remove() }
        let run = try await WorkoutRelaunchAdversarialTests.running(harness, Launch.middle)
        let finished = try #require(Launch.folded(Launch.middle + [.finished(endedAt: Launch.end)]))
        try await run.execute(Launch.refusal(of: statement))
        await #expect(throws: (any Error).self) { try await run.session.finish(endedAt: Launch.end) }
        #expect(try await run.rows(in: Launch.historyTables) == [0, 0, 0, 0], "no row of history, \(statement) refused")
        let log = try await run.stores.events.envelopes(for: finished.id)
        let isWhole = log.count == Launch.middle.count + 2 && WorkoutEngine.replay(log) == finished
        #expect(isWhole, "the log is whole and holds the end: \(log.count) envelopes")
        try await run.execute(Launch.allow)
        let relaunched = try await AppRun(harness)
        let isSaved = try await relaunched.history() == [Launch.asStored(finished)].compactMap(\.self)
        #expect(isSaved, "the relaunch saved the workout as the engine finished it")
        #expect(try await relaunched.logs().isEmpty)
        #expect(try await relaunched.session.current() == nil)
    }

    /// The same, where the transaction reaches the program: the statement that sets a slot's exercise for a
    /// swap made with "Also update program" is refused, so the app dies with the workout's rows written and
    /// not committed.
    @Test("Killed at the program's statement of the save: no row, no slot changed, the whole log")
    func kill_atTheProgramStatement_leavesTheProgramAndSavesOnRelaunch() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await AppRun(harness)
        let program = try Fixtures.seedProgram()
        try await run.stores.programs.save(program)
        let catalog = try ExerciseCatalog.seed()
        let session = try SessionBuilder.build(
            program: program, weekIndex: 4, day: program.days[0],
            exercises: Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) }), history: [:],
            settings: Fixtures.settingsLb, id: Launch.session.id, device: run.stores.deviceID, now: EventBuilders.start
        )
        let (replacement, slot) = try (#require(catalog.last), #require(session.exercises[1].slotID))
        try await run.session.start(session)
        try await run.session.apply(.exerciseSwapped(
            exerciseIndex: 1, exerciseID: replacement.id, name: replacement.name, alsoUpdateProgram: true
        ))
        try await run.execute(Launch.refusal(of: "UPDATE ON slot"))
        await #expect(throws: (any Error).self) { try await run.session.finish(endedAt: Launch.end) }
        let isUntouched = try await run.stores.programs.active() == program
        #expect(isUntouched, "no slot and no miss of the program changed")
        #expect(try await run.rows(in: Launch.historyTables) == [0, 0, 0, 0])
        #expect(try await run.stores.events.envelopes(for: session.id).count == 3, "the whole log")
        try await run.execute(Launch.allow)
        let relaunched = try await AppRun(harness)
        let stored = try await relaunched.stores.programs.active()?.days[0].slots.first { $0.id == slot }
        #expect(stored?.exerciseID == replacement.id, "the swap landed with the save")
        #expect(stored?.misses.contains(4) == true, "and the slot's miss of week 5, in the same transaction")
        #expect(try await relaunched.history().map(\.id) == [session.id])
        #expect(try await relaunched.logs().isEmpty)
    }

    @Test("Killed once the transaction has committed: the history row and no log, and the relaunch changes nothing")
    func kill_afterTheSaveCommitted_leavesTheRowAndNoLog() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await WorkoutRelaunchAdversarialTests.running(harness, Launch.middle)
        _ = try await run.session.finish(endedAt: Launch.end)
        let saved = try await run.history()
        let counts = try await run.rows(in: Launch.historyTables + ["workout_event"])
        #expect(saved.count == 1 && counts.last == 0, "in history, and no event left: \(counts)")
        harness.clearLog()
        let relaunched = try await AppRun(harness)
        let isUnchanged = try await relaunched.history() == saved
        #expect(isUnchanged, "history as the killed app left it")
        #expect(try await relaunched.rows(in: Launch.historyTables + ["workout_event"]) == counts)
        #expect(try await relaunched.session.current() == nil)
        #expect(Launch.steps(harness, .resumeWorkout) == ["began resumeWorkout"])
    }
}
