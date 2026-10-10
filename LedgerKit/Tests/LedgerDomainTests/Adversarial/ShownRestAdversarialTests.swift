import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S6 criteria 2, 4 and 6: `WorkoutState.shownRest` against an oracle written from the brief, not
/// from the engine's `rest`. The oracle is what a lifter is owed on screen: a logged set that starts a rest
/// shows it; it stays, running and then over, until "+30s" (which grows a running rest, or starts 30 s at
/// the tap once it is over), "Skip rest" or the next logged set; un-logging changes nothing (rule 22).
@Suite("WorkoutState.shownRest (adversarial)", .tags(.domain, .property))
struct ShownRestAdversarialTests {
    static let solo = EventBuilders.seedSession()
    static let superset = EventBuilders.session(EventBuilders.supersetExercises)

    static func at(_ seconds: Double) -> Date {
        EventBuilders.start.addingTimeInterval(seconds)
    }

    /// What the screen is owed, kept beside the engine's state.
    struct Oracle {
        var shown: RestTimer?
        var done: Set<SetID> = []

        /// A set of a solo exercise logged at `moment`: its exercise's rest, from that moment.
        mutating func logged(_ id: SetID, rest: Duration, at moment: Date) {
            guard done.insert(id).inserted else {
                return
            }
            shown = rest > .zero ? RestTimer(endsAt: moment.addingTimeInterval(rest / .seconds(1)), total: rest) : nil
        }

        /// "+30s" as the panel sends it: what it showed at the tap decides. With nothing shown, a rest of 30 s.
        mutating func extended(at moment: Date) -> WorkoutEvent {
            let isRunning = shown.map { $0.endsAt > moment } ?? false
            if let running = shown, isRunning {
                shown = RestTimer(endsAt: running.endsAt.addingTimeInterval(30), total: running.total + .seconds(30))
            } else {
                shown = RestTimer(endsAt: moment.addingTimeInterval(30), total: .seconds(30))
            }
            return .restExtended(amount: .seconds(30), extendsShownRest: isRunning, tappedAt: moment)
        }
    }

    /// One seeded walk through a solo workout: logs, un-logs, steppers, added sets, "+30s", "Skip rest",
    /// with time moving on between 0 and 200 s a step, so rests are met running, just over and long over.
    /// (The seed session's rests are 150, 90, 90, 75 and 60 s.)
    /// Returns the first step at which the state's `shownRest` is not the oracle's, or nil.
    static func firstDifference(seed: PropertySeed, steps: Int = 60) -> String? {
        var generator = seed.generator
        var state = solo
        var oracle = Oracle()
        var clock = 10.0
        let rows = solo.exercises.enumerated().flatMap { index, exercise in exercise.sets.map { (index, $0) } }
        for step in 0 ..< steps {
            clock += [0, 0.5, 1, 29, 30, 31, 89, 90, 151, 200][Int.random(in: 0 ..< 10, using: &generator)]
            let (exercise, row) = rows[Int.random(in: 0 ..< rows.count, using: &generator)]
            let event: WorkoutEvent
            // A check is a log on a row that is not done and an un-log on one that is: the screen never logs a
            // done row again (a peer's re-log is F17's).
            let isDone = oracle.done.contains(row.id)
            switch Int.random(in: 0 ..< 12, using: &generator) {
            case 0 ..< 7 where !isDone:
                event = .setLogged(
                    exerciseIndex: exercise, setID: row.id, weight: row.weight, reps: row.reps, doneAt: at(clock)
                )
                oracle.logged(row.id, rest: solo.exercises[exercise].rest.duration, at: at(clock))
            case 0 ..< 7:
                event = .setUnlogged(exerciseIndex: exercise, setID: row.id)
                oracle.done.remove(row.id)
            case 7:
                event = .setTargetChanged(exerciseIndex: exercise, setID: row.id, weight: .pounds(100), reps: nil)
            case 8:
                event = .exerciseSelected(exerciseIndex: exercise, setIndex: 0)
            case 9 ..< 11:
                event = oracle.extended(at: at(clock))
            default:
                event = .restSkipped
                oracle.shown = nil
            }
            let envelope = EventBuilders.envelope(event, seq: UInt64(step + 2), at: at(clock))
            state = WorkoutEngine.reduce(state, envelope).0 ?? state
            if state.shownRest != oracle.shown {
                return "step \(step), \(event): shown \(String(describing: state.shownRest)), "
                    + "owed \(String(describing: oracle.shown))"
            }
        }
        return nil
    }

