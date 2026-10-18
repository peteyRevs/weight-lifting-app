import Dependencies
@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13, criteria 7 to 13: the builder's store over the in-memory stores behind a probe. Each test runs
/// `run()` and `save()` in tasks, as `ProgramRoot`'s tasks run them, and waits for what it expects by
/// observing the store, never by time. Criteria 7 to 9 here, the actions in `+Actions`.
@MainActor
@Suite("ProgramStore", .tags(.feature), .timeLimit(.minutes(1)))
struct ProgramStoreTests {
    // MARK: Criterion 7

    @Test("7. Loading until every source has spoken; then the seed program, from the stores")
    func run_showsTheStoredProgram() async throws {
        let scene = try ProgramStoreScene()
        #expect(scene.store.state == .loading)
        let running = await scene.running()
        #expect(try scene.model.block.title == "BLOCK · 8 WEEKS")
        #expect(try scene.model.days.summary == "4 days · 58 sets a week")
        await running.cancel()
        #expect(try scene.model.block.chips.count == 8, "a root that went away has not failed")
    }

    @Test("7. With no active program it shows the empty state")
    func noActiveProgram_showsTheEmptyState() async throws {
        let scene = try ProgramStoreScene(hasProgram: false)
        let running = await scene.running()
        #expect(scene.store.state == .noProgram)
        await running.cancel()
    }

    @Test("7. A program observation that ends before a value shows the failed state")
    func streamEndsBeforeAValue_showsFailed() async throws {
        let scene = try ProgramStoreScene { values, _ in values.programRepository = EndedPrograms() }
        let running = await scene.running()
        #expect(scene.store.state == .failed)
        await running.cancel()
        #expect(scene.store.state == .failed, "a root that went away leaves it so until the next run")
    }

    @Test("7. Once loaded it is never loading again: a new run keeps the model on screen")
    func loaded_neverReturnsToLoading() async throws {
        let scene = try ProgramStoreScene()
        let first = await scene.running()
        let model = try scene.model
        await first.cancel()
        let second = await scene.running()
        #expect(try scene.model == model)
        await second.cancel()
    }

    @Test("7. A workout saved meanwhile is shown, under the edits that wait")
    func storedProgramChanges_isShown() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        let program = try await scene.stored()
        let slot = program.days[0].slots[0]
        await scene.probe.hold(.updateProgram)
        scene.store.send(.rename("Block A"))
        try await scene.probe.waitUntilHeld()
        scene.store.send(.edit(.setDeload(true, week: 1)))
        var workout = try finishedWorkout(of: program, weekIndex: 4)
        workout.programUpdates = [slot.id: Fixtures.CatalogID.inclineDBPress]
        _ = try await scene.memory.workouts.materialize(workout, slotUpdates: [], droppingLog: false)
        await scene.probe.release()
        await scene.idle()
        let shown = try #require(scene.store.session.shown)
        #expect(shown.days[0].slots[0].exerciseID == Fixtures.CatalogID.inclineDBPress)
        #expect(shown.name == "Block A" && shown.weeks[1].isDeload)
        #expect(try scene.model.days.cards[0].chips.first == "INCLINE")
        await running.cancel()
    }

    // MARK: Criterion 8

    @Test("8. A finished workout in the last week makes \"−\" say so, read on the first run")
    func loggedLastWeek_minusSaysSo() async throws {
        let program = try Fixtures.seedProgram()
        let scene = try ProgramStoreScene(finished: [finishedWorkout(of: program, weekIndex: 7)])
        let running = await scene.running()
        #expect(try scene.model.block.removeWeek == .notice(.weekHasLoggedSessions(weekNumber: 8)))
        await running.cancel()
    }

    @Test("8. A workout finished in the last week while the screen is open is read again")
    func workoutFinishedMeanwhile_isRead() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        #expect(try scene.model.block.removeWeek == .edit(.removeLastWeek(loggedWeeks: [])))
        let workout = try await finishedWorkout(of: scene.stored(), weekIndex: 7)
        _ = try await scene.memory.workouts.materialize(workout, slotUpdates: [], droppingLog: false)
        await eventually { scene.store.loggedWeeks == [7] }
        #expect(try scene.model.block.removeWeek == .notice(.weekHasLoggedSessions(weekNumber: 8)))
        await running.cancel()
    }

    @Test("8. A workout finished in the last week between the tap on \"−\" and the write removes nothing and says so")
    func workoutFinishedBeforeTheWrite_removesNothing() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        scene.store.send(.rename("Block A"))
        try await scene.probe.waitUntilHeld()
        try scene.store.send(scene.model.block.removeWeek)
        let workout = try await finishedWorkout(of: scene.stored(), weekIndex: 7)
        _ = try await scene.memory.workouts.materialize(workout, slotUpdates: [], droppingLog: false)
        await scene.probe.release()
        await scene.idle()
        #expect(try await scene.stored().weeks.count == 8)
        #expect(try scene.model.block.chips.count == 8)
        #expect(try scene.model.notice == "Week 8 has logged sessions and can't be removed.")
        await running.cancel()
    }

    // MARK: Criterion 9

    @Test("9. The first model selects the week that holds the injected date: week 5 of the seed block")
    func firstLoad_selectsTheWeekThatHoldsToday() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        #expect(scene.store.selectedWeek == 4)
        #expect(try scene.model.week.title == "WEEK 5")
        await running.cancel()
    }

    @Test("9. A week asked for wins over today's, and a new request selects again")
    func requestedWeek_isSelected() async throws {
        let scene = try ProgramStoreScene()
        scene.store.select(week: 2)
        let running = await scene.running()
        #expect(try scene.model.week.title == "WEEK 3")
        scene.store.send(.selectWeek(6))
        scene.store.select(week: 2)
        #expect(try scene.model.week.title == "WEEK 3")
        await running.cancel()
    }

    @Test("9. Before the block, the selection is handed in raw and read as the first week")
    func beforeTheBlock_selectionIsRaw() async throws {
        var program = try Fixtures.seedProgram()
        program.startDate = try #require(CivilDate(year: 2026, month: 10, day: 5))
        let scene = try ProgramStoreScene(program: program)
        let running = await scene.running()
        #expect(scene.store.selectedWeek == -3)
        #expect(try scene.model.week.title == "WEEK 1")
        await running.cancel()
    }

    @Test("9. \"−\" keeps the selection raw; the last week is shown; \"+\" selects the week it added")
    func removeWeek_keepsTheSelectionInsideTheBlock() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        scene.store.send(.selectWeek(7))
        try scene.store.send(scene.model.block.removeWeek)
        #expect(scene.store.selectedWeek == 7)
        #expect(try scene.model.week.title == "WEEK 7")
        #expect(try scene.model.block.chips[6].isSelected)
        scene.store.send(.selectWeek(0))
        try scene.store.send(scene.model.block.addWeek)
        #expect(scene.store.selectedWeek == 7)
        #expect(try scene.model.week.title == "WEEK 8")
        await scene.idle()
        await running.cancel()
    }
}
