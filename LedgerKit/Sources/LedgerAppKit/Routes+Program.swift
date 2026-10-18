import FeatureProgram

extension AppRouter {
    /// Where each of the Program screens' routes goes (architecture §4): the Day editor is pushed on the
    /// Program tab's stack, one screen per route, and its close pops it.
    func resolve(_ route: ProgramRoute) {
        switch route {
        case let .day(day, weekIndex):
            open(.day(day, weekIndex: weekIndex), in: .program)
        case .closeDay:
            // Only a Day editor on top is popped, so a second close, or one that comes after the swipe back
            // has popped it, pops nothing.
            if case .day? = self[path: .program].last {
                self[path: .program].removeLast()
            }
        }
    }

    /// Today's "Edit this week": the Program tab, back at the builder, with that week selected. A Day editor
    /// open there is popped (Pete's question 2, A: "Edit this week" always lands on the builder).
    func editProgramWeek(_ weekIndex: Int) {
        selectedTab = .program
        self[path: .program] = []
        requestProgramWeek(weekIndex)
    }
}
