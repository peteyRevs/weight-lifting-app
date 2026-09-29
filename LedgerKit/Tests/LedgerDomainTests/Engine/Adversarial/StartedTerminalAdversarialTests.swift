import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Rules 1, 2 and 10 and criteria 6 and 12, attacked: starts that are late, early, invalid or
/// doubled, and terminals that race each other or the start.
@Suite("WorkoutEngine · started and terminals (adversarial)", .tags(.domain))
struct StartedTerminalAdversarialTests {
    typealias Adv = EngineAdv

    @Test("Rule 1: a second started, even an earlier-built different snapshot, is ignored with no effects.")
    func started_onExisting_isIgnored() {
        let first = Adv.state(after: [Adv.start()])
        let other = EventBuilders.seedSession(autoRest: false)
        let (state, effects) = WorkoutEngine.reduce(first, Adv.start(other, Adv.watch, seq: 1, at: 1))
        #expect(state == first)
        #expect(effects.isEmpty)
    }

    @Test("Rule 1: an envelope that sorts before the started (peer clock behind) is applied by replay.")
    func beforeStarted_isBufferedByReplay() throws {
        let early = Adv.env(Adv.logged(0, 0, doneAt: -5), Adv.watch, seq: 1, at: -5)
        #expect(WorkoutEngine.reduce(nil, early).0 == nil)
        let state = try #require(WorkoutEngine.replay([early, Adv.start()]))
        #expect(Adv.row(state, 0, 0)?.isDone == true)
    }

    @Test("Rule 1: an invalid started sorting first does not swallow the envelopes buffered before the valid one.")
    func invalidFirstStarted_doesNotDropBufferedEnvelopes() throws {
        var ended = EventBuilders.seedSession()
        ended.phase = .finished
        let other = EventBuilders.session(EventBuilders.seedExercises, id: WorkoutID(EventBuilders.uuid(0xBAD)))
        let log = [
            Adv.env(.started(ended), Adv.tablet, seq: 1, at: -20),
            Adv.env(.started(other), Adv.tablet, seq: 2, at: -15),
            Adv.env(Adv.logged(0, 0, doneAt: -5), Adv.watch, seq: 1, at: -5),
            Adv.start(),
            Adv.env(Adv.logged(0, 1, doneAt: 15), Adv.phone, seq: 2, at: 15)
        ]
        let state = try #require(WorkoutEngine.replay(log))
        #expect(state.phase == .live)
        // Both sets are done: the watch's envelope is buffered until the first *applicable* started.
        #expect(Adv.row(state, 0, 0)?.isDone == true)
        #expect(Adv.row(state, 0, 1)?.isDone == true)
    }

    @Test("Rule 1: a started whose snapshot is for another workout, or not live, never starts it.")
    func started_mismatchedOrNotLive_isIgnored() {
        let other = EventBuilders.session(EventBuilders.seedExercises, id: WorkoutID(EventBuilders.uuid(0xBAD)))
        let mismatched = Adv.env(.started(other), seq: 1, at: 0, workoutID: Adv.workoutID)
        var discarded = EventBuilders.seedSession()
        discarded.phase = .discarded
        for envelope in [mismatched, Adv.start(discarded)] {
            let (state, effects) = WorkoutEngine.reduce(nil, envelope)
            #expect(state == nil)
            #expect(effects.isEmpty)
        }
    }

    @Test("An envelope stamped for another workout is ignored with no effects.")
    func otherWorkout_isIgnored() {
        let live = Adv.state(after: [Adv.start()])
        let stray = Adv.env(Adv.logged(0, 0, doneAt: 5), seq: 2, at: 5, workoutID: WorkoutID(EventBuilders.uuid(0xBAD)))
        let (state, effects) = WorkoutEngine.reduce(live, stray)
        #expect(state == live)
        #expect(effects.isEmpty)
        #expect(WorkoutEngine.replay([Adv.start(), stray]) == live)
    }
}

// MARK: - Terminals

