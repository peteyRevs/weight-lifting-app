import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// A store on a `PumpSession` (S5's: held calls, a stream kept behind), with a date and a clock the test
/// moves together and haptics it reads.
@MainActor
struct LaggingRestBench {
    let session: PumpSession
    let store: WorkoutStore
    let haptics = FakeHaptics()
    let clock = RestProbeClock()
    let running: WorkoutState
    var following: Task<Void, Never>

    init() async throws {
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
        await eventually("the session's first update") { [store] in store.shown != nil }
    }

    var now: Date {
        Fixtures.now.addingTimeInterval(clock.elapsed / .seconds(1))
    }

    func played() async -> [Haptic] {
        await giveWay()
        return await haptics.played
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
