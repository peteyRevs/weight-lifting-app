import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// A store on a `PumpSession` (S5's: held calls, a stream kept behind), with a date and a clock the test
/// moves together (`RestCoverClock`) and haptics it reads. Where no rest's task is started, nothing sleeps on
/// the clock, and moving it only moves the date.
@MainActor
struct LaggingRestBench {
    let session: PumpSession
    let store: WorkoutStore
    let haptics = FakeHaptics()
    let clock: RestCoverClock
    let running: WorkoutState
    var following: Task<Void, Never>

    init(clock: RestCoverClock = RestCoverClock()) async throws {
        self.clock = clock
        let workout = EventBuilders.seedSession()
        running = workout
        let client = PumpSession(live: workout)
        session = client
        store = withTestDependencies { [haptics, clock] in
            $0.workoutSession = client
            $0.haptics = haptics
            $0.continuousClock = clock
            $0.date = DateGenerator { Fixtures.now.addingTimeInterval(clock.elapsed / .seconds(1)) }
        } operation: {
            WorkoutStore()
        }
        following = Task { [store] in await store.follow() }
        await observed("the session's first update") { [store] in store.shown != nil }
    }

    var now: Date {
        Fixtures.now.addingTimeInterval(clock.elapsed / .seconds(1))
    }

    func played() async -> [Haptic] {
        await giveWay()
        return await haptics.played
    }
}

extension LaggingRestBench {
    /// Starts the task that keeps the shown rest's time, as the root does, and returns once it is asleep on
    /// the clock or has ended.
    func keepingTime() async -> RestKeeper {
        let keeper = RestKeeper(store)
        await eventually("the rest's task asleep") { clock.asleep == 1 || keeper.isDone }
        return keeper
    }

    /// `duration` goes by a wait at a time (`RestCoverClock.run`): time moves past each of the rest's waits
    /// only once `keeper` sleeps again or has ended. A single `TestClock` jump over a long rest can leave the
    /// woken task to start its next wait after the jump, a wait nothing ends (issue #116).
    func run(_ duration: Duration, _ keeper: RestKeeper) async {
        await clock.run(duration) { keeper.isDone }
    }
}

/// Haptics that record, and can be made to keep each call from returning until the test lets it.
actor GatedHaptics: HapticsClient {
    private(set) var played: [Haptic] = []
    private var holds = false
    private var parked: [CheckedContinuation<Void, Never>] = []

    func play(_ haptic: Haptic) async {
        played.append(haptic)
        if holds {
            await withCheckedContinuation { parked.append($0) }
        }
    }

    func hold() {
        holds = true
    }

    func release() {
        holds = false
        for call in parked {
            call.resume()
        }
        parked = []
    }
}
