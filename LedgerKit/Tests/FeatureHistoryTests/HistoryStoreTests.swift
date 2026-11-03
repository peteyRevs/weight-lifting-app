import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S1, criteria 1, 2, 6 and 7 and N2, through the store over in-memory stores: the first model, what a change of
/// each source redraws without navigating (an older workout edited, a delete, the units, the first day of the week),
/// the route, and the failed state.
@MainActor
@Suite("HistoryStore", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct HistoryStoreTests {
    static let twelve = HistoryFixtures.twelve()

    @Test("1. The first model: four weeks of three workouts, newest first, each with its records as stored")
    func run_firstModel_showsTheWeeks() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        let model = try scene.model
        #expect(model.weeks.map(\.title) == ["Sep 7 – 13", "Aug 31 – Sep 6", "Aug 24 – 30", "Aug 17 – 23"]
            .map(\.thinSpaced))
        let stored = try await scene.memory.workouts.historyEntries()
        let inTheStoredOrder = model.rows.map(\.id) == stored.map(\.id)
        #expect(inTheStoredOrder)
        let badges = model.rows.map { $0.badge != nil } == stored.map { $0.prCount > 0 }
        #expect(badges, "a badge where the workout holds records")
        #expect(model.rows.last?.badge == nil, "the first workout is a baseline")
        #expect(model.rows.first?.meta == "Fri · 58 min · 2,850 lb")
    }

    @Test("N2. An older workout edited while History is up redraws its row, and the record it takes from a later one")
    func olderWorkoutEdited_redrawsItsRowAndALaterOnes() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        let oldest = try #require(Self.twelve.first)
        let second = try #require(Self.twelve.dropFirst().first)
        #expect(try scene.model.row(second.id)?.badge != nil)
        // The oldest workout's bench raised past the second's 140 lb: the second sets no record any more.
        var raised = oldest.exercises[0].sets
        for index in raised.indices {
            raised[index].weight = .pounds(145)
        }
        try await scene.memory.workouts.updateSets(workoutExerciseID: oldest.exercises[0].id, sets: raised)
        await eventually { (try? scene.model.row(oldest.id)?.meta) == "Mon · 58 min · 2,175 lb" }
        #expect(try scene.model.row(second.id)?.badge == nil)
    }

    @Test("5, the list's part. A workout deleted while History is up leaves its week; the last of a week, the week")
    func workoutDeleted_leavesTheList() async throws {
        let scene = HistoryScene(workouts: Array(Self.twelve.prefix(4)))
        let run = await scene.running()
        defer { run.cancel() }
        let newest = try #require(Self.twelve.dropFirst(3).first)
        #expect(try scene.model.weeks.count == 2)
        try await scene.memory.workouts.delete(id: newest.id)
        await eventually { (try? scene.model.weeks.count) == 1 }
        #expect(try scene.model.row(newest.id) == nil)
        #expect(try scene.model.weeks.map(\.title) == ["Aug 17 – 23"].map(\.thinSpaced))
    }

    @Test("7. A change of units redraws every volume, without navigating")
    func unitsChanged_redrawsTheVolumes() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        try await scene.memory.settings.save(Fixtures.settingsKg)
        await eventually { (try? scene.model.rows.first?.meta) == "Fri · 58 min · 1,293 kg" }
        #expect(try scene.model.rows.first?.spokenValue.contains("1,293 kilograms") == true)
    }

    @Test("A new first day of the week regroups the list (F14 criterion 7), without navigating")
    func weekStartChanged_regroups() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        var settings = Fixtures.settingsLb
        settings.weekStart = .wednesday
        try await scene.memory.settings.save(settings)
        await eventually { (try? scene.model.weeks.first?.title) == "Sep 9 – 15".thinSpaced }
        #expect(try scene.model.weeks.map(\.rows.count) == [2, 3, 3, 3, 1])
    }

    @Test("A workout finished while History is up appears at the top")
    func workoutFinished_appears() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        let finished = HistoryFixtures.workout(20, startedAt: Fixtures.date(2026, 9, 14, hour: 7), name: "Lower B")
        try await scene.memory.workouts.materialize(finished, slotUpdates: [])
        await eventually { (try? scene.model.weeks.first?.title) == "Sep 14 – 20".thinSpaced }
        #expect(try scene.model.rows.first?.name == "Lower B")
    }

    @Test("2. No workout: the empty state, and its button routes to Today")
    func noWorkouts_showsTheEmptyState_andRoutesToToday() async throws {
        let scene = HistoryScene()
        let run = await scene.running()
        defer { run.cancel() }
        guard case let .empty(empty) = try scene.model.content else {
            Issue.record("not the empty state")
            return
        }
        scene.store.send(empty.route)
        var handed: [HistoryRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.today])
    }

    @Test("6. A row's tap waits as one route; a second tap before the app took it is dropped")
    func rowTapped_twice_isOneRoute() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        let row = try #require(scene.model.rows.first)
        scene.store.send(row.route)
        scene.store.send(row.route)
        var handed: [HistoryRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.workout(row.id)])
        #expect(scene.store.pendingRoute == nil)
        scene.store.send(row.route)
        #expect(scene.store.pendingRoute?.number == 2, "a tap after the app took the first is a new route")
    }

    @Test("A new run keeps the model on screen until its own is ready, then follows the sources")
    func newRun_keepsTheModelOnScreen() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let first = await scene.running()
        first.cancel()
        await first.value
        let shown = try scene.model
        let second = Task { await scene.store.run() }
        defer { second.cancel() }
        await Task.yield()
        let isKept = try scene.model == shown
        #expect(isKept, "never loading again")
        try await scene.memory.workouts.delete(id: #require(Self.twelve.last).id)
        await eventually { (try? scene.model.rows.count) == 11 }
    }

    @Test("An observation that ends shows the failed state")
    func observationEnds_showsFailed() async {
        let scene = HistoryScene { $0.settingsRepository = EndedSettings() }
        let run = await scene.running()
        defer { run.cancel() }
        #expect(scene.store.state == .failed)
    }

    @Test("A workouts observation whose read fails shows the failed state")
    func workoutsObservationEnds_showsFailed() async {
        let scene = HistoryScene { $0.workoutRepository = EndedHistory(base: $0.workoutRepository) }
        let run = await scene.running()
        defer { run.cancel() }
        #expect(scene.store.state == .failed)
    }
}

