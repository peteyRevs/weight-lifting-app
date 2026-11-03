@testable import FeatureHistory
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S3, criteria 4 and 7, N11 and N12, through the store over in-memory stores: the draft, steps in pounds and in
/// kilograms, "Save" off until something changed, one save for a double tap, failure, a workout deleted meanwhile, and
/// a cancelled run.
@MainActor
@Suite("EditSetsStore", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct EditSetsStoreTests {
    private func weightText(_ scene: EditScene) -> String? {
        scene.store.model.exercises.first?.sets.first?.weight.value
    }

    @Test("4. The sheet opens on every exercise and its logged sets, with Save off")
    func draft_isTheWorkoutsLoggedSets() {
        let scene = EditScene(EditFixtures.partlyLogged())
        let model = scene.store.model
        #expect(model.exercises.count == 2)
        #expect(model.exercises[0].sets.map(\.weight.label) == ["Set 1 weight", "Set 2 weight"])
        #expect(model.exercises[0].nothingLogged == nil)
        #expect(model.exercises[1].sets.isEmpty)
        #expect(model.exercises[1].nothingLogged == "Nothing logged")
        #expect(model.foot.action == nil)
    }

    @Test("4. A step in pounds moves the exercise's step, and turns Save on; its way back turns Save off")
    func steps_inPounds() throws {
        let scene = EditScene()
        let set = try scene.firstSet
        #expect(weightText(scene) == "190 lb")
        scene.store.send(.step(set.id, .weight, .upward))
        #expect(weightText(scene) == "195 lb")
        #expect(scene.store.model.foot.action == .save)
        scene.store.send(.step(set.id, .weight, .downward))
        #expect(weightText(scene) == "190 lb")
        #expect(scene.store.model.foot.action == nil)
    }

    @Test("7. A pound workout read in kilograms draws kg and moves to the next kg multiple")
    func steps_inKilograms() throws {
        let scene = EditScene(units: .kg)
        let set = try scene.firstSet
        #expect(weightText(scene) == "86.2 kg")
        scene.store.send(.step(set.id, .weight, .upward))
        #expect(weightText(scene) == "87.5 kg")
        #expect(scene.store.model.exercises.first?.sets.first?.weight.spokenValue == "87.5 kilograms")
    }

    @Test("N11. At 1 rep the step down is off")
    func repsAtOne_haveNoStepDown() {
        var workout = HistoryFixtures.twelve()[11]
        workout.exercises[0].sets[0].reps = .one
        let field = EditScene(workout).store.model.exercises.first?.sets.first?.reps
        #expect(field?.decrement == nil)
        #expect(field?.increment != nil)
    }

    @Test("N12. Save with nothing changed is refused: no write")
    func save_withNoChange_writesNothing() async {
        let scene = EditScene()
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.phase == .editing && scene.store.attempt == nil)
        #expect(scene.workouts.saveCount == 0)
    }

    @Test("4, N12. Save hands every changed exercise to one call, and the sheet is saved")
    func save_writesEveryChangedExerciseOnce() async throws {
        let workout = Seeders.workout(number: 7, endedAt: Fixtures.date(2026, 9, 16, hour: 8), [
            .straight(HistoryFixtures.bench, sets: 1, reps: 5, pounds: 185),
            .straight(WorkoutRepositoryContract.exercises[1], sets: 1, reps: 5, pounds: 225)
        ])
        let scene = EditScene(workout)
        scene.store.send(.step(workout.exercises[0].sets[0].id, .weight, .upward))
        scene.store.send(.step(workout.exercises[1].sets[0].id, .reps, .downward))
        scene.store.send(.save)
        #expect(scene.store.phase == .saving)
        #expect(scene.store.model.isEnabled == false)
        #expect(scene.store.canClose == false)
        await scene.store.save()
        #expect(scene.store.phase == .saved)
        #expect(scene.workouts.saveCount == 1)
        let stored = try #require(try await scene.memory.workouts.workout(id: workout.id))
        #expect(stored.exercises[0].sets[0].weight == .pounds(190))
        #expect(stored.exercises[1].sets[0].reps.value == 4)
    }

    @Test("N12. A second tap while a save runs, and a second run of its task, save nothing more")
    func save_doubleTap_isOneSave() async throws {
        let scene = EditScene()
        try scene.store.send(.step(scene.firstSet.id, .reps, .upward))
        scene.store.send(.save)
        let attempt = scene.store.attempt
        scene.store.send(.save)
        try scene.store.send(.step(scene.firstSet.id, .reps, .upward))
        #expect(scene.store.attempt == attempt, "the second tap is dropped")
        async let first: Void = scene.store.save()
        async let second: Void = scene.store.save()
        _ = await (first, second)
        await scene.store.save()
        #expect(scene.workouts.saveCount == 1)
        let stored = try #require(try await scene.memory.workouts.workout(id: scene.workout.id))
        #expect(stored.exercises[0].sets[0].reps.value == 6, "the step sent while saving was dropped")
    }

    @Test("N12. A failure shows a line and keeps the draft; another step takes the line away, and Save can run again")
    func save_failed_keepsTheSheet() async throws {
        let scene = EditScene(saveFailure: DetailWorkouts.DeleteFailed())
        let id = try scene.firstSet.id
        scene.store.send(.step(id, .weight, .upward))
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.phase == .editing)
        #expect(scene.store.model.foot.problem == "Couldn't save your changes. Try again in a moment.")
        #expect(weightText(scene) == "195 lb")
        #expect(scene.store.model.foot.action == .save)
        scene.store.send(.step(id, .reps, .upward))
        #expect(scene.store.model.foot.problem == nil)
    }

    @Test("N12. A workout deleted meanwhile says so, and asks nothing more")
    func save_workoutDeleted_saysSo() async throws {
        let scene = EditScene()
        try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
        try await scene.memory.workouts.delete(id: scene.workout.id)
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.phase == .workoutGone)
        #expect(scene.store.model.foot.problem == nil)
        let gone = scene.store.model.workoutGone
        #expect(gone?.title == "This workout was deleted")
        #expect(gone?.message == "Your changes weren't saved.")
        #expect(gone?.okay == "OK")
        #expect(scene.store.canClose)
    }

    @Test("N12. A run cancelled before its write stores nothing, says nothing, and leaves the draft to save again")
    func save_cancelled_writesNothing() async throws {
        let scene = EditScene()
        try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
        scene.store.send(.save)
        let store = scene.store
        let run = Task { await store.save() }
        run.cancel()
        await run.value
        #expect(scene.store.phase == .editing)
        #expect(scene.store.model.foot.problem == nil)
        let stored = try #require(try await scene.memory.workouts.workout(id: scene.workout.id))
        #expect(stored == scene.workout)
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.phase == .saved)
    }
}

