import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · setUnlogged (rule 4)", .tags(.domain))
struct ReduceUnlogTests {
    @Test("Criterion 4: un-logging a done set leaves the cursor and the rest alone (rule 22)")
    func criterion4_unlog_keepsCursorAndRest() throws {
        let logged = try Engine.run([Engine.logged(0, 0, at: 10)])
        let (state, _) = try Engine.run([
            Engine.logged(0, 0, at: 10),
            .setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 0))
        ])
        #expect(!state.exercises[0].sets[0].isDone)
        #expect(state.cursor == logged.state.cursor)
        #expect(state.rest == logged.state.rest)
        #expect(state.exercises[0].sets[0].weight == .pounds(185))
    }

    @Test("Logging a set again after un-logging it is a new done transition: rest restarts, cursor moves")
    func relogAfterUnlog_isTransitionAgain() throws {
        let (state, effects) = try Engine.run([
            Engine.logged(0, 0, at: 10),
            .setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 0)),
            .exerciseSelected(exerciseIndex: 0, setIndex: 0),
            Engine.logged(0, 0, at: 40)
        ])
        #expect(state.rest == RestTimer(endsAt: Engine.at(40 + 150), total: .seconds(150)))
        #expect(state.cursor == Cursor(exerciseIndex: 0, setIndex: 1))
        #expect(effects.contains(.scheduleRestNotification(endsAt: Engine.at(190))))
    }

    @Test("Un-logging an unknown or undone set changes nothing")
    func unlog_unknownOrUndone_changesNothing() throws {
        let live = try Engine.live()
        for event in [
            WorkoutEvent.setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 1)),
            .setUnlogged(exerciseIndex: 9, setID: Engine.set(0, 1)),
            .setUnlogged(exerciseIndex: 1, setID: Engine.set(0, 1))
        ] {
            #expect(WorkoutEngine.reduce(live, Engine.envelope(event, 10, seq: 2)).0 == live)
        }
    }
}
