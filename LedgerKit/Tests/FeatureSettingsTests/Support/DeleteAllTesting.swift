@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Synchronization
import Testing

/// What the "Delete all data" store tests share (F14 S3): the history a scene holds before the erase, the settings a
/// new US install starts from, and a scene whose erase is a `HeldReset` over its own stores.
@MainActor
enum DeleteAllScene {
    /// What a scene holds before the erase: the bundled catalog, the seed program and two weeks of its history.
    static func history() throws -> InMemoryStores.Seed {
        try InMemoryStores.Seed(
            catalog: ExerciseCatalog.seed(),
            programs: [Fixtures.seedProgram()],
            workouts: Fixtures.history(weeks: 2)
        )
    }

    /// A US lifter's new install (the scene's locale and calendar): pounds, weeks from Sunday.
    static var regional: Settings {
        Settings.regional(locale: Fixtures.locale, calendar: Fixtures.calendar)
    }

    /// The scene over `history()` whose "Delete all data" erases the scene's own stores through a `HeldReset`.
    /// `quietLive` puts a workout in progress that `current()` reports and `updates()` never does.
    static func erasingTheScenesStores(
        holds: Bool = false,
        failures: Int = 0,
        session: FakeWorkoutSessionClient = FakeWorkoutSessionClient(),
        quietLive: Bool = false
    ) throws -> (SettingsScene, HeldReset) {
        var held: HeldReset?
        let scene = try SettingsScene(seed: history(), session: quietLive ? QuietLiveSession() : session) { stores in
            let made = HeldReset(stores.reset, holds: holds, failures: failures)
            held = made
            return made
        }
        return try (scene, #require(held))
    }

    static func untilHeld(_ reset: HeldReset) async {
        while !reset.isHolding {
            await Task.yield()
        }
    }
}

/// A `DataReset` that counts its calls, holds each until released when asked to, and fails the next `failures`.
final class HeldReset: DataReset {
    struct Refused: Error {}

    private struct State {
        var calls: [Settings] = []
        var holds: Bool
        var failures: Int
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state: Mutex<State>
    private let base: any DataReset

    init(_ base: any DataReset, holds: Bool = false, failures: Int = 0) {
        self.base = base
        state = Mutex(State(holds: holds, failures: failures))
    }

    var calls: [Settings] {
        state.withLock { $0.calls }
    }

    var isHolding: Bool {
        state.withLock { !$0.waiters.isEmpty }
    }

    func release() {
        let waiters = state.withLock { state in
            state.holds = false
            defer { state.waiters = [] }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func eraseAll(restoring settings: Settings) async throws {
        let (holds, refuses) = state.withLock { state in
            state.calls.append(settings)
            defer { state.failures -= 1 }
            return (state.holds, state.failures > 0)
        }
        if holds {
            await withCheckedContinuation { continuation in
                state.withLock { $0.waiters.append(continuation) }
            }
        }
        try Task.checkCancellation()
        if refuses {
            throw Refused()
        }
        try await base.eraseAll(restoring: settings)
    }
}

/// A session whose `current()` holds a workout in progress that its `updates()` never told of: what the erase's own
/// check finds when a workout starts between the follower's last update and the erase.
actor QuietLiveSession: WorkoutSessionClient {
    struct Unused: Error {}

    func updates() -> AsyncStream<WorkoutSessionUpdate> {
        AsyncStream { $0.yield(WorkoutSessionUpdate(state: nil)) }
    }

    func current() -> WorkoutState? {
        EventBuilders.seedSession()
    }

    func start(_: WorkoutState) throws {
        throw Unused()
    }

    func apply(_: WorkoutEvent) throws -> WorkoutState {
        throw Unused()
    }

    func finish(endedAt _: Date) throws -> WorkoutState {
        throw Unused()
    }

    func discard(endedAt _: Date) throws {
        throw Unused()
    }
}
