import FeatureWorkout

extension AppRouter {
    /// What the app does when the workout's cover has closed (architecture §4). The cover is over the tabs,
    /// so closing it shows the tab the lifter left; Today follows the session itself, and shows Resume or
    /// the day's card without being told.
    func resolve(_ route: WorkoutRoute) {
        switch route {
        case .minimized, .discarded:
            // The lifter is back where the workout was opened from.
            break
        case .saved:
            // Today shows the session as logged (F10 criterion 10).
            selectedTab = .today
        case let .exercise(id):
            // A row of the receipt (F12 S3, N18; Pete's question 2, A): Today, as for "Done", one step deeper.
            // A push on the stack under the cover is no presentation, so it may happen as the cover goes down.
            open(.exercise(id), in: .today)
        }
    }
}
