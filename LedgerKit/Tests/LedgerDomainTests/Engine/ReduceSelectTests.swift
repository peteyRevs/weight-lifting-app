import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · exerciseSelected (rule 11)", .tags(.domain))
struct ReduceSelectTests {
    @Test("Rule 11: selecting an existing undone row moves the cursor there")
    func select_undoneRow_movesCursor() throws {
        let (state, _) = try Engine.run([.exerciseSelected(exerciseIndex: 3, setIndex: 2)])
        #expect(state.cursor == Cursor(exerciseIndex: 3, setIndex: 2))
    }

    @Test("Rule 11: selecting a done row is ignored")
    func select_doneRow_isIgnored() throws {
        let logged = try Engine.run([Engine.logged(2, 0, at: 10)]).state
        let (state, _) = try Engine.run([Engine.logged(2, 0, at: 10), .exerciseSelected(exerciseIndex: 2, setIndex: 0)])
        #expect(state == logged)
    }

    @Test("Rule 11: selecting a row that does not exist is ignored", arguments: [
        Cursor(exerciseIndex: -1, setIndex: 0),
        Cursor(exerciseIndex: 5, setIndex: 0),
        Cursor(exerciseIndex: 0, setIndex: 5),
        Cursor(exerciseIndex: 0, setIndex: -1)
    ])
    func select_missingRow_isIgnored(target: Cursor) throws {
        let event = WorkoutEvent.exerciseSelected(exerciseIndex: target.exerciseIndex, setIndex: target.setIndex)
        #expect(try Engine.run([event]).state == (Engine.live()))
    }
}
