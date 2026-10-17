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
        case .openWorkout:
            // The workout's detail is F13's; until then, the History tab it will be pushed in (F13
            // criterion 6).
            selectedTab = .history
        case .editWeek, .openProgram, .setUpProgram:
            // The week editor and the next block are F11's and F24's, on the Program tab; setting up a
            // program is F08's, which replaces the tabs altogether while there is none.
            selectedTab = .program
        case .settings:
            // One Settings on the stack, however often it is asked for.
            if self[path: .today].last != .settings {
                open(.settings, in: .today)
            }
        }
    }
}
