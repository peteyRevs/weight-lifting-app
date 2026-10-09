import FeatureWorkout
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S4, criterion 9: what the app does when the workout's cover has closed (`Routes+Workout.swift`).
@MainActor
@Suite("Workout routes")
struct WorkoutRoutesTests {
    @Test(
        "Minimized and discarded leave the lifter on the tab, and the stack, the workout was opened over",
        arguments: [WorkoutRoute.minimized, .discarded]
    )
    func closedWithoutASave_leavesTheTabsAsTheyWere(_ route: WorkoutRoute) {
        let router = AppRouter()
        router.open(.settings, in: .library)
        router.resolve(route)
        #expect(router.selectedTab == .library)
        #expect(router[path: .library] == [.settings])
        #expect(router[path: .today].isEmpty)
    }

    @Test("Saved shows Today, where the session now stands as logged, and keeps every tab's stack")
    func saved_selectsToday() {
        let router = AppRouter()
        router.open(.settings, in: .library)
        router.resolve(.saved(Fixtures.sessionID))
        #expect(router.selectedTab == .today)
        #expect(router[path: .library] == [.settings])
        #expect(router[path: .today].isEmpty)
    }
}
