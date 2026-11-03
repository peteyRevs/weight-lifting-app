import FeatureHistory
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S1 and S2, criteria 2, 5 and 6: where the History screens' routes go (`Routes+History.swift`). Each lands on the
/// stack of the tab whose screen sent it (F13-S1-6), whichever tab is selected when it arrives: a row's detail is
/// pushed there (F13 question 1, built to A), one screen per route, and a detail's row pushes its exercise's history
/// over it; a closed detail is popped only while it is on top; the empty list's "Go to Today" selects Today and leaves
/// every stack as it was.
@MainActor
@Suite("History routes")
struct HistoryRouteMappingTests {
    private static let upperA = WorkoutID(Fixtures.uuid(461))
    private static let lowerA = WorkoutID(Fixtures.uuid(462))
    private static let bench = ExerciseID(Fixtures.uuid(463))

    @Test("6. A row's route pushes that workout's detail on the History tab's stack, one screen per route")
    func workout_pushesItsDetailOnTheHistorysStack() {
        let router = AppRouter()
        router.selectedTab = .history
        router.resolve(HistoryRoute.workout(Self.upperA), from: .history)
        #expect(router.selectedTab == .history)
        #expect(router[path: .history] == [.workout(Self.upperA)])
        router.resolve(HistoryRoute.workout(Self.lowerA), from: .history)
        #expect(router[path: .history] == [.workout(Self.upperA), .workout(Self.lowerA)])
        #expect(AppTab.allCases.map { router[path: $0].count } == [0, 0, 0, 2])
    }

    @Test("F13-S1-6. A route that arrives after a tab switch lands on the stack it came from, not the selected one")
    func lateRoute_landsOnItsOwnTab() {
        let router = AppRouter()
        router.open(.workout(Self.upperA), in: .today)
        router.selectedTab = .library
        router.resolve(HistoryRoute.exercise(Self.bench), from: .today)
        #expect(router[path: .today] == [.workout(Self.upperA), .exercise(Self.bench)], "back returns to the detail")
        #expect(router[path: .library] == [])
    }

    @Test("F13-S1-6. A row's detail sent from History while Today is selected is pushed on History's stack")
    func workout_fromAnUnselectedTab_landsOnItsOwnStack() {
        let router = AppRouter()
        router.selectedTab = .today
        router.resolve(HistoryRoute.workout(Self.upperA), from: .history)
        #expect(router[path: .history] == [.workout(Self.upperA)])
        #expect(router[path: .today] == [])
    }

    @Test("3. A detail's row pushes its exercise's history over the detail, on the same tab")
    func exercise_pushesTheHistoryOverTheDetail() {
        let router = AppRouter()
        router.open(.workout(Self.upperA), in: .history)
        router.resolve(HistoryRoute.exercise(Self.bench), from: .history)
        #expect(router.selectedTab == .history)
        #expect(router[path: .history] == [.workout(Self.upperA), .exercise(Self.bench)])
    }

    @Test("5. Closing a detail pops it while it is on top, once; it pops nothing under another screen or another tab")
    func closeWorkout_popsOnlyTheDetailOnTop() {
        let router = AppRouter()
        router.open(.workout(Self.upperA), in: .today)
        router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .today)
        #expect(router[path: .today] == [])
        router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .today)
        #expect(router[path: .today] == [], "a second close pops nothing")
        router.open(.workout(Self.upperA), in: .history)
        router.open(.exercise(Self.bench), in: .history)
        router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .history)
        #expect(router[path: .history] == [.workout(Self.upperA), .exercise(Self.bench)], "not under another screen")
        router.resolve(HistoryRoute.closeWorkout(Self.lowerA), from: .history)
        router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .today)
        #expect(router[path: .history].count == 2, "another workout, or another tab, pops nothing")
    }

    @Test("2. Go to Today selects Today and pushes nothing; each stack stays as the lifter left it")
    func today_selectsTodayAndPushesNothing() {
        let router = AppRouter()
        router.open(.settings, in: .today)
        router.selectedTab = .history
        router.resolve(HistoryRoute.today, from: .history)
        #expect(router.selectedTab == .today)
        #expect(router[path: .today] == [.settings])
        #expect(router[path: .history] == [])
    }
}