/// F13 S3, the detail's part: "Edit" opens the sheet over what the detail shows, and the sheet coming down.
@MainActor
@Suite("WorkoutDetailStore's edit", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutDetailEditTests {
    static let newest = HistoryFixtures.twelve()[11]

    @Test("4. Edit opens on the workout as stored, in the units drawn; its save redraws the detail, without navigating")
    func edit_opens_andASaveRedraws() async throws {
        let scene = DetailScene(Self.newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.edit == "Edit")
        scene.store.edit()
        let request = try #require(scene.store.editing)
        #expect(request.units == .lb)
        #expect(request.workout == Self.newest)
        var sets = Self.newest.exercises[0].sets
        sets[0].weight = .pounds(500)
        try await scene.memory.workouts.updateSets([Self.newest.exercises[0].id: sets], of: Self.newest.id)
        scene.store.editClosed(.cancelled)
        #expect(scene.store.editing == nil)
        await eventually { (try? scene.model.receipt.rows.first?.chips.first)?.contains("500") == true }
    }

    @Test("Edit opens nothing before the workout is drawn, or on a workout that can't be read")
    func edit_onNothingDrawn_opensNothing() async {
        let scene = DetailScene(Self.newest.id, endsObservation: true)
        scene.store.edit()
        #expect(scene.store.editing == nil)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.edit()
        #expect(scene.store.editing == nil)
    }

    @Test("N12. A workout deleted under the sheet waits; the detail closes when the sheet comes down")
    func deletedUnderTheSheet_closesAfterIt() async throws {
        let scene = DetailScene(Self.newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.edit()
        try await scene.memory.workouts.delete(id: Self.newest.id)
        // Nothing to wait on but a state that must not change: the observation's nil is seen by the next read.
        var values = scene.memory.workouts.observeWorkout(id: Self.newest.id).makeAsyncIterator()
        _ = await values.next()
        await Task.yield()
        #expect(scene.store.pendingRoute == nil, "the sheet is still up")
        scene.store.editClosed(.cancelled)
        await eventually { scene.store.state == .gone }
        #expect(scene.store.pendingRoute?.route == .closeWorkout(Self.newest.id))
    }

    @Test("N12. A save that found the workout gone closes the detail with the sheet")
    func sheetFoundItGone_closesTheDetail() async {
        let scene = DetailScene(Self.newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.edit()
        scene.store.editClosed(.workoutGone)
        #expect(scene.store.state == .gone)
        #expect(scene.store.pendingRoute?.route == .closeWorkout(Self.newest.id))
    }

    @Test("N12. The sheet's item is the request while it is up; the system's nil (a swipe) closes it as Cancel does")
    func sheetItem_nilClosesIt() async throws {
        let scene = DetailScene(Self.newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.edit()
        let request = try #require(scene.store.editSheet)
        #expect(request.workout == Self.newest)
        scene.store.editSheet = request
        #expect(scene.store.editing == request, "only a nil closes it")
        scene.store.editSheet = nil
        #expect(scene.store.editing == nil)
        #expect(scene.store.pendingRoute == nil)
        #expect(try scene.model.edit == "Edit", "the receipt stays")
    }
}
