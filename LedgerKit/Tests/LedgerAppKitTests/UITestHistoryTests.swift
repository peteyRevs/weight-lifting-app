import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F15 S1 criterion 1 (restated, Q1): a UI test's past workouts, `-LEDGER_UITEST_HISTORY <weeks>` beside
/// `-LEDGER_UITEST` and `-LEDGER_UITEST_PROGRAM seed`, read as `UITestProgram` reads its argument, and saved by the
/// root's launch call right after the seed program, once, in the call `RootGate.follow` awaits before it reads.
@Suite("UITestHistory", .timeLimit(.minutes(1)))
struct UITestHistoryTests {
    private static let asked = ["Ledger", "-LEDGER_UITEST", "1", "-LEDGER_UITEST_PROGRAM", "seed"]

    @Test("The weeks are read beside -LEDGER_UITEST and the seed program, and only there")
    func weeks_isReadOnlyForAUITest() throws {
        #expect(try UITestHistory.weeks(arguments: Self.asked + ["-LEDGER_UITEST_HISTORY", "4"]) == 4)
        #expect(try UITestHistory.weeks(arguments: Self.asked + ["-LEDGER_UITEST_HISTORY", "16"]) == 16)
        #expect(try UITestHistory.weeks(arguments: Self.asked) == nil)
        #expect(try UITestHistory.weeks(arguments: ["Ledger", "-LEDGER_UITEST_HISTORY", "4"]) == nil)
        #expect(try UITestHistory.weeks(arguments: ["Ledger", "-LEDGER_UITEST_HISTORY", "none"]) == nil)
    }

    @Test("A value that is missing or is no whole number from 1 to 16 is refused", arguments: [
        nil, "", "0", "17", "-1", "4.5", "four", "-LEDGER_UITEST_NOW"
    ])
    func weeks_refusesAnyOtherValue(value: String?) {
        let arguments = Self.asked + ["-LEDGER_UITEST_HISTORY"] + [value].compactMap(\.self)
        #expect(throws: UITestHistory.InvalidWeeks(value: value)) {
            try UITestHistory.weeks(arguments: arguments)
        }
    }

    @Test("Asked for without the seed program, it is refused: the workouts belong to that program")
    func weeks_withoutTheSeedProgram_isRefused() {
        #expect(throws: UITestHistory.NoSeedProgram()) {
            try UITestHistory.weeks(arguments: ["Ledger", "-LEDGER_UITEST", "1", "-LEDGER_UITEST_HISTORY", "4"])
        }
    }

    @Test("The live environment carries the weeks asked for, and none when not asked")
    func liveEnvironment_carriesTheWeeks() {
        let live = AppComposition.Environment.live(arguments: Self.asked + ["-LEDGER_UITEST_HISTORY", "4"])
        #expect(live.uiTestHistoryWeeks == 4)
        #expect(live.seedsUITestProgram)
        #expect(AppComposition.Environment.live(arguments: Self.asked).uiTestHistoryWeeks == nil)
        #expect(UITestHistory.liveWeeks(arguments: ["Ledger"]) == nil)
    }

    @Test("Asked for, the gate's first answer is the tabs, over the seed program and its workouts, records derived")
    func asked_theGateOpensOverTheHistory() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 4)
        composition.boot()
        let gate = RootGate()
        let follow = Task { await gate.follow(composition, in: .active) }
        defer { follow.cancel() }
        #expect(await gate.answer() == .main)

        // Read once the gate has answered: the launch call, which the gate awaits first, has stored them by now.
        let stores = try #require(composition.stores)
        let expected = try Fixtures.history(weeks: 4)
        let stored = try await stores.workouts.recent(limit: 100)
        #expect(stored.map(\.id) == expected.reversed().map(\.id), "the fixture's workouts, newest first")
        #expect(try await stores.programs.active()?.id == Fixtures.seedProgram().id)
        let records = try await stores.workouts.historyEntries().map(\.prCount).reduce(0, +)
        #expect(records > 0, "the repository derived their records, as after real workouts")
    }

    @Test("Saved once in a process: a later pass stores nothing, even over a database emptied of workouts")
    func asked_savedOnceInAProcess() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 1)
        composition.boot()
        #expect(await harness.gate(following: composition).destination == .main)
        let workouts = try #require(composition.stores).workouts
        let stored = try await workouts.recent(limit: 100)
        #expect(!stored.isEmpty)

        for workout in stored {
            try await workouts.delete(id: workout.id)
        }
        await composition.resume(in: .active)
        await composition.saveUITestProgramIfAsked()
        #expect(try await workouts.recent(limit: 100).isEmpty, "the history is saved once in a process")
    }

    @Test("A launch over a database that holds a workout stores no history: the second launch adds nothing")
    func secondLaunch_overWorkouts_storesNothing() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let first = harness.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 2)
        first.boot()
        #expect(await harness.gate(following: first).destination == .main)
        let firstWorkouts = try #require(first.stores).workouts
        let oldest = try #require(try await firstWorkouts.recent(limit: 100).last)
        try await firstWorkouts.delete(id: oldest.id)
        let left = try await firstWorkouts.recent(limit: 100).map(\.id)

        let second = harness.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 2)
        second.boot()
        #expect(await harness.gate(following: second).destination == .main)
        let workouts = try #require(second.stores).workouts
        #expect(try await workouts.recent(limit: 100).map(\.id) == left, "nothing stored again, nothing back")
    }

    @Test("A history that fails to save is not retried, and the launch goes on to the tabs over the seed program")
    func failedSave_theLaunchGoesOn() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try harness.arrange {
            try $0.execute(sql: "CREATE TRIGGER refuse BEFORE INSERT ON workout BEGIN SELECT RAISE(ABORT, 'no'); END")
        }
        let composition = harness.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 1)
        composition.boot()
        #expect(await harness.gate(following: composition).destination == .main)
        let stores = try #require(composition.stores)
        #expect(try await stores.programs.active()?.id == Fixtures.seedProgram().id)
        #expect(try await stores.workouts.recent(limit: 100).isEmpty)

        try await stores.queue.write { try $0.execute(sql: "DROP TRIGGER refuse") }
        await composition.saveUITestProgramIfAsked()
        #expect(try await stores.workouts.recent(limit: 100).isEmpty, "a failure counts as the one save")
    }

    /// The Release path: `liveWeeks` reads nothing there, so the environment holds no weeks, which is this.
    @Test("Not asked for (and so in a Release build), the seed program is saved and no workout is")
    func notAsked_storesNoWorkout() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true)
        composition.boot()
        #expect(await harness.gate(following: composition).destination == .main)
        #expect(try await #require(composition.stores).workouts.recent(limit: 100).isEmpty)
    }
}
