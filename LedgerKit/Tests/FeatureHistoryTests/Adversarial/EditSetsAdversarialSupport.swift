import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Synchronization

/// F13 S3 adversarial (G2): the workouts of `base`, with the workout's observation in the test's hands and the batched
/// writes counted, failed on demand, or held at a gate until the test lets them go.
final nonisolated class ScriptedWorkouts: WorkoutRepository {
    struct Refused: Error {}

    let base: any WorkoutRepository
    private let saves = Mutex(0)
    private let failures = Mutex(0)
    private let isHolding: Bool
    private let gate = Mutex<[CheckedContinuation<Void, Never>]>([])
    private let scripted: Bool
    let values: AsyncStream<RecordedWorkout?>
    let observation: AsyncStream<RecordedWorkout?>.Continuation

    init(base: any WorkoutRepository, scripted: Bool = true, failures count: Int = 0, holdsSaves: Bool = false) {
        self.base = base
        self.scripted = scripted
        isHolding = holdsSaves
        failures.withLock { $0 = count }
        (values, observation) = AsyncStream.makeStream()
    }

    /// How many batched writes began.
    var saveCount: Int {
        saves.withLock { $0 }
    }

    /// Lets every held write go on.
    func release() {
        for waiting in gate.withLock({ held in
            defer { held = [] }
            return held
        }) {
            waiting.resume()
        }
    }

    var heldCount: Int {
        gate.withLock { $0.count }
    }

    func updateSets(_ sets: [WorkoutExerciseID: [LoggedSet]], of workout: WorkoutID) async throws {
        try Task.checkCancellation()
        saves.withLock { $0 += 1 }
        if isHolding {
            await withCheckedContinuation { waiting in
                gate.withLock { $0.append(waiting) }
            }
        }
        let fails = failures.withLock { left in
            defer { left = max(0, left - 1) }
            return left > 0
        }
        if fails {
            throw Refused()
        }
        try await base.updateSets(sets, of: workout)
    }

    func observeWorkout(id: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        scripted ? values : base.observeWorkout(id: id)
    }

    func delete(id: WorkoutID) async throws {
        try await base.delete(id: id)
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

/// A detail over `ScriptedWorkouts`, and the sheet its "Edit" opens, as the root makes it.
@MainActor
struct EditAdversarialScene {
    static let newest = HistoryFixtures.twelve()[11]

    let memory: InMemoryStores
    let workouts: ScriptedWorkouts
    let detail: WorkoutDetailStore

    init(scripted: Bool = false, failures: Int = 0, holdsSaves: Bool = false) {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(
            workouts: HistoryFixtures.twelve(),
            settings: Fixtures.settingsLb
        ))
        let seen = ScriptedWorkouts(
            base: stores.workouts,
            scripted: scripted,
            failures: failures,
            holdsSaves: holdsSaves
        )
        memory = stores
        workouts = seen
        detail = withTestDependencies {
            $0.workoutRepository = seen
            $0.settingsRepository = stores.settings
        } operation: {
            WorkoutDetailStore(workout: EditAdversarialScene.newest.id)
        }
    }

    func sheet(_ request: EditSetsRequest) -> EditSetsStore {
        withTestDependencies {
            $0.workoutRepository = workouts
            $0.settingsRepository = memory.settings
        } operation: {
            EditSetsStore(request)
        }
    }

    func run() -> Task<Void, Never> {
        let store = detail
        return Task { await store.run() }
    }

    func recorded(_ workout: WorkoutState) -> RecordedWorkout {
        RecordedWorkout(workout: workout, records: [])
    }
}
