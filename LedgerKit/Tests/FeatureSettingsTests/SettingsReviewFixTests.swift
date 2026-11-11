@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S2 fix round 2, against G3's round 1: a failed export (coverage), the plates sheet closed by a failed switch
/// that puts its units back, and "Try again" for units already shown (N6).
@MainActor
@Suite("SettingsStore · G3 round 1 fixes", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct SettingsReviewFixTests {
    @Test("N16. An export whose workouts cannot be read throws to the share sheet and leaves no file")
    func export_failedRead_throwsAndWritesNothing() async throws {
        let scene = SettingsScene(workouts: UnreadableWorkouts(InMemoryWorkoutRepository()))
        let task = await scene.running()
        defer { task.cancel() }
        let export = try scene.model.export.file
        await #expect(throws: UnreadableWorkouts.Refused.self) {
            _ = try await export.write()
        }
        let listed = try? FileManager.default.contentsOfDirectory(atPath: scene.exportDirectory.path)
        #expect(listed?.isEmpty ?? true, "no file is left")
    }

    @Test("The previews' export writes nothing: it throws")
    func unavailableExport_throws() async {
        await #expect(throws: CocoaError.self) {
            _ = try await WorkoutExport.unavailable.write()
        }
    }

    @Test("N6. A failed switch that puts the units back closes a plates sheet opened in the units it failed to")
    func failedSwitch_closesTheSheetOfItsUnits() async {
        let scene = SettingsScene(failures: 1, holdsSaves: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilASaveIsHeld()
        scene.store.send(.editPlates)
        #expect(scene.store.plates?.units == .kg)
        scene.watched.releaseSaves()
        await eventually { scene.store.model?.retry != nil }
        #expect(scene.store.plates == nil && scene.store.model?.platesSheet == nil)
    }

    @Test("N6. A failed switch's sheet in the units that stay is kept")
    func failedSwitch_keepsTheSheetOfTheUnitsThatStay() async {
        let scene = SettingsScene(failures: 1, holdsSaves: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        scene.store.send(.setUnits(.kg))
        await scene.untilASaveIsHeld()
        scene.watched.releaseSaves()
        await eventually { scene.store.model?.retry != nil }
        #expect(scene.store.plates?.units == .lb)
    }

    @Test("N6. Try again for units already shown clears the line and saves nothing")
    func tryAgain_forUnitsShown_clearsTheLine() async throws {
        var settings = Fixtures.settingsLb
        settings.units = .kg
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        // As if a switch to kilograms were written and then reported failed.
        scene.store.saveFailed = true
        scene.store.failedSwitch = .kg
        scene.store.show()
        let retry = try #require(try scene.model.retry)
        scene.store.send(retry.action)
        #expect(try scene.model.problem == nil && scene.model.retry == nil)
        #expect(scene.watched.saves.isEmpty)
    }
}

/// The workouts of `base`, but `workouts(in:)`, the export's one read, fails.
nonisolated struct UnreadableWorkouts: WorkoutRepository {
    struct Refused: Error {}

    let base: InMemoryWorkoutRepository

    init(_ base: InMemoryWorkoutRepository) {
        self.base = base
    }

    func workouts(in _: Range<Date>) async throws -> [WorkoutState] {
        throw Refused()
    }

    func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog: Bool) async throws -> Bool {
        try await base.materialize(workout, slotUpdates: slotUpdates, droppingLog: droppingLog)
    }

    func workout(id: WorkoutID) async throws -> WorkoutState? {
        try await base.workout(id: id)
    }

    func recent(limit: Int) async throws -> [WorkoutState] {
        try await base.recent(limit: limit)
    }

    func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
        try await base.updateSets(workoutExerciseID: workoutExerciseID, sets: sets)
    }

    func updateSets(_ sets: [WorkoutExerciseID: [LoggedSet]], of workout: WorkoutID) async throws {
        try await base.updateSets(sets, of: workout)
    }

    func delete(id: WorkoutID) async throws {
        try await base.delete(id: id)
    }

    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
        base.observeRecent(limit: limit)
    }

    func historyEntries() async throws -> [HistoryEntry] {
        try await base.historyEntries()
    }

    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        base.observeHistoryEntries()
    }

    func observeWorkout(id: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        base.observeWorkout(id: id)
    }
}
