import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Synchronization

/// F13 S2 adversarial (G2): a detail's store over in-memory stores seen through `GatedWorkouts` (deletes counted,
/// held at a gate, or run before the gate) and, optionally, settings whose observation ends.
@MainActor
struct GatedDetailScene {
    let memory: InMemoryStores
    let workouts: GatedWorkouts
    let store: WorkoutDetailStore

    init(
        _ id: WorkoutID,
        workouts stored: [WorkoutState] = HistoryFixtures.twelve(),
        gate: GatedWorkouts.Gate = .none,
        settingsEnd: EndingSettings.Ending? = nil
    ) {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(workouts: stored, settings: Fixtures.settingsLb))
        let seen = GatedWorkouts(base: stores.workouts, gate: gate)
        let settings: any SettingsRepository = settingsEnd.map { EndingSettings(base: stores.settings, ending: $0) }
            ?? stores.settings
        memory = stores
        workouts = seen
        store = withTestDependencies {
            $0.workoutRepository = seen
            $0.settingsRepository = settings
        } operation: {
            WorkoutDetailStore(workout: id)
        }
    }

    func running() async -> Task<Void, Never> {
        let task = Task { await store.run() }
        await eventually { store.state != .loading }
        return task
    }
}

/// Polls `condition` until it holds or `limit` passes: for a test whose wanted state may never come (a known issue),
/// where `eventually` would wait for the suite's time limit. Asserts nothing about time.
@MainActor
func settles(within limit: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + limit
    while !condition() {
        guard ContinuousClock.now < deadline else {
            return false
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// Settings whose observation ends: at once, with no value, or after the first value. A GRDB settings row this app
/// can't read (a later version's payload) ends `observe()` at once, every time (`GRDBSettingsRepository.observe`).
final nonisolated class EndingSettings: SettingsRepository {
    enum Ending: Sendable {
        case atOnce
        case afterFirstValue
    }

    let base: any SettingsRepository
    let ending: Ending

    init(base: any SettingsRepository, ending: Ending) {
        self.base = base
        self.ending = ending
    }

    func load() async throws -> Settings {
        try await base.load()
    }

    func save(_ settings: Settings) async throws {
        try await base.save(settings)
    }

    func seedIfAbsent(_ settings: Settings) async throws {
        try await base.seedIfAbsent(settings)
    }

    func observe() -> AsyncStream<Settings> {
        switch ending {
        case .atOnce:
            return AsyncStream { $0.finish() }
        case .afterFirstValue:
            let settings = base
            return AsyncStream { continuation in
                let task = Task {
                    if let first = try? await settings.load() {
                        continuation.yield(first)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}

/// The workouts of `base`, every delete counted. With a gate, a delete waits for `open()`: `.before` waits before it
/// deletes (a cancelled wait throws `CancellationError` and deletes nothing, as GRDB's write does when its task is
/// cancelled before it starts), `.after` deletes first and returns only once opened.
final nonisolated class GatedWorkouts: WorkoutRepository {
    enum Gate: Sendable {
        case none
        case before
        case after
    }

    let base: any WorkoutRepository
    let gate: Gate
    private let deletes = Mutex(0)
    private let waiting = Mutex(0)
    /// Openings not yet taken: each lets one waiting delete through.
    private let openings = Mutex(0)

    init(base: any WorkoutRepository, gate: Gate) {
        self.base = base
        self.gate = gate
    }

    var deleteCount: Int {
        deletes.withLock { $0 }
    }

    /// A delete is waiting at the gate.
    var isWaiting: Bool {
        waiting.withLock { $0 > 0 }
    }

    /// Lets one waiting (or the next) delete through.
    func open() {
        openings.withLock { $0 += 1 }
    }

    /// Waits for an opening, or for the task's cancellation.
    private func wait() async {
        waiting.withLock { $0 += 1 }
        defer { waiting.withLock { $0 -= 1 } }
        while !Task.isCancelled {
            let isOpen = openings.withLock { openings in
                guard openings > 0 else {
                    return false
                }
                openings -= 1
                return true
            }
            if isOpen {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func delete(id: WorkoutID) async throws {
        deletes.withLock { $0 += 1 }
        switch gate {
        case .none:
            try await base.delete(id: id)
        case .before:
            await wait()
            try Task.checkCancellation()
            try await base.delete(id: id)
        case .after:
            try await base.delete(id: id)
            await wait()
        }
    }

    func observeWorkout(id: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        base.observeWorkout(id: id)
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
