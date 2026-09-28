import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · setTargetChanged (rule 5)", .tags(.domain))
struct ReduceTargetLWWTests {
    private func change(_ weight: Decimal?, _ reps: Int? = nil) -> WorkoutEvent {
        .setTargetChanged(
            exerciseIndex: 0,
            setID: Engine.set(0, 1),
            weight: weight.map { .pounds($0) },
            reps: reps.map { Reps(clamping: $0) }
        )
    }

    @Test("Criterion 11: W's 190 at t=10 beats P's 195 at t=9, whichever arrives first")
    func criterion11_laterWallClockWins_inAnyArrivalOrder() throws {
        let fromWatch = Engine.envelope(change(190), 10, from: Engine.watch, seq: 1)
        let fromPhone = Engine.envelope(change(195), 9, from: Engine.phone, seq: 2)
        for arrival in [[fromWatch, fromPhone], [fromPhone, fromWatch]] {
            let state = try #require(WorkoutEngine.replay([Engine.started()] + arrival))
            #expect(state.exercises[0].sets[1].weight == .pounds(190))
        }
    }

    @Test("Rule 5: last writer wins per field, so edits to different fields both survive")
    func lastWriterWins_perField() throws {
        let log = [
            Engine.started(),
            Engine.envelope(change(190), 10, from: Engine.watch, seq: 1),
            Engine.envelope(change(nil, 3), 11, from: Engine.phone, seq: 2),
            Engine.envelope(change(200), 12, from: Engine.phone, seq: 3)
        ]
        let state = try #require(WorkoutEngine.replay(log.reversed()))
        #expect(state.exercises[0].sets[1].weight == .pounds(200))
        #expect(state.exercises[0].sets[1].reps.value == 3)
    }

    @Test("A target change leaves the done flag, the cursor and the rest alone")
    func targetChange_touchesOnlyTheSet() throws {
        let logged = try Engine.run([Engine.logged(0, 1, at: 10)])
        let (state, _) = try Engine.run([Engine.logged(0, 1, at: 10), change(150, 8)])
        #expect(state.exercises[0].sets[1].doneAt == Engine.at(10))
        #expect(state.exercises[0].sets[1].weight == .pounds(150))
        #expect(state.cursor == logged.state.cursor)
        #expect(state.rest == logged.state.rest)
    }

    @Test("A negative weight is stored as zero; a change naming no field or no set changes nothing")
    func clampAndNoOps() throws {
        #expect(try Engine.run([change(-20)]).state.exercises[0].sets[1].weight == .zero)
        let live = try Engine.live()
        #expect(try Engine.run([change(nil)]).state == live)
        let unknown = WorkoutEvent.setTargetChanged(
            exerciseIndex: 3,
            setID: Engine.set(0, 1),
            weight: .zero,
            reps: .one
        )
        #expect(try Engine.run([unknown]).state == live)
    }
}
