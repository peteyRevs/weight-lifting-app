import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · started (rule 1)", .tags(.domain))
struct ReduceStartedTests {
    @Test("Rule 1: started on no state yields the snapshot, persisted and sent")
    func started_onNil_yieldsSnapshot() {
        let snapshot = EventBuilders.seedSession()
        let envelope = Engine.started(snapshot)
        let (state, effects) = WorkoutEngine.reduce(nil, envelope)
        #expect(state == snapshot)
        #expect(effects == [.persist(envelope), .transmit(envelope), .updateLiveActivity])
    }

    @Test("Rule 1: a second started is ignored, with no effects")
    func started_onExistingState_isIgnored() throws {
        let live = try Engine.live()
        let other = EventBuilders.session(EventBuilders.supersetExercises)
        let (state, effects) = WorkoutEngine.reduce(live, Engine.envelope(.started(other), 10, seq: 2))
        #expect(state == live)
        #expect(effects.isEmpty)
    }

    @Test("Rule 1: any other event before started is not applied")
    func eventBeforeStarted_isIgnored() {
        let (state, effects) = WorkoutEngine.reduce(nil, Engine.envelope(Engine.logged(0, 0, at: 5), 5, seq: 1))
        #expect(state == nil)
        #expect(effects.isEmpty)
    }

    @Test("A started whose snapshot is not live, or is for another workout, is ignored")
    func started_invalidSnapshot_isIgnored() {
        var finished = EventBuilders.seedSession()
        finished.phase = .finished
        #expect(WorkoutEngine.reduce(nil, Engine.started(finished)).0 == nil)
        let otherWorkout = EventBuilders.session(EventBuilders.seedExercises, id: WorkoutID(EventBuilders.uuid(77)))
        let (state, effects) = WorkoutEngine.reduce(nil, Engine.started(otherWorkout))
        #expect(state == nil)
        #expect(effects.isEmpty)
    }

    @Test("An envelope for another workout is ignored")
    func envelope_forAnotherWorkout_isIgnored() throws {
        let live = try Engine.live()
        let stray = EventBuilders.envelope(
            Engine.logged(0, 0, at: 10),
            seq: 2,
            at: Engine.at(10),
            workoutID: WorkoutID(EventBuilders.uuid(77))
        )
        let (state, effects) = WorkoutEngine.reduce(live, stray)
        #expect(state == live)
        #expect(effects.isEmpty)
    }

    @Test("Rule 1: replay buffers events that sort before started (a slow peer clock) and applies them after it")
    func replay_buffersEventsSortedBeforeStarted() throws {
        let early = Engine.envelope(Engine.logged(0, 0, at: -1), -1, from: Engine.watch, seq: 1)
        let state = try #require(WorkoutEngine.replay([early, Engine.started()]))
        #expect(state.exercises[0].sets[0].doneAt == Engine.at(-1))
        #expect(state.cursor == Cursor(exerciseIndex: 0, setIndex: 1))
        #expect(WorkoutEngine.foldOrder([early, Engine.started()]).map(\.key) == [
            Engine.started().key,
            early.key
        ])
    }

    @Test("A log with no started replays to no state")
    func replay_withoutStarted_isNil() {
        #expect(WorkoutEngine.replay([]) == nil)
        #expect(WorkoutEngine.replay([Engine.envelope(.restSkipped, 1, seq: 1)]) == nil)
    }
}
