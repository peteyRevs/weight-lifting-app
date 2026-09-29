import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · setLogged (rule 3)", .tags(.domain))
struct ReduceSetLoggedTests {
    private func cursor(_ exerciseIndex: Int, _ setIndex: Int) -> Cursor {
        Cursor(exerciseIndex: exerciseIndex, setIndex: setIndex)
    }

    @Test("Criterion 1: logging bench set 1 rests 150 s from the log time and moves to set 2")
    func criterion1_firstSet_startsRestAndAdvances() throws {
        let (state, effects) = try Engine.run([Engine.logged(0, 0, pounds: 190, reps: 4, at: 12)])
        let endsAt = Engine.at(12 + 150)
        #expect(state.rest == RestTimer(endsAt: endsAt, total: .seconds(150)))
        #expect(state.cursor == cursor(0, 1))
        #expect(effects.contains(.haptic(.setLogged)))
        #expect(effects.contains(.scheduleRestNotification(endsAt: endsAt)))
        let set = state.exercises[0].sets[0]
        #expect(set.doneAt == Engine.at(12))
        #expect(set.weight == .pounds(190))
        #expect(set.reps.value == 4)
    }

    @Test("Criterion 2: a superset rests only after the round's last member, for the longest rest")
    func criterion2_superset_restsAfterRound_roundRobin() throws {
        let session = EventBuilders.session(EventBuilders.supersetExercises)
        let afterA1 = try Engine.run([Engine.logged(0, 0, at: 10)], on: session)
        #expect(afterA1.state.rest == nil)
        #expect(afterA1.state.cursor == cursor(1, 0))
        #expect(!afterA1.effects.contains {
            if case .scheduleRestNotification = $0 {
                true
            } else {
                false
            }
        })

        let afterB1 = try Engine.run([Engine.logged(0, 0, at: 10), Engine.logged(1, 0, at: 20)], on: session)
        #expect(afterB1.state.rest == RestTimer(endsAt: Engine.at(20 + 90), total: .seconds(90)))
        #expect(afterB1.state.cursor == cursor(0, 1))
    }

    @Test("Criterion 3: logging the last set of an exercise moves the cursor to the next exercise")
    func criterion3_lastSetOfExercise_movesToNextExercise() throws {
        let events = (0 ..< 5).map { Engine.logged(0, $0, at: Double(10 * ($0 + 1))) }
        let (state, _) = try Engine.run(events)
        let allDone = state.exercises[0].sets.allSatisfy(\.isDone)
        #expect(allDone)
        #expect(state.cursor == cursor(1, 0))
    }

    @Test("Rule 20: with nothing undone later, the cursor wraps to the earliest undone row")
    func cursor_wrapsToEarliestUndoneRow() throws {
        let events = [1, 2, 3, 4].map { Engine.logged(0, $0, at: Double(10 * $0)) }
        let (state, _) = try Engine.run(events)
        #expect(state.cursor == cursor(0, 0))
    }

    @Test("Rule 20: the last row of the last block leaves the cursor where it was")
    func cursor_staysAfterLastRowOfWorkout() throws {
        let session = EventBuilders.session([
            EventBuilders.ExerciseSpec("Curl", .barbell, sets: 1, reps: 10, pounds: 75, restSeconds: 60)
        ])
        let (state, _) = try Engine.run(
            [.exerciseSelected(exerciseIndex: 0, setIndex: 0), Engine.logged(0, 0, at: 20)],
            on: session
        )
        #expect(state.cursor == cursor(0, 0))
    }

    @Test("Rule 19: with auto rest off, a logged set starts no rest but still advances")
    func autoRestOff_startsNoRest() throws {
        let (state, effects) = try Engine.run(
            [Engine.logged(0, 0, at: 10)],
            on: EventBuilders.seedSession(autoRest: false)
        )
        #expect(state.rest == nil)
        #expect(state.cursor == cursor(0, 1))
        #expect(effects.contains(.haptic(.setLogged)))
    }

    @Test("Rule 3: re-logging a done set updates its values (latest wins) without resting or moving")
    func relog_updatesValuesOnly() throws {
        let events: [WorkoutEvent] = [
            Engine.logged(0, 0, at: 10),
            .exerciseSelected(exerciseIndex: 2, setIndex: 1),
            Engine.logged(0, 0, pounds: 195, reps: 3, at: 30)
        ]
        let (state, effects) = try Engine.run(events)
        #expect(state.exercises[0].sets[0].weight == .pounds(195))
        #expect(state.exercises[0].sets[0].reps.value == 3)
        #expect(state.exercises[0].sets[0].doneAt == Engine.at(30))
        #expect(state.rest == RestTimer(endsAt: Engine.at(10 + 150), total: .seconds(150)))
        #expect(state.cursor == cursor(2, 1))
        #expect(!effects.contains {
            if case .scheduleRestNotification = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test("A logged weight below zero is stored as zero (spec rule 1)")
    func negativeWeight_isClampedToZero() throws {
        let (state, _) = try Engine.run([Engine.logged(0, 0, pounds: -10, at: 10)])
        #expect(state.exercises[0].sets[0].weight == .zero)
    }

    @Test("A set that is not in the named exercise changes nothing", arguments: [
        (exercise: 0, set: EventBuilders.setID(1, 0)),
        (exercise: 7, set: EventBuilders.setID(0, 0)),
        (exercise: -1, set: EventBuilders.setID(0, 0))
    ])
    func unknownSet_changesNothing(target: (exercise: Int, set: SetID)) throws {
        let live = try Engine.live()
        let event = WorkoutEvent.setLogged(
            exerciseIndex: target.exercise,
            setID: target.set,
            weight: .pounds(100),
            reps: .one,
            doneAt: Engine.at(10)
        )
        let (state, effects) = WorkoutEngine.reduce(live, Engine.envelope(event, 10, seq: 2))
        #expect(state == live)
        #expect(effects.count == 2)
    }

    @Test("The drop round of a superset rests after its last drop row")
    func supersetDropRound_restsAfterLastDropRow() throws {
        let session = EventBuilders.session([
            EventBuilders.ExerciseSpec("A", .dumbbell, sets: 1, reps: 10, pounds: 50, restSeconds: 60, dropSet: true),
            EventBuilders.ExerciseSpec(
                "B",
                .cable,
                sets: 1,
                reps: 10,
                pounds: 50,
                restSeconds: 75,
                superset: true,
                dropSet: true
            )
        ])
        let first = try Engine.run([Engine.logged(0, 1, at: 10)], on: session)
        #expect(first.state.rest == nil)
        #expect(first.state.cursor == cursor(1, 1))
        let second = try Engine.run([Engine.logged(0, 1, at: 10), Engine.logged(1, 1, at: 20)], on: session)
        #expect(second.state.rest == RestTimer(endsAt: Engine.at(20 + 75), total: .seconds(75)))
        #expect(second.state.cursor == cursor(0, 0))
    }
}
