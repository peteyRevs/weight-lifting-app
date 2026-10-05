import Foundation
@testable import LedgerAppKit
import Observation
import Synchronization
import Testing

/// F09 S1 adversarial round 1: `AppRouter` against the brief's amendments (S1 criteria 1 and 3): Today selected at
/// launch, four tabs in the tab bar's order, one stack per tab that survives the lifter switching away and back,
/// and `open(_:in:)` selecting the tab and pushing there. Random sequences are checked against a model.
@MainActor
@Suite("Adversarial F09 S1 · AppRouter")
struct AppRouterAdversarialTests {
    @Test("A new router shows Today, and every tab at its root")
    func newRouter_showsTodayAtItsRoot() {
        let router = AppRouter()
        #expect(router.selectedTab == .today)
        for tab in AppTab.allCases {
            #expect(router[path: tab].isEmpty)
        }
    }

    @Test("The tabs are Today, Program, Library, History, in that order (product decision #1)")
    func tabs_areInTheTabBarsOrder() {
        #expect(AppTab.allCases == [.today, .program, .library, .history])
        #expect(Set(AppTab.allCases).count == 4)
    }

    @Test(
        "Opening a destination in the selected tab pushes it there and selects nothing else",
        arguments: AppTab.allCases
    )
    func open_inTheSelectedTab_pushesThere(_ tab: AppTab) {
        let router = AppRouter()
        router.selectedTab = tab
        router.open(.settings, in: tab)
        #expect(router.selectedTab == tab)
        #expect(router[path: tab] == [.settings])
        for other in AppTab.allCases where other != tab {
            #expect(router[path: other].isEmpty)
        }
    }

    @Test(
        "Opening a destination in another tab selects that tab and pushes on its stack alone",
        arguments: AppTab.allCases
    )
    func open_inAnotherTab_selectsItAndPushesThere(_ tab: AppTab) throws {
        let start = try #require(AppTab.allCases.first { $0 != tab })
        let router = AppRouter()
        router.selectedTab = start
        router.open(.settings, in: start)
        router.open(.settings, in: tab)
        #expect(router.selectedTab == tab)
        #expect(router[path: tab] == [.settings])
        #expect(router[path: start] == [.settings], "the tab the lifter left keeps its stack")
    }

    @Test("Selecting another tab and coming back leaves every stack as it was")
    func selectingAway_keepsEveryStack() {
        let router = AppRouter()
        router.open(.settings, in: .today)
        router.open(.settings, in: .today)
        router.open(.settings, in: .library)
        let before = AppTab.allCases.map { router[path: $0] }
        for tab in AppTab.allCases + AppTab.allCases.reversed() {
            router.selectedTab = tab
            #expect(AppTab.allCases.map { router[path: $0] } == before)
        }
    }

    @Test("Opening the same destination twice pushes it twice, and a deep stack keeps its order and depth")
    func open_twice_pushesTwice() {
        let router = AppRouter()
        for depth in 1 ... 200 {
            router.open(.settings, in: .history)
            #expect(router[path: .history].count == depth)
        }
        #expect(router[path: .history].allSatisfy { $0 == .settings })
        router[path: .history].removeLast()
        #expect(router[path: .history].count == 199, "the back button pops one")
        router[path: .history] = []
        #expect(router[path: .history].isEmpty, "a tap on the selected tab pops to the root")
        #expect(router.selectedTab == .history)
    }

    @Test("A view that reads a tab's path, or the selected tab, is told when `open` changes it")
    func open_notifiesObservers() {
        let router = AppRouter()
        let pathChanged = Mutex(false)
        let tabChanged = Mutex(false)
        withObservationTracking {
            _ = router[path: .library]
        } onChange: {
            pathChanged.withLock { $0 = true }
        }
        withObservationTracking {
            _ = router.selectedTab
        } onChange: {
            tabChanged.withLock { $0 = true }
        }
        router.open(.settings, in: .library)
        #expect(pathChanged.withLock { $0 })
        #expect(tabChanged.withLock { $0 })
    }

    @Test(
        "Random selections, opens, pops and returns to the root match the model: one stack per tab",
        arguments: 1 ... 300
    )
    func randomSequences_matchTheModel(seed: Int) {
        var random = AdversarialRandom(seed: seed)
        let router = AppRouter()
        var model = Model()
        for step in 0 ..< 60 {
            let tab = AppTab.allCases[Int.random(in: 0 ..< 4, using: &random)]
            switch Int.random(in: 0 ..< 5, using: &random) {
            case 0:
                router.selectedTab = tab
                model.selected = tab
            case 1, 2:
                router.open(.settings, in: tab)
                model.selected = tab
                model.paths[tab, default: []].append(.settings)
            case 3:
                // The back button, as `NavigationStack` writes it through the path's binding: on the selected tab.
                let shown = model.selected
                if !model.paths[shown, default: []].isEmpty {
                    router[path: shown].removeLast()
                    model.paths[shown, default: []].removeLast()
                }
            default:
                router[path: tab] = []
                model.paths[tab] = []
            }
            #expect(router.selectedTab == model.selected, "seed \(seed) step \(step)")
            for each in AppTab.allCases {
                #expect(router[path: each] == model.paths[each, default: []], "seed \(seed) step \(step) tab \(each)")
            }
        }
    }
}

extension AppRouterAdversarialTests {
    /// What the brief says the router holds: the selected tab, and a stack per tab.
    struct Model {
        var selected = AppTab.today
        var paths: [AppTab: [AppDestination]] = [:]
    }
}
