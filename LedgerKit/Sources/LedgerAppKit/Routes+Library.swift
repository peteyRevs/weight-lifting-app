import FeatureLibrary

extension AppRouter {
    /// Where the Library's routes go (architecture §4): an exercise's history is pushed on the stack of the tab
    /// that asked for it, which is the selected one, so the lifter's back button returns there.
    func resolve(_ route: LibraryRoute) {
        switch route {
        case let .exercise(id):
            open(.exercise(id), in: selectedTab)
        }
    }
}
