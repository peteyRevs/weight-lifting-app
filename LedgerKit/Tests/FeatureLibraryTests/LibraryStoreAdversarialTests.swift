import Dependencies
@testable import FeatureLibrary
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S1 adversarial round 1 (G2): the store where its own tests are silent. The failed state is left again by the
/// next change, with the filter typed meanwhile; a deleted newest workout takes its PR and its recent row away
/// while the Library is up (N1); RECENTLY LOGGED stops at five; a change of units keeps the filter; a bodyweight
/// exercise logged at no load reads its zero.
@MainActor
@Suite("Adversarial F12 S1 · LibraryStore", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct LibraryStoreAdversarialTests {
    static let benchName = "Barbell Bench Press"

    @Test("A failed stats read is left at the next change: the model returns, with the filter typed meanwhile")
    func statsReadFailsOnce_nextWorkout_showsTheModelWithTheFilter() async throws {
        let failures = Failures(remaining: 1)
        let scene = LibraryScene { $0.statsQueries = FailingBests(base: $0.statsQueries, failures: failures) }
        let run = await scene.running()
        defer { run.cancel() }
        #expect(scene.store.state == .failed)
        scene.store.send(.setQuery("bench"))
        let bench = try LibraryFixtures.exercise(named: Self.benchName)
        try await scene.memory.workouts.materialize(
            Seeders.workout(number: 1, endedAt: Fixtures.now, [.straight(bench, sets: 1, reps: 5, pounds: 185)]),
            slotUpdates: []
        )
        await eventually { (try? scene.model) != nil }
        let model = try scene.model
        #expect(model.search.query == "bench")
        #expect(model.row(Self.benchName)?.record == "185")
        #expect(model.names(.all).allSatisfy { $0.localizedCaseInsensitiveContains("bench") })
    }

    @Test("N1. The newest workout deleted while the Library is up takes its PR and its recent row with it")
    func newestWorkoutDeleted_whileRunning_dropsItsPRAndRecentRow() async throws {
        let bench = try LibraryFixtures.exercise(named: Self.benchName)
        let squat = try LibraryFixtures.exercise(named: "Back Squat")
        let older = Seeders.workout(number: 1, endedAt: Fixtures.now.addingTimeInterval(-86400), [
            .straight(bench, sets: 1, reps: 5, pounds: 185)
        ])
        let newest = Seeders.workout(number: 2, endedAt: Fixtures.now, [
            .straight(bench, sets: 1, reps: 3, pounds: 205),
            .straight(squat, sets: 3, reps: 5, pounds: 225)
        ])
        let scene = LibraryScene(workouts: [older, newest])
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.row(Self.benchName)?.record == "205")
        try await scene.memory.workouts.delete(id: newest.id)
        await eventually { (try? scene.model.row(Self.benchName)?.record) == "185" }
        let model = try scene.model
        #expect(model.names(.recent) == [Self.benchName])
        #expect(model.row(Self.benchName, in: .recent)?.meta == "Barbell · Chest · 1 session")
        #expect(model.row("Back Squat")?.record == "—")
    }

    @Test("1. RECENTLY LOGGED shows the five latest of seven logged exercises, the latest first")
    func sevenLogged_recentShowsTheFiveLatest() async throws {
        let names = [
            "Barbell Bench Press", "Back Squat", "Deadlift", "Barbell Row", "Overhead Press", "Pull-Up", "Dip"
        ]
        let exercises = names.compactMap { name in LibraryFixtures.catalog.first { $0.name == name } }
        #expect(exercises.count == names.count, "every name is in the catalog")
        // Exercise i is logged i days before now: the first is the latest.
        let workouts = exercises.enumerated().map { day, exercise in
            Seeders.workout(number: 10 + day, endedAt: Fixtures.now.addingTimeInterval(-86400 * Double(day)), [
                .straight(exercise, sets: 1, reps: 5, pounds: 100)
            ])
        }
        let scene = LibraryScene(workouts: workouts)
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.names(.recent) == Array(exercises.prefix(5).map(\.name)))
    }

    @Test("8. A change of units while a filter is on keeps the filter and converts what it shows")
    func unitsChanged_withAFilter_keepsTheFilter() async throws {
        let bench = try LibraryFixtures.exercise(named: Self.benchName)
        let scene = LibraryScene(workouts: [
            Seeders.workout(number: 1, endedAt: Fixtures.now, [.straight(bench, sets: 1, reps: 5, pounds: 195)])
        ])
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.send(.setQuery("bench"))
        scene.store.send(.setEquipment(.barbell))
        try await scene.memory.settings.save(Fixtures.settingsKg)
        await eventually { (try? scene.model.row(Self.benchName)?.record) == "88.5" }
        let model = try scene.model
        #expect(model.search.query == "bench")
        #expect(model.selectedChips == ["All", "Barbell"])
        #expect(model.names(.all).allSatisfy { $0.localizedCaseInsensitiveContains("bench") })
    }

    /// F12-S1-3 (question for Pete): the brief says a row's PR is the best set's weight, so a bodyweight exercise
    /// done at no added load reads "0" and is spoken "PR 0 pounds", where one never logged reads "—". Pinned as
    /// built until Pete answers.
    @Test("A bodyweight exercise logged at no load reads its PR as 0, not as a dash")
    func zeroLoadBest_readsZero_andSpeaksIt() async throws {
        let pushUp = try #require(LibraryFixtures.catalog.first { $0.equipment == .bodyweight })
        let scene = LibraryScene(workouts: [
            Seeders.workout(number: 1, endedAt: Fixtures.now, [
                Seeders.ExerciseLog(pushUp, [Seeders.SetSpec(0, 15), Seeders.SetSpec(0, 12)])
            ])
        ])
        let run = await scene.running()
        defer { run.cancel() }
        let row = try #require(try scene.model.row(pushUp.name))
        #expect(row.record == "0")
        #expect(row.spokenValue.hasSuffix("PR 0 pounds"))
    }
}

/// How many more `bestSets` reads fail.
final nonisolated class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int

    init(remaining: Int) {
        self.remaining = remaining
    }

    /// Whether this read fails, counting it.
    func next() -> Bool {
        lock.withLock {
            defer { remaining -= 1 }
            return remaining > 0
        }
    }
}

/// The stats of `base`, but the first `failures` reads of `bestSets` throw, as a read the database refused once.
nonisolated struct FailingBests: StatsQueries {
    let base: any StatsQueries
    let failures: Failures

    func bestSets() async throws -> [ExerciseID: BestSet] {
        if failures.next() {
            throw UnreadableBests.Unreadable()
        }
        return try await base.bestSets()
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
