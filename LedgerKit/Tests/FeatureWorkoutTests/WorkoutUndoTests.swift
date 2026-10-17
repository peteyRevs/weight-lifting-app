@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criteria 3 and 18: the check of a logged row. It un-logs the set and moves nothing (rule 22),
/// except in the first second after the set was logged, when a second touch on the same spot must not take
/// the set back. The rule is the plan's, of two moments it is handed; the store adds the injected date.
@MainActor
@Suite("Workout undo", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutUndoTests {
    typealias Plans = WorkoutEditPlanTests
    typealias Pump = WorkoutStorePumpTests
    typealias Scene = WorkoutScene

    @Test("The check of a logged row un-logs it and moves nothing")
    func unlog_loggedRow_unlogsAndKeepsTheSelection() {
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: Plans.set(0, 3))
        let state = Plans.logged([0, 1], of: 0, secondsAgo: 60)
        let plan = Plans.plan(.unlog(exerciseIndex: 0, setID: Plans.set(0, 1)), in: state, selection: chosen)
        #expect(plan.events == [.setUnlogged(exerciseIndex: 0, setID: Plans.set(0, 1))])
        #expect(plan.selection == chosen)
        #expect(Plans.plan(.unlog(exerciseIndex: 0, setID: Plans.set(0, 2)), in: state).events == [])
    }

    /// Criterion 18. The rule is of two moments, the set's `doneAt` and the tap's: no clock is read and
    /// nothing counts time.
    @Test(
        "An un-log less than a second after the set was logged does nothing; from one second on it un-logs",
        arguments: [
            (0.0, false), (0.001, false), (0.78, false), (0.999, false), (1.0, true), (1.001, true), (60.0, true),
            // A set logged by a clock that runs ahead of this one is not guarded.
            (-0.5, true), (-3600.0, true)
        ]
    )
    func unlog_withinASecondOfTheLog_comesToNothing(secondsAgo: TimeInterval, isUnlogged: Bool) {
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: Plans.set(0, 1))
        let state = Plans.logged([0], of: 0, secondsAgo: secondsAgo)
        let plan = Plans.plan(.unlog(exerciseIndex: 0, setID: Plans.set(0, 0)), in: state, selection: chosen)
        #expect(plan.events == (isUnlogged ? [.setUnlogged(exerciseIndex: 0, setID: Plans.set(0, 0))] : []))
        #expect(plan.selection == chosen)
        #expect(WorkoutEditPlan.undoGuard == 1)
    }

    /// Criterion 18 through the store: the second touch is planned with the injected date, the very moment
    /// the set was logged at.
    @Test("A second touch on a check that was just redrawn as logged does not take the set back")
    func unlogRightAfterTheLog_keepsTheSet() async throws {
        let running = try Fixtures.seedSession()
        let first = Pump.sets(0, of: running)[0]
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        await store.drain()
        await eventually { store.model.page?.card?.rows.first?.state == .done }
        // The row is drawn logged: its check now sends an un-log.
        #expect(store.model.page?.card?.rows.first?.check == .unlog(exerciseIndex: 0, setID: first))
        store.send(.edit(.unlog(exerciseIndex: 0, setID: first)))
        await store.drain()
        #expect(await scene.fake?.applied.count == 1)
        #expect(try await Pump.live(scene).doneSets == 1)
        #expect(store.dialog == nil)
        task.cancel()
    }
}
