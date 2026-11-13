import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Synchronization
import Testing

/// F15 S1 G2 (2026-11-12): `-LEDGER_UITEST_HISTORY <weeks>` (criterion 1, its guards, ruling A1) pushed where
/// `UITestHistoryTests` does not: values `Int` reads that a person would not write, the argument twice, the order
/// of the guards, the largest value through a real save, calls that overlap, and a save that stops midway.
@MainActor
@Suite("Adversarial F15 S1 · the UI test's history", .timeLimit(.minutes(1)))
struct UITestHistoryAdversarialTests {
    private static let asked = ["Ledger", "-LEDGER_UITEST", "1", "-LEDGER_UITEST_PROGRAM", "seed"]
    private static let history = "-LEDGER_UITEST_HISTORY"

    /// The pass a database trigger cancels, told from the database's queue.
    final nonisolated class Pass: Sendable {
        let state = Mutex<(task: Task<Void, Never>?, isCancelled: Bool)>((nil, false))
    }

    /// As built, the value is read by `Int(_:)`, as `-LEDGER_UITEST_FAIL_FINISH` reads its count: a sign or a leading
    /// zero is read, while a space, a decimal point or a number past `Int` is refused, so the launch stops.
    @Test("Values Int reads are taken, and every other spelling stops the launch", arguments: [
        ("04", 4), ("+4", 4), ("1", 1), ("016", 16), (" 4", nil), ("4 ", nil), ("4.0", nil), ("1e1", nil),
        ("٤", nil), ("0x4", nil), ("99999999999999999999", nil), ("-0", nil), ("17", nil)
    ] as [(String, Int?)])
    func weeks_asIntReadsThem(value: String, weeks: Int?) throws {
        let arguments = Self.asked + [Self.history, value]
        guard let weeks else {
            #expect(throws: UITestHistory.InvalidWeeks(value: value)) { try UITestHistory.weeks(arguments: arguments) }
            return
        }
        #expect(try UITestHistory.weeks(arguments: arguments) == weeks)
    }

