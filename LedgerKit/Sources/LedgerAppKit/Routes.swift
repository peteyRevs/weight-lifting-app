import Observation

/// The four tabs, in the tab bar's order (product decision #1).
nonisolated enum AppTab: Hashable, Sendable, CaseIterable {
    case today, program, library, history
}

/// Every screen a tab's stack can push. All four stacks are keyed by this one type (architecture §4), so any tab
/// can show any screen and a route can open a screen in another tab. A feature adds its screens' cases here and
/// maps its routes onto them in `Routes+<Feature>.swift`; until a screen's feature lands, its case draws a
/// `PlaceholderScreen` that names it.
nonisolated enum AppDestination: Hashable, Sendable {
    /// Settings (F14), which Today's gear opens (product decision #19).
    case settings
}

/// The shell's navigation state: the selected tab and each tab's stack. A feature never sees it: it emits a route,
/// and the app resolves the route into calls on the router.
@MainActor
@Observable
final class AppRouter {
    var selectedTab = AppTab.today
    private var paths: [AppTab: [AppDestination]] = [:]

    /// `tab`'s stack, the screen on top last; empty while the tab shows its root. Selecting another tab leaves it
    /// as it is, so the lifter finds each tab where they left it.
    subscript(path tab: AppTab) -> [AppDestination] {
        get { paths[tab, default: []] }
        set { paths[tab] = newValue }
    }

    /// Selects `tab` and pushes `destination` on its stack.
    func open(_ destination: AppDestination, in tab: AppTab) {
        selectedTab = tab
        paths[tab, default: []].append(destination)
    }
}
