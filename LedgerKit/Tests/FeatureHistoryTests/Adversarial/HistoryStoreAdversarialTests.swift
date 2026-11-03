import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Synchronization
import Testing

/// F13 S1 adversarial (G2): the History store against its sources. The failed state is left by the next run (the
/// tab coming back) once the list can be read again; the first day of the week changed live through all seven days
/// regroups the list each time; a workout finished with an old start (a watch's late save) lands in its own week in
/// the middle of the list; a settings change that moves neither the units nor the week start leaves the model as it
/// was.
@MainActor
@Suite("Adversarial F13 S1 · the History store", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct HistoryStoreAdversarialTests {
    static let twelve = HistoryFixtures.twelve()

    @Test("After a failed observation, the next run shows the list again")
    func failed_thenNextRun_recovers() async throws {
        let scene = HistoryScene(workouts: Self.twelve) {
            $0.workoutRepository = FailingOnceHistory(base: $0.workoutRepository)
        }
        let first = await scene.running()
        #expect(scene.store.state == .failed)
        first.cancel()
        await first.value
        let second = Task { await scene.store.run() }
        defer { second.cancel() }
        await eventually { scene.store.state != .failed }
        #expect(try scene.model.rows.count == 12)
    }

    @Test("The first day of the week changed live through all seven days regroups the list each time")
    func weekStart_everyDay_regroups() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        let calendar = Fixtures.calendar
        for weekStart in [Weekday.tuesday, .wednesday, .thursday, .friday, .saturday, .sunday, .monday] {
            var settings = Fixtures.settingsLb
            settings.weekStart = weekStart
            try await scene.memory.settings.save(settings)
            let wanted = HistoryWeeks.group(
                HistoryFixtures.entries(Self.twelve),
                weekStart: weekStart,
                calendar: Fixtures.calendar
            ).map(\.bounds.lowerBound)
            await eventually { (try? scene.model.weeks.map(\.id)) == wanted }
            let firstDays = try scene.model.weeks.map {
                Weekday(calendarWeekday: calendar.component(.weekday, from: $0.id))
            }
            #expect(firstDays.allSatisfy { $0 == weekStart }, "\(weekStart)")
            #expect(try scene.model.rows.count == 12)
        }
    }

    @Test("A workout finished now with an old start lands in its own week, in the middle of the list")
    func lateSave_withAnOldStart_landsInItsWeek() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        // Tuesday of the second week, between its Monday and Wednesday workouts.
        let late = HistoryFixtures.workout(40, startedAt: Fixtures.date(2026, 8, 25, hour: 7), name: "Watch day")
        try await scene.memory.workouts.materialize(late, slotUpdates: [])
        await eventually { (try? scene.model.row(late.id)) != nil }
        let weeks = try scene.model.weeks
        #expect(weeks.count == 4)
        #expect(weeks[2].rows.map(\.name) == ["Upper B", "Lower A", "Watch day", "Upper A"])
    }

    @Test("A settings change that moves neither the units nor the week start leaves the list as it was")
    func unrelatedSettingsChange_keepsTheModel() async throws {
        let scene = HistoryScene(workouts: Self.twelve)
        let run = await scene.running()
        defer { run.cancel() }
        let before = try scene.model
        var settings = Fixtures.settingsLb
        settings.autoRest.toggle()
        try await scene.memory.settings.save(settings)
        // A later change that does move it: once it shows, the first change has been through the store.
        settings.units = .kg
        try await scene.memory.settings.save(settings)
        await eventually { (try? scene.model.rows.first?.meta.hasSuffix("kg")) == true }
        settings.units = .lb
        try await scene.memory.settings.save(settings)
        await eventually { (try? scene.model.rows.first?.meta.hasSuffix("lb")) == true }
        let isKept = try scene.model == before
        #expect(isKept)
    }
}

/// The workouts of `base`, but the first History observation ends at once, as GRDB's does when a read fails; the
/// ones after it follow `base`.
final nonisolated class FailingOnceHistory: WorkoutRepository {
    let base: any WorkoutRepository
    private let observations = Mutex(0)

    init(base: any WorkoutRepository) {
        self.base = base
    }

    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        let number = observations.withLock { count in
            count += 1
            return count
        }
        return number == 1 ? AsyncStream { $0.finish() } : base.observeHistoryEntries()
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
