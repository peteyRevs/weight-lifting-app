import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Synchronization
import Testing

/// A `WorkoutDetailStore` of one workout and what it reads, under test: in-memory stores holding `workouts` (criterion
/// 1's twelve by default), the settings in pounds, and the workouts seen through `DetailWorkouts`, which counts
/// deletes and can fail them or end the workout's observation. The store is made inside `withTestDependencies`, so
/// its dependencies are the scene's for its whole life.
@MainActor
struct DetailScene {
    let memory: InMemoryStores
    let workouts: DetailWorkouts
    let store: WorkoutDetailStore

    init(
        _ id: WorkoutID,
        workouts stored: [WorkoutState] = HistoryFixtures.twelve(),
        failsDeletes: Bool = false,
        endsObservation: Bool = false
    ) {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(workouts: stored, settings: Fixtures.settingsLb))
        let seen = DetailWorkouts(base: stores.workouts, failsDeletes: failsDeletes, endsObservation: endsObservation)
        memory = stores
        workouts = seen
        store = withTestDependencies {
            $0.workoutRepository = seen
            $0.settingsRepository = stores.settings
        } operation: {
            WorkoutDetailStore(workout: id)
        }
    }

    /// The store's run, as the root's task runs it, once it shows anything but loading. A test cancels it where the
    /// view would go away.
    func running() async -> Task<Void, Never> {
        let task = Task { await store.run() }
        await eventually { store.state != .loading }
        return task
    }

    /// The model on screen.
    var model: WorkoutDetailModel {
        get throws {
            guard case let .loaded(model) = store.state else {
                throw HistoryScene.NotLoaded(state: "\(store.state)")
            }
            return model
        }
    }

    /// The model the presentation makes of the workout `id` as the in-memory store holds it now, in `units`.
    func expected(_ id: WorkoutID, units: Units = .lb) async throws -> WorkoutDetailModel {
        let values = memory.workouts.observeWorkout(id: id)
        var iterator = values.makeAsyncIterator()
        let recorded = try #require(await iterator.next() ?? nil)
        return WorkoutDetailPresentation.make(DetailFixtures.input(recorded, units: units))
    }
}

/// The inputs the detail's tests draw.
nonisolated enum DetailFixtures {
    /// `recorded` in `units`, at UTC in en_US.
    static func input(
        _ recorded: RecordedWorkout,
        units: Units = .lb,
        calendar: Calendar = Fixtures.calendar
    ) -> WorkoutDetailInput {
        WorkoutDetailInput(recorded: recorded, units: units, calendar: calendar, locale: Fixtures.locale)
    }

    /// Criterion 1's twelve workouts, each with the records it set against those before it.
    static func twelve() -> [RecordedWorkout] {
        HistoryPreviewData.recorded(HistoryFixtures.twelve())
    }
}

/// The workouts of `base`, with every delete counted; a delete fails when `failsDeletes`, and the workout's
/// observation ends at once when `endsObservation`, as GRDB's does when the workout can't be read.
final nonisolated class DetailWorkouts: WorkoutRepository {
    struct DeleteFailed: Error {}

    let base: any WorkoutRepository
    let failsDeletes: Bool
    let endsObservation: Bool
    private let deletes = Mutex(0)

    init(base: any WorkoutRepository, failsDeletes: Bool, endsObservation: Bool) {
        self.base = base
        self.failsDeletes = failsDeletes
        self.endsObservation = endsObservation
    }

    /// How many deletes were asked for.
    var deleteCount: Int {
        deletes.withLock { $0 }
    }

    func delete(id: WorkoutID) async throws {
        deletes.withLock { $0 += 1 }
        if failsDeletes {
            throw DeleteFailed()
        }
        try await base.delete(id: id)
    }

    func observeWorkout(id: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        endsObservation ? AsyncStream { $0.finish() } : base.observeWorkout(id: id)
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

    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
        base.observeRecent(limit: limit)
    }

    func historyEntries() async throws -> [HistoryEntry] {
        try await base.historyEntries()
    }

    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        base.observeHistoryEntries()
    }
}
