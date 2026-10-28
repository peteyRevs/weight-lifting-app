import FeatureLibrary
import FeatureWorkout
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S1 and S2, criteria 3 and 11: where the Library's routes go (`Routes+Library.swift`). A row's history is
/// pushed on the selected tab's stack, the one that asked for it, one screen per route; a session opens History.
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
        router.resolve(LibraryRoute.exercise(Self.bench))
        #expect(router.selectedTab == .library)
        #expect(router[path: .library] == [.exercise(Self.bench)])
        router.resolve(LibraryRoute.exercise(Self.squat))
        #expect(router[path: .library] == [.exercise(Self.bench), .exercise(Self.squat)])
        #expect(AppTab.allCases.map { router[path: $0].count } == [0, 0, 2, 0])
    }

    @Test("3. The history is pushed on whichever tab is selected, and the tab stays selected")
    func exercise_pushesOnTheSelectedTab() {
        let router = AppRouter()
        router.selectedTab = .history
        router.resolve(LibraryRoute.exercise(Self.bench))
        #expect(router.selectedTab == .history)
        #expect(router[path: .history] == [.exercise(Self.bench)])
        #expect(router[path: .library] == [])
    }

    @Test("11. A session of the log opens the History tab until F13's detail, and pushes nothing")
    func openWorkout_selectsTheHistoryTab() {
        let router = AppRouter()
        router.open(.exercise(Self.bench), in: .library)
        router.resolve(LibraryRoute.openWorkout(WorkoutID(Fixtures.uuid(453))))
        #expect(router.selectedTab == .history)
        #expect(router[path: .library] == [.exercise(Self.bench)], "the history stays where the lifter left it")
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
