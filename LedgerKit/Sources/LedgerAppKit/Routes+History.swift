import FeatureHistory

extension AppRouter {
    /// Where the History tab's routes go (architecture §4): a workout's detail is pushed on the stack of the tab that
    /// asked for it, which is the selected one (F13 question 1, built to A); "Go to Today" selects Today.
    func resolve(_ route: HistoryRoute) {
        switch route {
        case let .workout(id):
            open(.workout(id), in: selectedTab)
        case .today:
            selectedTab = .today
        }
    }
}