    @Test("The first occurrence decides, as -LEDGER_UITEST_PROGRAM's does; -LEDGER_UITEST's own value is not read")
    func arguments_readByPosition() throws {
        #expect(try UITestHistory.weeks(arguments: Self.asked + [Self.history, "4", Self.history, "bogus"]) == 4)
        #expect(throws: UITestHistory.InvalidWeeks(value: "bogus")) {
            try UITestHistory.weeks(arguments: Self.asked + [Self.history, "bogus", Self.history, "4"])
        }
        // -LEDGER_UITEST is a switch: "0" after it is no "off", for this argument as for the others.
        let zero = ["Ledger", "-LEDGER_UITEST", "0", "-LEDGER_UITEST_PROGRAM", "seed", Self.history, "2"]
        #expect(try UITestHistory.weeks(arguments: zero) == 2)
        #expect(try UITestProgram.seeds(arguments: zero))
        // Before the seed program's argument, or after it: the order of the arguments does not matter.
        let first = ["Ledger", Self.history, "3", "-LEDGER_UITEST_PROGRAM", "seed", "-LEDGER_UITEST"]
        #expect(try UITestHistory.weeks(arguments: first) == 3)
    }

    @Test("The value is checked before the program: a bad value without the seed program names the value")
    func guards_valueBeforeProgram() {
        #expect(throws: UITestHistory.InvalidWeeks(value: "0")) {
            try UITestHistory.weeks(arguments: ["Ledger", "-LEDGER_UITEST", Self.history, "0"])
        }
        // A program other than the seed one is no seed program (the live launch stops on the program's own message
        // first, since `Environment.live` reads it before the history).
        #expect(throws: UITestHistory.NoSeedProgram()) {
            try UITestHistory.weeks(arguments: [
                "Ledger",
                "-LEDGER_UITEST",
                "-LEDGER_UITEST_PROGRAM",
                "Seed",
                Self.history,
                "4"
            ])
        }
        // The seed program's argument as the history's value is refused, not read as both.
        #expect(throws: UITestHistory.InvalidWeeks(value: "-LEDGER_UITEST_PROGRAM")) {
            try UITestHistory.weeks(arguments: [
                "Ledger",
                "-LEDGER_UITEST",
                Self.history,
                "-LEDGER_UITEST_PROGRAM",
                "seed"
            ])
        }
    }

    @Test("The largest value, 16 weeks, is saved whole through the repository, before the gate's first answer")
    func sixteenWeeks_areSavedWhole() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 16)
        composition.boot()
        #expect(await harness.gate(following: composition).destination == .main)
        let expected = try Fixtures.history(weeks: 16).reversed().map(\.id)
        let stored = try await #require(composition.stores).workouts.recent(limit: 1000).map(\.id)
        #expect(stored.count == expected.count)
        #expect(stored == expected, "every week's workouts, newest first, none refused as a duplicate")
    }

    @Test("Two calls that overlap, both before either has saved, store the fixture's workouts once, records as one")
    func overlappingCalls_storeTheHistoryOnce() async throws {
        let once = Harness("overlapOnce")
        let twice = Harness("overlapTwice")
        defer { once.remove()
            twice.remove()
        }
        let single = once.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 3)
        let racing = twice.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 3)
        for composition in [single, racing] {
            composition.boot()
            await composition.resume(in: .active)
        }
        await single.saveUITestProgramIfAsked()
        async let first: Void = racing.saveUITestProgramIfAsked()
        async let second: Void = racing.saveUITestProgramIfAsked()
        _ = await (first, second)

        let alone = try await #require(single.stores).workouts.historyEntries()
        let raced = try await #require(racing.stores).workouts.historyEntries()
        #expect(raced.map(\.id) == alone.map(\.id), "each workout once")
        #expect(raced.map(\.prCount) == alone.map(\.prCount), "the records of one save, not of two")
    }

    /// G2-1 (medium): the workouts are saved one transaction each, and the pass is skipped once any workout is
    /// stored. A first pass cancelled between two of them (a phase change, which `saveUITestProgramIfAsked` says
    /// "does not count: the next pass makes it") leaves part of the history, and the next pass, finding a workout,
    /// stores nothing more: the test then reads a history without its newest workouts.
    @Test("A pass cancelled midway through the history: the next pass leaves the whole history")
    func cancelledMidway_theNextPassMakesItWhole() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 2)
        composition.boot()
        await composition.resume(in: .active)
        let stores = try #require(composition.stores)
        let pass = Pass()
        let cancel = DatabaseFunction("g2_cancel", argumentCount: 0, pure: false) { _ in
            pass.state.withLock { $0.task?.cancel()
                $0.isCancelled = true
            }
            return nil
        }
        try await stores.queue.write { database in
            database.add(function: cancel)
            // On the second workout's insert: the first is saved, and its own transaction is over.
            try database.execute(sql: """
            CREATE TEMP TRIGGER g2_cancel BEFORE INSERT ON workout WHEN (SELECT COUNT(*) FROM workout) >= 1
            BEGIN SELECT g2_cancel(); END
            """)
        }
        let first = Task { await composition.saveUITestProgramIfAsked() }
        pass.state.withLock { $0.task = first }
        await first.value
        try await stores.queue.write { try $0.execute(sql: "DROP TRIGGER temp.g2_cancel") }
        #expect(pass.state.withLock { $0.isCancelled }, "the first pass was cancelled at the second workout")

        await composition.saveUITestProgramIfAsked()
        let expected = try Fixtures.history(weeks: 2).reversed().map(\.id)
        let stored = try await stores.workouts.recent(limit: 100).map(\.id)
        withKnownIssue("G2-1: a cancelled pass leaves part of the history, and the next pass adds nothing") {
            #expect(stored == expected, "\(stored.count) of \(expected.count) workouts stored")
        }
    }

    /// G2-1 again, through a save that fails: the log says the save failed, yet the workouts before the failure
    /// stay, so a test reads part of a history that no launch completes.
    @Test("A save that fails at the second workout leaves no history behind")
    func failedMidway_leavesNoPartOfTheHistory() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try harness.arrange {
            try $0.execute(sql: """
            CREATE TRIGGER refuse BEFORE INSERT ON workout WHEN (SELECT COUNT(*) FROM workout) >= 1
            BEGIN SELECT RAISE(ABORT, 'no'); END
            """)
        }
        let composition = harness.composition(seedsUITestProgram: true, uiTestHistoryWeeks: 2)
        composition.boot()
        #expect(await harness.gate(following: composition).destination == .main)
        let stored = try await #require(composition.stores).workouts.recent(limit: 100)
        withKnownIssue("G2-1: a failed history save keeps the workouts saved before the failure") {
            #expect(stored.isEmpty, "\(stored.count) workout(s) left by a save that was logged as failed")
        }
    }
}