    @Test(
        "Solo exercises: after every event the shown rest is the one the brief owes the screen",
        arguments: PropertySeed.all
    )
    func solo_isTheBriefsRest(seed: PropertySeed) {
        let difference = Self.firstDifference(seed: seed)
        #expect(difference == nil, "\(seed)")
    }

    @Test("Solo exercises: un-logging any set, at any point, changes neither the rest nor the shown rest")
    func solo_unlogChangesNothing() {
        var state = Self.solo
        var seq: UInt64 = 2
        func apply(_ event: WorkoutEvent, to state: inout WorkoutState) {
            state = WorkoutEngine.reduce(state, EventBuilders.envelope(event, seq: seq, at: Self.at(0))).0 ?? state
        }
        let bench = state.exercises[0].sets
        for (offset, row) in bench.prefix(3).enumerated() {
            apply(.setLogged(
                exerciseIndex: 0, setID: row.id, weight: row.weight, reps: row.reps,
                doneAt: Self.at(Double(offset) * 400)
            ), to: &state)
            seq += 1
        }
        // The third set's rest runs from 800 s to 950 s; the first two rests are long over.
        let rest = RestTimer(endsAt: Self.at(950), total: .seconds(150))
        #expect(state.shownRest == rest)
        for row in bench.prefix(3) {
            var undone = state
            apply(.setUnlogged(exerciseIndex: 0, setID: row.id), to: &undone)
            #expect(undone.rest == rest)
            #expect(undone.shownRest == rest)
        }
    }

    /// The first round of the superset (A1 at 60 s, B1 at 70 s; the group's rest ends at 160 s), then `more`.
    static func afterFirstRound(_ more: [WorkoutEvent]) -> WorkoutState {
        func logged(_ exercise: Int, _ set: Int, at seconds: Double) -> WorkoutEvent {
            let row = superset.exercises[exercise].sets[set]
            return .setLogged(
                exerciseIndex: exercise, setID: row.id, weight: row.weight, reps: row.reps, doneAt: at(seconds)
            )
        }
        var state = superset
        for (offset, event) in ([logged(0, 0, at: 60), logged(1, 0, at: 70)] + more).enumerated() {
            let envelope = EventBuilders.envelope(event, seq: UInt64(offset + 2), at: EventBuilders.start)
            state = WorkoutEngine.reduce(state, envelope).0 ?? state
        }
        return state
    }

    /// As built, and a question for the product owner (S9), not a ruling: a superset's member logged after
    /// the rest's end takes "Rest over" away (the next logged set, brief criterion 6); un-logging that
    /// member brings the ended rest back on screen, however long ago it ended. Rule 22 says an un-log
    /// never cancels a rest; nothing says it shows one again. The cover draws a superset's members as solo
    /// cards today, so this is reachable in the app before S9. When it is ruled, this test changes with it.
    @Test("As built: un-logging the member logged after a rest's end brings Rest over back (question, S9)")
    func supersetMember_unlogged_asBuilt() {
        let second = Self.superset.exercises[0].sets[1]
        let logged = WorkoutEvent.setLogged(
            exerciseIndex: 0, setID: second.id, weight: second.weight, reps: second.reps, doneAt: Self.at(900)
        )
        let gone = Self.afterFirstRound([logged])
        #expect(gone.shownRest == nil, "the next logged set takes Rest over away")
        let back = Self.afterFirstRound([logged, .setUnlogged(exerciseIndex: 0, setID: second.id)])
        #expect(back.shownRest == RestTimer(endsAt: Self.at(160), total: .seconds(90)))
    }

    /// As built, a second question for S9: a member logged while the rest runs leaves it shown, so at its
    /// end "Rest over" stands although a set was logged since the rest began.
    @Test("As built: a member logged while the rest runs does not take it away, running or over (question, S9)")
    func supersetMember_loggedDuringTheRest_asBuilt() {
        let second = Self.superset.exercises[0].sets[1]
        let during = Self.afterFirstRound([.setLogged(
            exerciseIndex: 0, setID: second.id, weight: second.weight, reps: second.reps, doneAt: Self.at(100)
        )])
        #expect(during.shownRest == RestTimer(endsAt: Self.at(160), total: .seconds(90)))
    }
}
