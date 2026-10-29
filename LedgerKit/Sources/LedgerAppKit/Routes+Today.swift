import FeatureToday
import FeatureWorkout
import LedgerDomain

extension AppRouter {
    /// Where each of Today's routes goes (architecture §4). Starting and resuming are the workout's own
    /// presenter's: `workout` shows its cover over the tabs, and shows a start it refuses itself, so Today
    /// adds no alert. A screen whose feature has not landed goes to the placeholder the shell has for it, so
    /// no button is dead.
    func resolve(_ route: TodayRoute, workout: WorkoutLauncher) {
        switch route {
        case let .startWorkout(program, weekIndex, day):
            workout.start(WorkoutSource(programID: program, weekIndex: weekIndex, dayTemplateID: day))
        case .resumeWorkout:
            workout.resume()
        case let .openWorkout(id):
            // A past workout opens on Today's own stack, so back returns to Today (F13 question 1, built to A).
            open(.workout(id), in: .today)
        case let .editWeek(_, weekIndex):
            // The builder edits the active program, which is the one Today shows.
            editProgramWeek(weekIndex)
        case .openProgram, .setUpProgram:
            // The next block is F24's, on the Program tab; setting up a program is F08's, which replaces the
            // tabs altogether while there is none.
            selectedTab = .program
        case .settings:
            // One Settings on the stack, however often it is asked for.
            if self[path: .today].last != .settings {
                open(.settings, in: .today)
            }
        }
    }
}
