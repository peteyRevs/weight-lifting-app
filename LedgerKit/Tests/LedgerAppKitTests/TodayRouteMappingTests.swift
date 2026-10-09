import FeatureToday
@testable import FeatureWorkout
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S5, criterion 9: where each of Today's routes goes (`Routes+Today.swift`). The launcher only takes a
/// request here: nothing runs it, so no store is read.
@MainActor
@Suite("Today routes")
struct TodayRouteMappingTests {
    private static let day = DayTemplateID(Fixtures.uuid(331))
    private static let source = WorkoutSource(programID: Fixtures.programID, weekIndex: 3, dayTemplateID: day)
    private static let start = TodayRoute.startWorkout(program: Fixtures.programID, weekIndex: 3, day: day)

    @Test("Start workout asks the launcher for that program, week and day, and moves no tab")
    func startWorkout_asksTheLauncher() {
        let router = AppRouter()
        let workout = WorkoutLauncher()
        router.resolve(Self.start, workout: workout)
        #expect(workout.request == WorkoutLaunchRequest(number: 1, job: .start(Self.source)))
        #expect(workout.phase == .working)
        #expect(router.selectedTab == .today)
        #expect(router[path: .today].isEmpty)
    }

    @Test("A double tap on Start workout is one request: the launcher drops the second while it answers the first")
    func startWorkout_twice_isOneRequest() {
        let router = AppRouter()
        let workout = WorkoutLauncher()
        router.resolve(Self.start, workout: workout)
        router.resolve(Self.start, workout: workout)
        router.resolve(.resumeWorkout, workout: workout)
        #expect(workout.request == WorkoutLaunchRequest(number: 1, job: .start(Self.source)))
    }

    @Test("Resume asks the launcher for the live workout")
    func resumeWorkout_asksTheLauncher() {
        let router = AppRouter()
        let workout = WorkoutLauncher()
        router.resolve(.resumeWorkout, workout: workout)
        #expect(workout.request == WorkoutLaunchRequest(number: 1, job: .resume))
        #expect(router.selectedTab == .today)
    }

    @Test("Settings is pushed on Today's stack, once however often it is asked for")
    func settings_isPushedOnce() {
        let router = AppRouter()
        let workout = WorkoutLauncher()
        router.selectedTab = .library
        router.resolve(.settings, workout: workout)
        router.resolve(.settings, workout: workout)
        #expect(router.selectedTab == .today)
        #expect(router[path: .today] == [.settings])
        #expect(workout.request == nil)
    }

    @Test("A past workout goes to the History tab, until F13 pushes its detail there")
    func openWorkout_selectsHistory() {
        let router = AppRouter()
        let workout = WorkoutLauncher()
        router.resolve(.openWorkout(Fixtures.sessionID), workout: workout)
        #expect(router.selectedTab == .history)
        #expect(AppTab.allCases.map { router[path: $0].count } == [0, 0, 0, 0])
        #expect(workout.request == nil)
    }

    @Test(
        "The week editor, the next block and program set-up go to the Program tab, until their features land",
        arguments: [TodayRoute.editWeek(program: Fixtures.programID, weekIndex: 2), .openProgram, .setUpProgram]
    )
    func programRoutes_selectProgram(_ route: TodayRoute) {
        let router = AppRouter()
        let workout = WorkoutLauncher()
        router.resolve(route, workout: workout)
        #expect(router.selectedTab == .program)
        #expect(AppTab.allCases.map { router[path: $0].count } == [0, 0, 0, 0])
        #expect(workout.request == nil)
    }
}
