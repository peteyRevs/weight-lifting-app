@testable import LedgerAppKit
import Testing

/// F09 S1 criteria 1 and 3: four tabs in the bar's order, Today first; a stack per tab, kept while another tab is
/// selected; `open(_:in:)` selects the tab and pushes there.
@MainActor
@Suite("AppRouter")
struct AppRouterTests {
    @Test("The tabs are Today, Program, Library, History, in that order")
    func tabs_areInTheBarsOrder() {
        #expect(AppTab.allCases == [.today, .program, .library, .history])
    }

    @Test("A new router selects Today, and every tab shows its root")
    func newRouter_selectsToday_withEmptyStacks() {
        let router = AppRouter()
        #expect(router.selectedTab == .today)
        #expect(AppTab.allCases.allSatisfy { router[path: $0].isEmpty })
    }

    @Test("Opening a destination in the selected tab pushes it on that tab's stack")
    func open_inTheSelectedTab_pushesOnItsStack() {
        let router = AppRouter()
        router.open(.settings, in: .today)
        #expect(router.selectedTab == .today)
        #expect(router[path: .today] == [.settings])
        #expect(Self.others(than: .today).allSatisfy { router[path: $0].isEmpty })
    }

    @Test("Opening a destination in another tab selects that tab and pushes there", arguments: AppTab.allCases)
    func open_inAnotherTab_selectsItAndPushesThere(_ tab: AppTab) {
        let router = AppRouter()
        router.open(.settings, in: tab)
        #expect(router.selectedTab == tab)
        #expect(router[path: tab] == [.settings])
        #expect(Self.others(than: tab).allSatisfy { router[path: $0].isEmpty })
    }

    @Test("Opening twice pushes twice: the second screen is on top")
    func open_twice_stacksInOrder() {
        let router = AppRouter()
        router.open(.settings, in: .library)
        router.open(.settings, in: .library)
        #expect(router[path: .library] == [.settings, .settings])
    }

    @Test("A tab keeps its stack while another tab is selected, and when the lifter comes back")
    func selectingAnotherTab_keepsEachStack() {
        let router = AppRouter()
        router.open(.settings, in: .library)
        router.selectedTab = .today
        #expect(router[path: .library] == [.settings])
        router.open(.settings, in: .history)
        router.selectedTab = .library
        #expect(router[path: .library] == [.settings])
        #expect(router[path: .history] == [.settings])
        #expect(router[path: .today].isEmpty)
    }

    @Test("Going back, which the stack does by writing the path, pops that tab alone")
    func writingAPath_popsThatTabAlone() {
        let router = AppRouter()
        router.open(.settings, in: .today)
        router.open(.settings, in: .program)
        router[path: .today] = []
        #expect(router[path: .today].isEmpty)
        #expect(router[path: .program] == [.settings])
        #expect(router.selectedTab == .program)
    }

    private static func others(than tab: AppTab) -> [AppTab] {
        AppTab.allCases.filter { $0 != tab }
    }
}
