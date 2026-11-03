import FeatureLibrary

extension AppRouter {
    /// Where the Library's routes go (architecture §4): an exercise's history, and a workout of its session log, are
    /// pushed on the stack of `tab`, the tab whose screen asked for them (F13-S1-6), so the lifter's back button
    /// returns there (F13 question 1, built to A).
    func resolve(_ route: LibraryRoute, from tab: AppTab) {
        switch route {
        case let .exercise(id):
            open(.exercise(id), in: tab)
        case let .openWorkout(id):
            open(.workout(id), in: tab)
        }
    }
}
