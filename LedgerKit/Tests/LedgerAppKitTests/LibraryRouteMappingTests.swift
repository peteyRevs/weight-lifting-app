import FeatureLibrary
import FeatureWorkout
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S1 and S2, criteria 3 and 11: where the Library's routes go (`Routes+Library.swift`). A row's history is
/// pushed on the stack of the tab that asked for it, one screen per route; a session opens its workout there.
/// Sanctioned edit of F13 S2 (F13-S1-6): each route is resolved with the tab whose screen sent it.
/// F12 S3, N18: a row of the workout's receipt shows the history on Today's stack (`Routes+Workout.swift`).
@MainActor
@Suite("Library routes")
struct LibraryRouteMappingTests {
    private static let bench = ExerciseID(Fixtures.uuid(451))
    private static let squat = ExerciseID(Fixtures.uuid(452))

    @Test("3. A row's route pushes that exercise's history on the Library tab's stack, one screen per route")
    func exercise_pushesItsHistoryOnTheLibrarysStack() {
        let router = AppRouter()
        router.selectedTab = .library
        router.resolve(LibraryRoute.exercise(Self.bench), from: .library)
        #expect(router.selectedTab == .library)
        #expect(router[path: .library] == [.exercise(Self.bench)])
        router.resolve(LibraryRoute.exercise(Self.squat), from: .library)
        #expect(router[path: .library] == [.exercise(Self.bench), .exercise(Self.squat)])
        #expect(AppTab.allCases.map { router[path: $0].count } == [0, 0, 2, 0])
    }

    @Test("3. The history is pushed on the tab that asked, and the tab stays selected")
    func exercise_pushesOnTheSelectedTab() {
        let router = AppRouter()
        router.selectedTab = .history
        router.resolve(LibraryRoute.exercise(Self.bench), from: .history)
        #expect(router.selectedTab == .history)
        #expect(router[path: .history] == [.exercise(Self.bench)])
        #expect(router[path: .library] == [])
    }

    /// F13 S2 (review S2-R1-2): the route lands on the tab that sent it, not the selected one.
    @Test("F13-S1-6. A row's history sent from the Library while Today is selected is pushed on the Library's stack")
    func exercise_fromAnUnselectedTab_landsOnItsOwnStack() {
        let router = AppRouter()
        router.selectedTab = .today
        router.resolve(LibraryRoute.exercise(Self.bench), from: .library)
        #expect(router[path: .library] == [.exercise(Self.bench)])
        #expect(router[path: .today] == [])
    }

    /// Sanctioned edit of F13 S1 (C3): the workout's detail is pushed over the exercise's history (F13 question 1,
    /// built to A), where the session selected the History tab until then.
    @Test("11. A session of the log pushes its workout's detail over the history, on the same tab")
    func openWorkout_pushesItsDetailOverTheHistory() {
        let router = AppRouter()
        let session = WorkoutID(Fixtures.uuid(453))
        router.open(.exercise(Self.bench), in: .library)
        router.resolve(LibraryRoute.openWorkout(session), from: .library)
        #expect(router.selectedTab == .library)
        #expect(router[path: .library] == [.exercise(Self.bench), .workout(session)], "back returns to the history")
        #expect(router[path: .history] == [])
    }

    @Test("N18. A receipt row's route shows Today with the exercise's history pushed; other stacks are kept")
    func receiptRow_pushesTheHistoryOnToday() {
        let router = AppRouter()
        router.open(.settings, in: .library)
        router.resolve(WorkoutRoute.exercise(Self.bench))
        #expect(router.selectedTab == .today)
        #expect(router[path: .today] == [.exercise(Self.bench)])
        #expect(router[path: .library] == [.settings])
    }
}
