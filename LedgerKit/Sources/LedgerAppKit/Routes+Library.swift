import FeatureLibrary

extension AppRouter {
    /// Where the Library's routes go (architecture §4): an exercise's history is pushed on the stack of the tab
    /// that asked for it, which is the selected one, so the lifter's back button returns there; a session of its log
    /// opens the History tab.
    func resolve(_ route: LibraryRoute) {
        switch route {
        case let .exercise(id):
            open(.exercise(id), in: selectedTab)
        case .openWorkout:
            // The workout's detail is F13's; until then, the History tab it will be pushed in, as Today's
            // RECENT goes (Pete's question 1, A).
            selectedTab = .history
        }
    }
}
