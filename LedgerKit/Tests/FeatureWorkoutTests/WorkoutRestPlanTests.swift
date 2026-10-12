@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S6, criterion 5: what "+30s" and "Skip rest" come to, as one event each. `WorkoutEditPlan.make` is
/// pure: the workout and the tap's moment are arguments. The fixtures are `WorkoutEditPlanTests`'.
@Suite("WorkoutEditPlan · rest", .tags(.feature))
struct WorkoutRestPlanTests {
    typealias Plans = WorkoutEditPlanTests

    /// The seed workout with a rest of 150 s that ends `secondsLeft` after `Fixtures.now` (before it when
    /// negative), started by the first set.
    static func resting(secondsLeft: TimeInterval) -> WorkoutState {
        var state = Plans.seed
        let end = Fixtures.now.addingTimeInterval(secondsLeft)
        state.exercises[0].sets[0].doneAt = end.addingTimeInterval(-150)
        state.cursor = Cursor(exerciseIndex: 0, setIndex: 1)
        state.rest = RestTimer(endsAt: end, total: .seconds(150))
        return state
    }

    @Test("+30s while the rest runs: one event, 30 s, extending the shown rest, at the tap's moment", arguments: [
        150.0, 75, 0.001
    ])
    func extend_running(secondsLeft: TimeInterval) {
        let plan = Plans.plan(.extendRest, in: Self.resting(secondsLeft: secondsLeft))
        #expect(plan.events == [
            .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: Fixtures.now)
        ])
        #expect(plan.selection == nil)
    }

    @Test("+30s at Rest over: the same event with extendsShownRest false, so a rest of 30 s starts", arguments: [
        0.0, -0.001, -400
    ])
    func extend_over(secondsLeft: TimeInterval) {
        let plan = Plans.plan(.extendRest, in: Self.resting(secondsLeft: secondsLeft))
        #expect(plan.events == [
            .restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: Fixtures.now)
        ])
    }

    @Test("Skip rest: one event, whether the rest runs or is over")
    func skip() {
        #expect(Plans.plan(.skipRest, in: Self.resting(secondsLeft: 75)).events == [.restSkipped])
        #expect(Plans.plan(.skipRest, in: Self.resting(secondsLeft: -75)).events == [.restSkipped])
    }

    @Test("With no rest shown, neither sends anything: a second tap behind a skip, or a panel that has gone")
    func noRestShown_sendsNothing() {
        #expect(Plans.plan(.extendRest).events == [])
        #expect(Plans.plan(.skipRest).events == [])
        // The engine still holds a rest that ended before a set was logged: no panel shows it.
        var stale = Self.resting(secondsLeft: -75)
        stale.exercises[0].sets[1].doneAt = Fixtures.now.addingTimeInterval(-10)
        #expect(stale.rest != nil)
        #expect(Plans.plan(.extendRest, in: stale).events == [])
        #expect(Plans.plan(.skipRest, in: stale).events == [])
    }

    @Test("Neither moves the shown row")
    func selection_stays() {
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: Plans.set(0, 3))
        let state = Self.resting(secondsLeft: 75)
        #expect(Plans.plan(.extendRest, in: state, selection: chosen).selection == chosen)
        #expect(Plans.plan(.skipRest, in: state, selection: chosen).selection == chosen)
    }

    @Test("Un-logging never sends a rest event (rule 22), and its one-second guard is as it was")
    func unlog_sendsNoRestEvent() {
        let state = Self.resting(secondsLeft: 75)
        let unlog = Plans.plan(.unlog(exerciseIndex: 0, setID: Plans.set(0, 0)), in: state)
        #expect(unlog.events == [.setUnlogged(exerciseIndex: 0, setID: Plans.set(0, 0))])
        // Logged half a second ago: the guard holds, and nothing at all is sent.
        var justNow = state
        justNow.exercises[0].sets[0].doneAt = Fixtures.now.addingTimeInterval(-0.5)
        #expect(Plans.plan(.unlog(exerciseIndex: 0, setID: Plans.set(0, 0)), in: justNow).events == [])
    }
}
