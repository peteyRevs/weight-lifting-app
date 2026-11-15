import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// A clock a bench's test moves, and the date with it: `RestProbeClock`, or `RestCoverClock` for a test that
/// moves time over many of the rest's waits (`TestClock` runs four `megaYield`s of background tasks for each).
nonisolated protocol BenchClock: Clock<Duration> where Instant == TestClock<Duration>.Instant {
    /// The time since the clock was made.
    var elapsed: Duration { get }
}

extension RestProbeClock: BenchClock {}
extension RestCoverClock: BenchClock {}

/// A store on a `PumpSession` (S5's: held calls, a stream kept behind), with a date and a clock the test
/// moves together and haptics it reads.
@MainActor
struct LaggingRestBench<Moved: BenchClock> {
    let session: PumpSession
    let store: WorkoutStore
    let haptics = FakeHaptics()
    let clock: Moved
    let running: WorkoutState
    var following: Task<Void, Never>

    init(clock: Moved) async throws {
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

extension LaggingRestBench where Moved == RestProbeClock {
    init() async throws {
        try await self.init(clock: RestProbeClock())
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
