import FeatureHistory
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S1, criteria 2 and 6: where the History tab's routes go (`Routes+History.swift`). A row's detail is pushed on
/// the selected tab's stack, the one that asked for it (F13 question 1, built to A), one screen per route; the empty
/// list's "Go to Today" selects Today and leaves every stack as it was.
@MainActor
@Suite("History routes")
struct HistoryRouteMappingTests {
    private static let upperA = WorkoutID(Fixtures.uuid(461))
    private static let lowerA = WorkoutID(Fixtures.uuid(462))

    @Test("6. A row's route pushes that workout's detail on the History tab's stack, one screen per route")
    func workout_pushesItsDetailOnTheHistorysStack() {
        let router = AppRouter()
        router.selectedTab = .history
        router.resolve(HistoryRoute.workout(Self.upperA))
        #expect(router.selectedTab == .history)
        #expect(router[path: .history] == [.workout(Self.upperA)])
        router.resolve(HistoryRoute.workout(Self.lowerA))
        #expect(router[path: .history] == [.workout(Self.upperA), .workout(Self.lowerA)])
        #expect(AppTab.allCases.map { router[path: $0].count } == [0, 0, 0, 2])
    }

    @Test("2. Go to Today selects Today and pushes nothing; each stack stays as the lifter left it")
    func today_selectsTodayAndPushesNothing() {
        let router = AppRouter()
        router.open(.settings, in: .today)
        router.selectedTab = .history
        router.resolve(HistoryRoute.today)
        #expect(router.selectedTab == .today)
        #expect(router[path: .today] == [.settings])
        #expect(router[path: .history] == [])
    }
}
