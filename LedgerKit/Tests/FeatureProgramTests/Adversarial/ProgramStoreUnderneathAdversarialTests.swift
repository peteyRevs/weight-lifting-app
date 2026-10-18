@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 1: relative edits against a program that changed underneath, and "−" refused at the
/// write inside a batch (criterion 8, ruling R4), with the workouts read before that write.
@MainActor
@Suite("Adversarial F11 S13 · edits against a program changed underneath", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramStoreUnderneathAdversarialTests {
    @Test("\"−\" waiting while the block is cut elsewhere is applied to what is stored then: once, from 7 to 6")
    func removeLastWeek_blockCutUnderneath_removesOneMore() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        let id = try #require(rig.session.shown?.id)
        await rig.probe.hold(.updateProgram)
        rig.store.send(.edit(.removeLastWeek(loggedWeeks: [])))
        try await rig.probe.waitUntilHeld()
        _ = try await rig.memory.programs.update(id) { try ProgramEditing.removeLastWeek($0, loggedWeeks: []) }
        await rig.probe.release()
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.weeks.count == 6)
        await s13Until { rig.session.shown == stored }
        #expect(rig.store.notice == nil)
    }

    @Test("\"−\" waiting while the block is cut to two elsewhere: refused at the write with the Domain's notice")
    func removeLastWeek_blockCutToTwoUnderneath_showsMinimumTwoWeeks() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        let id = try #require(rig.session.shown?.id)
        await rig.probe.hold(.updateProgram)
        rig.store.send(.edit(.removeLastWeek(loggedWeeks: [])))
        try await rig.probe.waitUntilHeld()
        _ = try await rig.memory.programs.update(id) { program in
            var cut = program
            cut.weeks = Array(program.weeks.prefix(2))
            return cut
        }
        await rig.probe.release()
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.weeks.count == 2)
        #expect(rig.store.notice == .minimumTwoWeeks)
        #expect(rig.session.waiting.isEmpty)
        await s13Until { rig.session.shown == stored }
        #expect(rig.model?.block.chips.count == 2)
    }

    @Test("R4: a workout finished in week 8 after \"−\" was tapped drops the whole batch and names week 8")
    func minusInABatch_weekLoggedSinceTheTap_dropsTheBatch() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram)
        rig.store.send(.rename("First"))
        try await rig.probe.waitUntilHeld()
        let minus = try #require(rig.model?.block.removeWeek)
        guard case .edit(.removeLastWeek, _) = minus else {
            Issue.record("\"−\" is \(minus), not an edit")
            return
        }
        rig.store.send(minus)
        rig.store.send(.edit(.setDeload(true, week: 2)))
        rig.store.send(.rename("First and more"))
        #expect(rig.model?.block.chips.count == 7)
        _ = try await rig.memory.workouts.materialize(
            S13Fixtures.finished(week: 7, start: S13Fixtures.morning(week: 7, weekday: 1)),
            slotUpdates: [],
            droppingLog: false
        )
        await rig.probe.release()
        await rig.settled()
        let stored = try #require(try await rig.storedProgram())
        #expect(stored.name == "First", "the first write is stored")
        #expect(stored.weeks.count == 8, "week 8 is kept")
        #expect(stored.week(at: 2)?.isDeload == false, "the whole batch is dropped (R4)")
        #expect(rig.store.notice == .weekHasLoggedSessions(weekNumber: 8))
        #expect(rig.model?.notice == "Week 8 has logged sessions and can't be removed.")
        #expect(rig.session.waiting.isEmpty)
        await s13Until { rig.session.shown == stored }
    }

    @Test("Criterion 8: the workouts are read after the last workout was finished and before the write with \"−\"")
    func minus_readsTheWorkoutsBeforeItsWrite() async throws {
        let rig = try S13Rig()
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        await rig.probe.hold(.updateProgram)
        rig.store.send(.rename("First"))
        try await rig.probe.waitUntilHeld()
        rig.store.send(.edit(.removeLastWeek(loggedWeeks: [])))
        rig.log.clear()
        await rig.probe.release()
        await rig.settled()
        let entries = rig.log.all
        let write = try #require(entries.firstIndex(of: "update"), "\(entries)")
        #expect(entries[..<write].contains("workouts"), "read before the write: \(entries)")
        #expect(try await rig.storedProgram()?.weeks.count == 7)
    }
}
