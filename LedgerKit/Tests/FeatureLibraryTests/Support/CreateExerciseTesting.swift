import Dependencies
@testable import FeatureLibrary
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport

/// The exercises of `base`, with what the sheet's tests need to see and to stop: every `save` counted, the next
/// `failures` saves refused, and the first `all()` read held until released (F12 S3, N16).
final nonisolated class WatchedExercises: ExerciseRepository, @unchecked Sendable {
    struct Refused: Error {}

    private let base: any ExerciseRepository
    private let lock = NSLock()
    private var saved: [Exercise] = []
    private var failures: Int
    private var holdsRead: Bool
    private var waiter: CheckedContinuation<Void, Never>?

    init(_ base: any ExerciseRepository, failures: Int = 0, holdsRead: Bool = false) {
        self.base = base
        self.failures = failures
        self.holdsRead = holdsRead
    }

    /// Every exercise `save` was called with, in order, the refused ones too.
    var saves: [Exercise] {
        lock.withLock { saved }
    }

    var isHoldingRead: Bool {
        lock.withLock { waiter != nil }
    }

    /// Lets the held read go on.
    func releaseRead() {
        let waiting = lock.withLock {
            holdsRead = false
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume()
    }

    func all() async throws -> [Exercise] {
        let holds = lock.withLock { holdsRead }
        if holds {
            await withCheckedContinuation { continuation in
                let resume = lock.withLock {
                    guard holdsRead else {
                        return true
                    }
                    waiter = continuation
                    return false
                }
                if resume {
                    continuation.resume()
                }
            }
        }
        return try await base.all()
    }

    func save(_ exercise: Exercise) async throws {
        let refuses = lock.withLock {
            saved.append(exercise)
            defer { failures -= 1 }
            return failures > 0
        }
        if refuses {
            throw Refused()
        }
        try await base.save(exercise)
    }

    func exercise(id: ExerciseID) async throws -> Exercise? {
        try await base.exercise(id: id)
    }

    func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise] {
        try await base.search(query, equipment: equipment, muscle: muscle)
    }

    func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws {
        try await base.seedIfNeeded(catalog, version: version)
    }

    func observeAll() -> AsyncStream<[Exercise]> {
        base.observeAll()
    }
}

/// A `CreateExerciseStore` and what it saves to, under test: in-memory stores seeded with the bundled catalog, behind
/// `WatchedExercises`; new ids counted from 0. A test that edits the lifter's own exercise saves it first.
@MainActor
struct CreateScene {
    let memory: InMemoryStores
    let exercises: WatchedExercises
    let store: CreateExerciseStore

    init(editing exercise: Exercise? = nil, failures: Int = 0, holdsRead: Bool = false) {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(
            catalog: LibraryFixtures.catalog,
            settings: Fixtures.settingsLb
        ))
        let watched = WatchedExercises(stores.exercises, failures: failures, holdsRead: holdsRead)
        memory = stores
        exercises = watched
        store = withTestDependencies {
            $0.exerciseRepository = watched
            $0.uuid = .incrementing
        } operation: {
            CreateExerciseStore(editing: exercise)
        }
    }

    /// Criterion 9's exercise, typed and chosen through the sheet's actions.
    func fillCriterion9() {
        store.send(.setName("Landmine Squeeze Press 2"))
        store.send(.setEquipment(.barbell))
        store.send(.setPrimaryMuscle(.chest))
        store.send(.setSecondaryMuscle(.shoulders, isOn: true))
        store.send(.setSecondaryMuscle(.triceps, isOn: true))
        store.send(.setPattern(.horizontalPush))
    }

    /// The stored exercise named `name`, if any.
    func stored(_ name: String) async throws -> Exercise? {
        try await memory.exercises.all().first { $0.name == name }
    }
}
