import Dependencies
@testable import FeatureToday
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Observation

// F09 S5 adversarial round 1 (G2): the store over the sources of `TodayStoreAdversarialSupport.swift`, and the
// waits and counts its attacks share.

/// A `TodayStore` whose five sources and whose reads the test drives by hand. Nothing has spoken until the
/// test says so (`speakAll()` gives each source the worked example's value).
@MainActor
struct ScriptedScene {
    let programs = Feed<Program?>()
    let settings = Feed<Settings>()
    let exercises = Feed<[Exercise]>()
    let recent = Feed<[WorkoutState]>()
    let session = Feed<WorkoutSessionUpdate>()
    let workouts: ScriptedWorkouts
    let clock = TestNow(Fixtures.now)
    let store: TodayStore

    /// The five sources by name, for a test that takes them in an order.
    nonisolated static let sources = ["program", "settings", "exercises", "recent", "session"]

    init() {
        let scripted = ScriptedWorkouts(feed: recent)
        workouts = scripted
        store = withTestDependencies { [programs, settings, exercises, session, clock] in
            $0.programRepository = ScriptedPrograms(feed: programs)
            $0.settingsRepository = ScriptedSettings(feed: settings)
            $0.exerciseRepository = ScriptedExercises(feed: exercises)
            $0.workoutRepository = scripted
            $0.statsQueries = InMemoryStores().stats
            $0.workoutSession = ScriptedSession(feed: session)
            $0.date = DateGenerator { clock.value }
        } operation: {
            TodayStore()
        }
    }

    /// Gives source `name` the worked example's value: the re-dated seed program, pounds and a Monday week,
    /// the catalog, no recent workout, no session.
    func speak(_ name: String) throws {
        switch name {
        case "program": try programs.yield(TodayFixtures.program())
        case "settings": settings.yield(Fixtures.settingsLb)
        case "exercises": try exercises.yield(ExerciseCatalog.seed())
        case "recent": recent.yield([])
        default: session.yield(WorkoutSessionUpdate(state: nil))
        }
    }

    func speakAll() throws {
        for name in Self.sources {
            try speak(name)
        }
    }

    /// The store running over these sources, once each source is listened to by the new run.
    func running() async -> Task<Void, Never> {
        let before = opened
        let task = Task { await store.run() }
        _ = await comes { zip(opened, before).allSatisfy { $0 > $1 } }
        return task
    }

    /// The streams each source has handed out, in the order of `sources`.
    var opened: [Int] {
        [programs.opened, settings.opened, exercises.opened, recent.opened, session.opened]
    }

    /// The streams of each source still listened to, in the order of `sources`.
    var listening: [Int] {
        [programs.listening, settings.listening, exercises.listening, recent.listening, session.listening]
    }
}

/// Counts each time the store sets its state, and keeps the states by name in order. Observation reports a
/// change before it is made, so the name is read on the main actor's next turn; two changes within one turn
/// are counted twice and named once, which is enough to see a pass through `loading`.
@MainActor
final class StatePublications {
    private(set) var changes = 0
    private(set) var phases: [String] = []
    private let store: TodayStore
    private var isWatching = true

    init(_ store: TodayStore) {
        self.store = store
        phases = [store.phase]
        watch()
    }

    func stop() {
        isWatching = false
    }

    private func watch() {
        withObservationTracking {
            _ = store.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isWatching else {
                    return
                }
                self.changes += 1
                if self.phases.last != self.store.phase {
                    self.phases.append(self.store.phase)
                }
                self.watch()
            }
        }
    }
}

/// Whether `condition` comes to hold, by watching what it reads (Observation). The time limit is no part of
/// passing: it only ends a wait that would never end, so that the test can say which case it was (a seed, a
/// step) instead of stopping at the suite's limit.
@MainActor
func settles(
    within limit: Duration = .seconds(20),
    _ condition: @escaping @MainActor @Sendable () -> Bool
) async -> Bool {
    let watcher = Task { @MainActor in
        for await holds in Observations({ condition() }) where holds {
            return true
        }
        return false
    }
    let limiter = Task {
        try? await Task.sleep(for: limit)
        watcher.cancel()
    }
    let holds = await watcher.value
    limiter.cancel()
    return holds
}

/// Lets what is queued on the main actor and on the other executors run, without waiting for time: for a
/// check that something did *not* happen. Each turn yields the main actor and passes through another
/// executor and back.
@MainActor
func drain(turns: Int = 200) async {
    for _ in 0 ..< turns {
        await Task.yield()
        await Task.detached {}.value
    }
}

/// Yields the main actor until `condition` holds, for a condition Observation cannot watch (a count behind a
/// lock). False when it never did within `turns`.
@MainActor
func comes(turns: Int = 20000, _ condition: () -> Bool) async -> Bool {
    for _ in 0 ..< turns {
        if condition() {
            return true
        }
        await Task.yield()
        await Task.detached {}.value
    }
    return condition()
}
