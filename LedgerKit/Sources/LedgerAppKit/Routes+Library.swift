import FeatureLibrary

extension AppRouter {
    /// Where the Library's routes go (architecture §4): an exercise's history, and a workout of its session log, are
    /// pushed on the stack of the tab that asked for them, which is the selected one, so the lifter's back button
    /// returns there (F13 question 1, built to A).
    func resolve(_ route: LibraryRoute) {
        switch route {
        case let .exercise(id):
            open(.exercise(id), in: selectedTab)
        case let .openWorkout(id):
            open(.workout(id), in: selectedTab)
        }
    }
}
