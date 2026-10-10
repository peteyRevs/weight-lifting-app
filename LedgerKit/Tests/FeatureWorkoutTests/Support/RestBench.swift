import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport

/// A test clock that counts the sleeps begun on it, so a test can wait until the store's task is
/// asleep before it moves time: no wait is missed, and none is on real time.
struct CountingClock: Clock {
    let base = TestClock<Duration>()
    let sleeps = LockIsolated(0)

    var now: TestClock<Duration>.Instant {
        base.now
    }

    var minimumResolution: Duration {
        base.minimumResolution
    }

    func sleep(until deadline: TestClock<Duration>.Instant, tolerance: Duration?) async throws {
        // Counted, then registered with the test clock before this task first suspends.
        sleeps.withValue { $0 += 1 }
        try await base.sleep(until: deadline, tolerance: tolerance)
    }
}

/// The store's task that keeps the rest's time, as `WorkoutRoot`'s `.task(id: store.shownRest)` runs it.
@MainActor
final class RestKeeper {
    let task: Task<Void, Never>
    private(set) var isDone = false

    init(_ store: WorkoutStore) {
        var finish: (@MainActor () -> Void)?
        task = Task {
            await store.keepRestTime()
            finish?()
        }
        finish = { [weak self] in self?.isDone = true }
    }
}

/// A cover's store on the fake session, with a date and a clock that move only when the test moves
/// them, and haptics it can read.
@MainActor
struct RestBench {
    let scene: WorkoutScene
    let store: WorkoutStore
    let following: Task<Void, Never>
    let haptics = FakeHaptics()
    let clock = CountingClock()
    let date = LockIsolated(Fixtures.now)
    let running: WorkoutState

    init(_ running: WorkoutState? = nil) async throws {
        let workout = try running ?? Fixtures.seedSession()
        self.running = workout
        scene = try WorkoutScene.onFake(live: workout)
        store = scene.store { [haptics, clock, date] in
            $0.haptics = haptics
            $0.continuousClock = clock
            $0.date = DateGenerator { date.value }
        }
        following = Task { [store] in await store.follow() }
        await eventually { [store] in store.shown != nil }
    }

    /// The first set of the first exercise.
    var first: SetID {
        running.exercises[0].sets[0].id
    }

    /// The first exercise's rest, in seconds.
    var rest: TimeInterval {
        running.exercises[0].rest.duration / .seconds(1)
    }

    /// Sends the taps and applies them, then waits for the page to show the session's workout.
    func tap(_ edits: WorkoutEdit...) async throws {
        for edit in edits {
            store.send(.edit(edit))
        }
        await store.drain()
        let truth = try await scene.session.current()
        await eventually { [store] in store.shown == truth }
    }

    /// Starts the task that keeps the shown rest's time, and returns once it is asleep or has ended.
    func keepingTime() async -> RestKeeper {
        let before = clock.sleeps.value
        let keeper = RestKeeper(store)
        await settled(keeper, after: before)
        return keeper
    }

    /// Waits, by giving way and never by time, until `keeper` has begun a sleep since `sleeps`, or ended.
    func settled(_ keeper: RestKeeper, after sleeps: Int) async {
        while clock.sleeps.value == sleeps, !keeper.isDone {
            await Task.yield()
        }
    }

    /// A second goes by, on the wall clock and on the store's clock together: the task wakes at the
    /// rest's next second, reads the date, and is asleep again, or has ended, when this returns.
    func second(_ keeper: RestKeeper) async {
        let before = clock.sleeps.value
        date.withValue { $0 += 1 }
        await clock.base.advance(by: .seconds(1))
        await settled(keeper, after: before)
    }

    func seconds(_ count: Int, _ keeper: RestKeeper) async {
        for _ in 0 ..< count {
            await second(keeper)
        }
    }

    /// The app was suspended for `seconds` while a wait was pending: the wall clock moved on, and the
    /// wait ends on the return.
    func suspended(_ seconds: TimeInterval, _ keeper: RestKeeper) async {
        let before = clock.sleeps.value
        date.withValue { $0 += seconds }
        await clock.base.advance(by: .seconds(1))
        await settled(keeper, after: before)
    }

    var panel: RestPanelModel? {
        store.model.rest
    }
}

/// Waits until `haptics` has played exactly `wanted`, by asking the actor between yields; the suite's time
/// limit ends a wait that never holds.
@MainActor
func eventuallyPlayed(_ haptics: FakeHaptics, _ wanted: [Haptic]) async {
    while await haptics.played != wanted {
        await Task.yield()
    }
}

extension WorkoutScreenModel {
    /// The rest panel, when a workout is on screen and shows a rest.
    var rest: RestPanelModel? {
        guard case let .workout(workout) = self else {
            return nil
        }
        return workout.rest
    }
}