extension StartedTerminalAdversarialTests {
    /// Every event kind, for "nothing happens after a terminal".
    static func everyEvent(at seconds: Double) -> [WorkoutEvent] {
        let added = LoggedSet(id: SetID(EventBuilders.uuid(0xADD)), weight: pounds("100"), reps: Reps.one, kind: .added)
        return [
            .started(EventBuilders.seedSession()),
            .exerciseSelected(exerciseIndex: 1, setIndex: 0),
            Adv.logged(0, 1, doneAt: seconds),
            .setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)),
            .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 2), weight: pounds("200"), reps: nil),
            .setAdded(exerciseIndex: 0, set: added),
            .allSetsRepeated(exerciseIndex: 1, weight: pounds("60"), reps: Reps.one),
            .exerciseSwapped(
                exerciseIndex: 2,
                exerciseID: ExerciseID(EventBuilders.uuid(0xA1)),
                name: "X",
                alsoUpdateProgram: true
            ),
            .restStarted(endsAt: engineTime(seconds + 90), total: .seconds(90)),
            .restExtended(amount: .seconds(30)),
            .restSkipped,
            .finished(endedAt: engineTime(seconds)),
            .discarded(endedAt: engineTime(seconds))
        ]
    }

    @Test("Criterion 6 / rule 2: after finished or discarded, every later envelope changes nothing and emits nothing.")
    func terminal_laterEnvelopes_areInert() {
        let terminals: [WorkoutEvent] = [.finished(endedAt: engineTime(100)), .discarded(endedAt: engineTime(100))]
        for terminal in terminals {
            let ended = Adv.state(after: [
                Adv.start(),
                Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10),
                Adv.env(terminal, seq: 3, at: 100)
            ])
            for (offset, event) in Self.everyEvent(at: 200).enumerated() {
                for device in [Adv.phone, Adv.watch] {
                    let later = Adv.env(event, device, seq: 10 + UInt64(offset), at: 200)
                    let (state, effects) = WorkoutEngine.reduce(ended, later)
                    #expect(
                        state == ended,
                        "\(event) from \(device) changed a \(String(describing: ended?.phase)) workout"
                    )
                    #expect(effects.isEmpty, "\(event) emitted \(effects) after a terminal")
                }
            }
        }
    }

    @Test("Rule 2: two terminals from two devices — the first by envelope order wins, in any arrival order.")
    func twoTerminals_firstByOrderWins() throws {
        let finished = Adv.env(.finished(endedAt: engineTime(100)), Adv.watch, seq: 2, at: 100)
        let discardedLater = Adv.env(.discarded(endedAt: engineTime(101)), Adv.phone, seq: 2, at: 101)
        let discardedTie = Adv.env(.discarded(endedAt: engineTime(100)), Adv.phone, seq: 2, at: 100)
        // Later wall clock loses; on a tie the phone's ID sorts first, so its discard wins.
        let cases: [(EventEnvelope, WorkoutPhase)] = [(discardedLater, .finished), (discardedTie, .discarded)]
        for (other, expected) in cases {
            for order in [[finished, other], [other, finished]] {
                let state = try #require(WorkoutEngine.replay([Adv.start()] + order))
                #expect(state.phase == expected)
                #expect(Replica([Adv.start()] + order).state == state)
            }
        }
    }

    @Test("A terminal whose wall clock sorts before the started ends the workout; incremental devices agree.")
    func terminalBeforeStarted_endsWorkoutEverywhere() throws {
        let discard = Adv.env(.discarded(endedAt: engineTime(-5)), Adv.watch, seq: 1, at: -5)
        let log = Adv.env(Adv.logged(0, 0, doneAt: 20), seq: 2, at: 20)
        let state = try #require(WorkoutEngine.replay([Adv.start(), log, discard]))
        #expect(state.phase == .discarded)
        #expect(Adv.row(state, 0, 0)?.isDone == false)
        for arrival in [[Adv.start(), log, discard], [discard, log, Adv.start()], [log, discard, Adv.start()]] {
            #expect(Replica(arrival).state == state)
        }
    }
}