/// A settings store whose observation ends at once, as a database observation does when its read fails.
nonisolated struct EndedSettings: SettingsRepository {
    struct Unused: Error {}

    func load() async throws -> Settings {
        throw Unused()
    }

    func save(_: Settings) async throws {
        throw Unused()
    }

    func observe() -> AsyncStream<Settings> {
        AsyncStream { $0.finish() }
    }

    /// F14's `SettingsRepository.seedIfAbsent(_:)` (on `feat/F14-settings`), here before the protocol requires it so
    /// that this double compiles whichever lane merges first (review R1-3 addendum).
    func seedIfAbsent(_: Settings) async throws {}
}

/// The workouts of `base`, but the History list's observation ends at once, as GRDB's does when its read fails.
nonisolated struct EndedHistory: WorkoutRepository {
    let base: any WorkoutRepository

    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        AsyncStream { $0.finish() }
    }

    func observeWorkout(id: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        base.observeWorkout(id: id)
    }

    func historyEntries() async throws -> [HistoryEntry] {
        try await base.historyEntries()
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

    func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
        try await base.workouts(in: range)
    }

    func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
        try await base.updateSets(workoutExerciseID: workoutExerciseID, sets: sets)
    }

    func delete(id: WorkoutID) async throws {
        try await base.delete(id: id)
    }

    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
        base.observeRecent(limit: limit)
    }
}
