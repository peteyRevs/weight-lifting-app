import FeatureHistory

extension AppRouter {
    /// Where the History screens' routes go (architecture §4), on the stack of `tab`, the tab whose screen asked
    /// (F13-S1-6): a workout's detail, and an exercise's history over it, are pushed there, so back returns to where
    /// the lifter tapped (F13 question 1, built to A); a closed detail is popped only while it is on top of that
    /// stack, so a second close, or one after the swipe back, pops nothing; "Go to Today" selects Today.
    func resolve(_ route: HistoryRoute, from tab: AppTab) {
        switch route {
        case let .workout(id):
            open(.workout(id), in: tab)
        case .today:
            selectedTab = .today
        case let .exercise(id):
            open(.exercise(id), in: tab)
        case let .closeWorkout(id):
            if self[path: tab].last == .workout(id) {
                self[path: tab].removeLast()
            }
        }
    }
}
