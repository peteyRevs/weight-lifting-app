#if DEBUG
    @testable import FeatureHistory
    import FeatureLibrary
    import Foundation
    @testable import LedgerAppKit
    import LedgerDomain
    import LedgerTestSupport
    import Testing

    /// F13 S2 adversarial (G2): the shell's side of a past workout's detail, its routes (F13-S1-6). A late route lands
    /// on the stack it came from after a tab switch; `.closeWorkout(id)` pops a detail only while it is on top of its
    /// own tab, so the same workout open on two tabs, a stack with the detail twice ([detail, exercise history,
    /// detail], as a session log reopens it) and a detail under its row's exercise history each lose exactly the
    /// screens they should. N13: `WorkoutDetailParityAdversarialTests`.
    @MainActor
    @Suite("Adversarial F13 S2 · the detail's routes")
    struct HistoryDetailAdversarialTests {
        static let upperA = WorkoutID(Fixtures.uuid(471))
        static let lowerA = WorkoutID(Fixtures.uuid(472))
        static let bench = ExerciseID(Fixtures.uuid(473))

        // MARK: - Routes

        @Test("F13-S1-6. A row's route delivered after a tab switch lands on its own stack, and selects that tab")
        func lateRoute_landsOnItsOwnStack() {
            let router = AppRouter()
            router.open(.workout(Self.upperA), in: .history)
            router.selectedTab = .program
            router.resolve(HistoryRoute.exercise(Self.bench), from: .history)
            #expect(router[path: .history] == [.workout(Self.upperA), .exercise(Self.bench)])
            #expect(router[path: .program] == [])
            // As built: `open(_:in:)` also selects the tab, so a late route brings the lifter back to it (Info).
            #expect(router.selectedTab == .history)
            router.selectedTab = .today
            router.resolve(LibraryRoute.openWorkout(Self.lowerA), from: .history)
            #expect(router[path: .history].last == .workout(Self.lowerA), "a session log's late route too")
            #expect(router[path: .today] == [])
        }

        @Test("The same workout open on two tabs: each tab's close pops its own detail only")
        func sameWorkout_onTwoTabs_closesEachOnce() {
            let router = AppRouter()
            router.open(.workout(Self.upperA), in: .today)
            router.open(.workout(Self.upperA), in: .history)
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .history)
            #expect(router[path: .history] == [])
            #expect(router[path: .today] == [.workout(Self.upperA)], "Today's detail is closed by its own store")
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .history)
            #expect(router[path: .today] == [.workout(Self.upperA)], "a second close from History pops nothing")
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .today)
            #expect(router[path: .today] == [])
        }

        @Test("A stack holding the detail twice loses the top one, then the lower one once its cover comes off")
        func detailTwice_onOneStack_closesFromTheTop() {
            let router = AppRouter()
            router.open(.workout(Self.upperA), in: .library)
            router.resolve(HistoryRoute.exercise(Self.bench), from: .library)
            router.resolve(LibraryRoute.openWorkout(Self.upperA), from: .library)
            let path = router[path: .library]
            #expect(path == [.workout(Self.upperA), .exercise(Self.bench), .workout(Self.upperA)])
            // Both details' stores see nil and ask to close: the first close pops the top; the other pops nothing.
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .library)
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .library)
            #expect(router[path: .library] == [.workout(Self.upperA), .exercise(Self.bench)])
            // The lifter goes back: the lower detail's task runs again, finds it gone and asks again.
            router[path: .library].removeLast()
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .library)
            #expect(router[path: .library] == [])
        }

        @Test(
            "A row's exercise history over the detail, then the workout deleted: it stays, then the detail goes"
        )
        func exerciseOverTheDetail_thenDeleted() {
            let router = AppRouter()
            router.open(.workout(Self.upperA), in: .history)
            router.resolve(HistoryRoute.exercise(Self.bench), from: .history)
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .history)
            #expect(router[path: .history] == [.workout(Self.upperA), .exercise(Self.bench)])
            router[path: .history].removeLast()
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .history)
            #expect(router[path: .history] == [])
            router.resolve(HistoryRoute.closeWorkout(Self.lowerA), from: .history)
            #expect(router[path: .history] == [], "a close of another workout on an empty stack is harmless")
        }

        @Test("A close of one workout never pops another's detail on top")
        func closeOfAnother_popsNothing() {
            let router = AppRouter()
            router.open(.workout(Self.upperA), in: .history)
            router.open(.workout(Self.lowerA), in: .history)
            router.resolve(HistoryRoute.closeWorkout(Self.upperA), from: .history)
            #expect(router[path: .history] == [.workout(Self.upperA), .workout(Self.lowerA)])
        }
    }
#endif
