import Dependencies
@testable import FeatureLibrary
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S1, criteria 1, 2, 3 and 8 and N1, through the store over in-memory stores: the first model, what a change
/// of each source redraws without navigating, the filter's intents, the route, and the failed state.
@MainActor
@Suite("LibraryStore", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct LibraryStoreTests {
    static let bench = "Barbell Bench Press"

    /// Three bench sessions at 195 × 5, the newest at `Fixtures.now`.
    static func benchHistory() throws -> [WorkoutState] {
        try LibraryFixtures.sessions(of: LibraryFixtures.exercise(named: bench), 3, pounds: 195, reps: 5)
    }

    @Test("1. The first model: bench in RECENTLY LOGGED with its sessions and PR, every exercise under ALL")
    func run_firstModel_showsRecentAndAll() async throws {
        let scene = try LibraryScene(workouts: Self.benchHistory())
        let run = await scene.running()
        defer { run.cancel() }
        let model = try scene.model
        #expect(model.names(.recent) == [Self.bench])
        #expect(model.row(Self.bench, in: .recent)?.meta == "Barbell · Chest · 3 sessions")
        #expect(model.row(Self.bench, in: .recent)?.record == "195")
        #expect(model.section(.all)?.rows.count == LibraryFixtures.catalog.count)
        #expect(model.search.placeholder == "Search \(LibraryFixtures.catalog.count) exercises")
    }

    @Test("N1. A custom exercise saved while the Library is up appears, without navigating")
    func customExerciseSaved_whileRunning_appears() async throws {
        let scene = LibraryScene()
        let run = await scene.running()
        defer { run.cancel() }
        try await scene.memory.exercises.save(LibraryFixtures.custom)
        let name = LibraryFixtures.custom.name
        await eventually { (try? scene.model.row(name)) != nil }
        #expect(try scene.model.row(name)?.meta == "Barbell · Chest · Custom")
        #expect(try scene.model.search.placeholder == "Search \(LibraryFixtures.catalog.count + 1) exercises")
    }

    @Test("N1. A workout finished while the Library is up shows: its exercise is recent and its PR is new")
    func workoutFinished_whileRunning_updatesRecentAndPR() async throws {
        let scene = try LibraryScene(workouts: Self.benchHistory())
        let run = await scene.running()
        defer { run.cancel() }
        let squat = try LibraryFixtures.exercise(named: "Back Squat")
        try await scene.memory.workouts.materialize(
            Seeders.workout(number: 1, endedAt: Fixtures.now.addingTimeInterval(60), [
                .straight(squat, sets: 3, reps: 5, pounds: 225),
                .straight(LibraryFixtures.exercise(named: Self.bench), sets: 1, reps: 3, pounds: 205)
            ]),
            slotUpdates: []
        )
        // Both are in the newest workout, where recentlyLogged orders them by id.
        await eventually { (try? Set(scene.model.names(.recent))) == ["Back Squat", Self.bench] }
        #expect(try scene.model.row(Self.bench, in: .recent)?.meta == "Barbell · Chest · 4 sessions")
        #expect(try scene.model.row(Self.bench)?.record == "205")
        #expect(try scene.model.row("Back Squat")?.record == "225")
    }

    @Test("8. A change of units redraws every PR, without navigating")
    func unitsChanged_redrawsThePRs() async throws {
        let scene = try LibraryScene(workouts: Self.benchHistory())
        let run = await scene.running()
        defer { run.cancel() }
        try await scene.memory.settings.save(Fixtures.settingsKg)
        await eventually { (try? scene.model.row(Self.bench)?.record) == "88.5" }
        #expect(try scene.model.row(Self.bench, in: .recent)?.spokenValue.hasSuffix("PR 88.5 kilograms") == true)
    }

    @Test("2. The query and both chips apply at once; Clear filters resets all three")
    func filters_applyAtOnce_andClearFiltersResetsAll() async throws {
        let scene = try LibraryScene(workouts: Self.benchHistory())
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.send(.setQuery("row"))
        scene.store.send(.setMuscle(.back))
        scene.store.send(.setEquipment(.machine))
        #expect(try scene.model.names(.all) == ["Chest-Supported Row"])
        #expect(try scene.model.section(.recent) == nil, "bench does not pass the filter")
        scene.store.send(.clearFilters)
        #expect(scene.store.filter == LibraryFilter())
        #expect(try scene.model.selectedChips == ["All", "All"])
        #expect(try scene.model.search.query.isEmpty)
        #expect(try scene.model.names(.recent) == [Self.bench])
    }

    @Test("2. A filter set before the first model is in it")
    func filter_beforeTheFirstModel_isInIt() async throws {
        let scene = LibraryScene()
        scene.store.send(.setQuery("row"))
        scene.store.send(.setEquipment(.machine))
        #expect(scene.store.state == .loading)
        let run = await scene.running()
        defer { run.cancel() }
        let expected = ExerciseSearch.filtered(LibraryFixtures.catalog, query: "row", muscle: nil, equipment: .machine)
        #expect(try scene.model.names(.all) == expected.map(\.name))
        #expect(expected.count >= 1)
        #expect(try scene.model.search.query == "row")
    }

    @Test("3. A row's tap waits as one route; a second tap before the app took it is dropped")
    func rowTapped_twice_isOneRoute() async throws {
        let scene = LibraryScene()
        let run = await scene.running()
        defer { run.cancel() }
        let row = try #require(scene.model.row(Self.bench))
        scene.store.send(row.action)
        scene.store.send(row.action)
        var handed: [LibraryRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        scene.store.deliverRoute { handed.append($0) }
        #expect(try handed == [.exercise(LibraryFixtures.exercise(named: Self.bench).id)])
        #expect(scene.store.pendingRoute == nil)
        scene.store.send(row.action)
        #expect(scene.store.pendingRoute?.number == 2, "a tap after the app took the first is a new route")
    }

    @Test("New exercise is recorded for S3's sheet; it routes nowhere and changes no model")
    func newExercise_isRecorded_andRoutesNowhere() async throws {
        let scene = LibraryScene()
        let run = await scene.running()
        defer { run.cancel() }
        let before = try scene.model
        scene.store.send(before.newExercise.action)
        #expect(scene.store.isNewExerciseShown)
        #expect(scene.store.pendingRoute == nil)
        #expect(try scene.model == before)
    }

    @Test("A new run keeps the model on screen until its own is ready")
    func newRun_keepsTheModelOnScreen() async throws {
        let scene = try LibraryScene(workouts: Self.benchHistory())
        let first = await scene.running()
        first.cancel()
        await first.value
        scene.store.send(.setMuscle(.chest))
        let second = Task { await scene.store.run() }
        defer { second.cancel() }
        await Task.yield()
        #expect(try scene.model.selectedChips == ["Chest", "All"], "never loading again")
        // The second run follows the sources: a change shows.
        try await scene.memory.exercises.save(LibraryFixtures.custom)
        await eventually { (try? scene.model.row(LibraryFixtures.custom.name)) != nil }
        #expect(try scene.model.names(.recent) == [Self.bench])
    }

    @Test("An observation that ends shows the failed state")
    func observationEnds_showsFailed() async {
        let scene = LibraryScene { $0.settingsRepository = EndedSettings() }
        let run = await scene.running()
        defer { run.cancel() }
        #expect(scene.store.state == .failed)
        scene.store.send(.setQuery("row"))
        #expect(scene.store.state == .failed, "a filter does not draw over the failed state")
    }

    /// F12 S3, N20: the stats are an observation, which ends when its read fails, as GRDB's does.
    @Test("A stats observation whose read fails shows the failed state")
    func statsReadFails_showsFailed() async {
        let scene = LibraryScene { $0.statsQueries = UnreadableBests(base: $0.statsQueries) }
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
}

/// The stats of `base`, but the Library's can't be read: `bestSets` throws, and the Library's observation ends at
/// once, as a database observation does when its read fails.
nonisolated struct UnreadableBests: StatsQueries {
    struct Unreadable: Error {}

    let base: any StatsQueries

    func bestSets() async throws -> [ExerciseID: BestSet] {
        throw Unreadable()
    }

    func observeLibraryStats(recentLimit _: Int) -> AsyncStream<LibraryStats> {
        AsyncStream { $0.finish() }
    }

    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
        try await base.lastPerformance(exerciseID: exerciseID)
    }

    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        try await base.bestSet(exerciseID: exerciseID)
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

    func exerciseSessions(exerciseID: ExerciseID) async throws -> [ExerciseSession] {
        try await base.exerciseSessions(exerciseID: exerciseID)
    }
}
