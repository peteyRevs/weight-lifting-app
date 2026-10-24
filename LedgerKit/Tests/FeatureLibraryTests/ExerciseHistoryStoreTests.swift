@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S2, criteria 8 and 11 and N13, through the store over in-memory stores: the model of the exercise asked
/// for, a change of units, a rename, a finished workout, the failed state and a route delivered once.
@MainActor
@Suite("ExerciseHistoryStore", .tags(.feature), .timeLimit(.minutes(1)))
struct ExerciseHistoryStoreTests {
    @Test("The first model is the history of the exercise asked for, its records tagged")
    func run_firstModel_isTheExercisesHistory() async throws {
        let scene = try HistoryScene(workouts: HistoryScene.benchWorkouts())
        let run = await scene.running()
        defer { run.cancel() }
        let model = try scene.model
        #expect(model.title == "Barbell Bench Press")
        #expect(model.stats.map(\.value) == ["219", "195", "3"])
        #expect(model.numbers.suffix(3) == [208, 214, 219])
        #expect(model.log.entries.map(\.tag) == ["PR", "PR", "—"], "each heavier week beat the one before")
    }

    @Test("8. A change of units redraws the history, without navigating")
    func unitsChanged_redraws() async throws {
        let scene = try HistoryScene(workouts: HistoryScene.benchWorkouts())
        let run = await scene.running()
        defer { run.cancel() }
        try await scene.memory.settings.save(Fixtures.settingsKg)
        await eventually { (try? scene.model.stats.first?.value) == "100" }
        #expect(try scene.model.stats[1].value == "88.5")
    }

    @Test("N13. A finished workout shows in an open history, and a rename of a custom exercise does too")
    func workoutFinishedAndRename_show() async throws {
        let scene = try HistoryScene(exercise: LibraryFixtures.custom.id)
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.log.entries.isEmpty)
        try await scene.memory.workouts.materialize(
            Seeders.workout(number: 700, endedAt: Fixtures.now, [
                .straight(LibraryFixtures.custom, sets: 2, reps: 8, pounds: 95)
            ]),
            slotUpdates: []
        )
        await eventually { (try? scene.model.log.entries.count) == 1 }
        #expect(try scene.model.stats.map(\.value) == ["118", "95", "1"])
        var renamed = LibraryFixtures.custom
        renamed.name = "Landmine Hug Press"
        try await scene.memory.exercises.save(renamed)
        await eventually { (try? scene.model.title) == "Landmine Hug Press" }
    }

    @Test("A source that ends, a read that fails and an exercise not stored each show the failed state")
    func failures_showFailed() async throws {
        let ended = try HistoryScene { $0.settingsRepository = EndedSettings() }
        let endedRun = await ended.running()
        endedRun.cancel()
        #expect(ended.store.state == .failed)

        let unreadable = try HistoryScene { $0.statsQueries = UnreadableSessions(base: $0.statsQueries) }
        let unreadableRun = await unreadable.running()
        unreadableRun.cancel()
        #expect(unreadable.store.state == .failed)

        let missing = try HistoryScene(exercise: ExerciseID(Fixtures.uuid(999)))
        let missingRun = await missing.running()
        missingRun.cancel()
        #expect(missing.store.state == .failed)
    }

    @Test("11. A session's route waits until it is delivered, once; a second tap meanwhile is dropped")
    func route_isDeliveredOnce() throws {
        let scene = try HistoryScene()
        let workout = WorkoutID(Fixtures.uuid(1))
        scene.store.send(.openWorkout(workout))
        scene.store.send(.openWorkout(WorkoutID(Fixtures.uuid(2))))
        var delivered: [LibraryRoute] = []
        scene.store.deliverRoute { delivered.append($0) }
        scene.store.deliverRoute { delivered.append($0) }
        #expect(delivered == [.openWorkout(workout)])
        #expect(scene.store.pendingRoute == nil)
    }
}

/// The stats of `base`, but the sessions cannot be read.
nonisolated struct UnreadableSessions: StatsQueries {
    struct Unreadable: Error {}

    let base: any StatsQueries

    func exerciseSessions(exerciseID _: ExerciseID) async throws -> [ExerciseSession] {
        throw Unreadable()
    }

    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
        try await base.lastPerformance(exerciseID: exerciseID)
    }

    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        try await base.bestSet(exerciseID: exerciseID)
    }

    func bestSets() async throws -> [ExerciseID: BestSet] {
        try await base.bestSets()
    }

    func bestE1RM(exerciseID: ExerciseID) async throws -> Weight? {
        try await base.bestE1RM(exerciseID: exerciseID)
    }

    func e1RMByWeek(exerciseID: ExerciseID, lastWeeks: Int, calendar: WeekCalendar) async throws -> [WeekKey: Weight] {
        try await base.e1RMByWeek(exerciseID: exerciseID, lastWeeks: lastWeeks, calendar: calendar)
    }

    func weeklyVolume(in range: Range<Date>) async throws -> Volume {
        try await base.weeklyVolume(in: range)
    }

    func sessionsCompleted(in range: Range<Date>) async throws -> Int {
        try await base.sessionsCompleted(in: range)
    }

    func sessionCount(exerciseID: ExerciseID) async throws -> Int {
        try await base.sessionCount(exerciseID: exerciseID)
    }

    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord] {
        try await base.personalRecords(exerciseID: exerciseID)
    }

    func bests(before workout: WorkoutState, for exerciseIDs: Set<ExerciseID>) async throws -> PersonalRecords.Bests {
        try await base.bests(before: workout, for: exerciseIDs)
    }

    func recentlyLogged(limit: Int) async throws -> [ExerciseID] {
        try await base.recentlyLogged(limit: limit)
    }

    func observeExerciseSessions(exerciseID: ExerciseID) -> AsyncStream<[ExerciseSession]> {
        base.observeExerciseSessions(exerciseID: exerciseID)
    }
}
