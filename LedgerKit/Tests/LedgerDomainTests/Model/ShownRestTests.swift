import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S6, criteria 2, 4 and 6: `WorkoutState.shownRest`, the rest a screen shows, through the engine: the
/// running rest; after its end the same rest until a set is logged, the rest is skipped or it is extended;
/// otherwise nil. And the two Domain additions the panel's time is written with.
@Suite("WorkoutState.shownRest", .tags(.domain))
struct ShownRestTests {
    /// `events` applied to `state` in order, one envelope each.
    static func after(_ events: [WorkoutEvent], on state: WorkoutState) -> WorkoutState {
        var state = state
        for (offset, event) in events.enumerated() {
            let envelope = EventBuilders.envelope(event, seq: UInt64(offset + 2), at: EventBuilders.start)
            state = WorkoutEngine.reduce(state, envelope).0 ?? state
        }
        return state
    }

    static func at(_ seconds: Double) -> Date {
        EventBuilders.start.addingTimeInterval(seconds)
    }

    /// Row (`exercise`, `set`) of `state` logged as it reads, `seconds` after the start.
    static func logged(_ exercise: Int, _ set: Int, at seconds: Double, in state: WorkoutState) -> WorkoutEvent {
        let row = state.exercises[exercise].sets[set]
        return .setLogged(
            exerciseIndex: exercise,
            setID: row.id,
            weight: row.weight,
            reps: row.reps,
            doneAt: at(seconds)
        )
    }

    static let solo = EventBuilders.seedSession()
    static let superset = EventBuilders.session(EventBuilders.supersetExercises)

    @Test("A workout with no set logged shows no rest")
    func fresh_showsNone() {
        #expect(Self.solo.shownRest == nil)
    }

    @Test("A logged set starts the exercise's rest, and that rest is shown; it is still shown after its end")
    func loggedSet_showsItsRest_alsoAfterItsEnd() throws {
        let state = Self.after([Self.logged(0, 0, at: 60, in: Self.solo)], on: Self.solo)
        let rest = try #require(state.shownRest)
        #expect(rest == RestTimer(endsAt: Self.at(210), total: .seconds(150)))
        // The value holds no clock: it is the same before and after its end, and reads zero then.
        #expect(rest.remaining(at: Self.at(100)) == .seconds(110))
        #expect(rest.remaining(at: Self.at(400)) == .zero)
    }

    @Test("With auto rest off a logged set starts no rest, and none is shown")
    func autoRestOff_showsNone() {
        let off = EventBuilders.seedSession(autoRest: false)
        let state = Self.after([Self.logged(0, 0, at: 60, in: off)], on: off)
        #expect(state.exercises[0].sets[0].isDone)
        #expect(state.shownRest == nil)
    }

    @Test("Skipping ends it; the next logged set replaces it with its own")
    func skip_andTheNextSet() {
        let first = Self.logged(0, 0, at: 60, in: Self.solo)
        #expect(Self.after([first, .restSkipped], on: Self.solo).shownRest == nil)
        // The second set is logged long after the first rest's end: the rest shown is the second's.
        let second = Self.logged(0, 1, at: 500, in: Self.solo)
        let state = Self.after([first, second], on: Self.solo)
        #expect(state.shownRest == RestTimer(endsAt: Self.at(650), total: .seconds(150)))
    }

    @Test("+30s on a running rest grows it; at Rest over it starts a rest of 30 s at the tap (decision #7)")
    func extended() {
        let first = Self.logged(0, 0, at: 60, in: Self.solo)
        let grown = Self.after(
            [first, .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: Self.at(100))],
            on: Self.solo
        )
        #expect(grown.shownRest == RestTimer(endsAt: Self.at(240), total: .seconds(180)))
        let fresh = Self.after(
            [first, .restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: Self.at(400))],
            on: Self.solo
        )
        #expect(fresh.shownRest == RestTimer(endsAt: Self.at(430), total: .seconds(30)))
    }

    @Test("Un-logging a set never cancels a rest (rule 22): not the set that started it, not another")
    func unlog_keepsTheRest() {
        let first = Self.logged(0, 0, at: 60, in: Self.solo)
        let second = Self.logged(0, 1, at: 300, in: Self.solo)
        let rest = RestTimer(endsAt: Self.at(450), total: .seconds(150))
        let own = Self.after(
            [first, second, .setUnlogged(exerciseIndex: 0, setID: Self.solo.exercises[0].sets[1].id)],
            on: Self.solo
        )
        #expect(own.shownRest == rest)
        let other = Self.after(
            [first, second, .setUnlogged(exerciseIndex: 0, setID: Self.solo.exercises[0].sets[0].id)],
            on: Self.solo
        )
        #expect(other.shownRest == rest)
    }

    @Test("In a superset: a member logged while the rest runs keeps it; one logged after its end takes it away")
    func supersetMember_thatStartsNoRest() {
        // A1 then B1 end the first round at 70 s: the group's rest, 90 s, ends at 160 s.
        let round = [Self.logged(0, 0, at: 60, in: Self.superset), Self.logged(1, 0, at: 70, in: Self.superset)]
        let rest = RestTimer(endsAt: Self.at(160), total: .seconds(90))
        #expect(Self.after(round, on: Self.superset).shownRest == rest)
        // A2 starts no rest of its own. Logged while the rest runs, the rest is still shown, also after its end.
        let during = Self.after(round + [Self.logged(0, 1, at: 100, in: Self.superset)], on: Self.superset)
        #expect(during.rest == rest)
        #expect(during.shownRest == rest)
        // Logged after the rest's end, the engine still holds the ended rest, and it is no longer shown.
        let afterward = Self.after(round + [Self.logged(0, 1, at: 200, in: Self.superset)], on: Self.superset)
        #expect(afterward.rest == rest)
        #expect(afterward.shownRest == nil)
        // At the very moment of its end counts as after it.
        let atTheEnd = Self.after(round + [Self.logged(0, 1, at: 160, in: Self.superset)], on: Self.superset)
        #expect(atTheEnd.shownRest == nil)
    }

    @Test("A workout that has ended shows no rest, whatever it holds")
    func ended_showsNone() {
        var state = Self.after([Self.logged(0, 0, at: 60, in: Self.solo)], on: Self.solo)
        #expect(Self.after([.discarded(endedAt: Self.at(90))], on: state).shownRest == nil)
        #expect(Self.after([.finished(endedAt: Self.at(90))], on: state).shownRest == nil)
        // A snapshot from anywhere: not live, with a rest left in it.
        state.phase = .finished
        #expect(state.rest != nil)
        #expect(state.shownRest == nil)
    }

    @Test("A rest of no length, logged at its own end, is not shown; dates that are no dates do not trap")
    func edges() {
        var state = Self.solo
        state.exercises[0].sets[0].doneAt = Self.at(60)
        state.rest = RestTimer(endsAt: Self.at(60), total: .zero)
        #expect(state.shownRest == nil)
        // A rest that ends at no time: no logged set is before its end, so it is not shown.
        state.rest = RestTimer(endsAt: Date(timeIntervalSinceReferenceDate: .nan), total: .seconds(90))
        #expect(state.shownRest == nil)
        state.exercises[0].sets[0].doneAt = Date(timeIntervalSinceReferenceDate: .infinity)
        state.rest = RestTimer(endsAt: Self.at(90), total: .seconds(30))
        #expect(state.shownRest == nil)
    }

    // MARK: The countdown's text and its tick

    @Test("A countdown is written by the whole second, rounded up: 0:00 only when nothing is left", arguments: [
        (90.0, "1:30"), (89.999, "1:30"), (89.001, "1:30"), (89.0, "1:29"), (60.0, "1:00"), (0.001, "0:01"),
        (0.0, "0:00"), (-5.0, "0:00"), (3600.0, "1:00:00"), (3599.2, "1:00:00")
    ])
    func remainingText(seconds: Double, text: String) {
        #expect(ClockText.remaining(.seconds(seconds)) == text)
    }

    @Test("The longest duration there is does not trap")
    func remainingText_saturates() {
        let longest = Duration(secondsComponent: .max, attosecondsComponent: 999_999_999_999_999_999)
        #expect(ClockText.remaining(longest) == ClockText.elapsed(longest))
    }

    @Test("The next tick is the next whole second left: the fraction first, then a second at a time, then none")
    func nextTick() {
        let rest = RestTimer(endsAt: Self.at(90), total: .seconds(90))
        #expect(rest.nextTick(after: Self.at(0)) == .seconds(1))
        #expect(rest.nextTick(after: Self.at(15.75)) == .milliseconds(250))
        #expect(rest.nextTick(after: Self.at(89)) == .seconds(1))
        #expect(rest.nextTick(after: Self.at(90)) == nil)
        #expect(rest.nextTick(after: Self.at(500)) == nil)
        #expect(rest.nextTick(after: Date(timeIntervalSinceReferenceDate: .nan)) == nil)
        // After each tick the text has changed, and after the last nothing is left.
        var now = Self.at(15.75)
        var texts: [String] = []
        while let wait = rest.nextTick(after: now), texts.count < 100 {
            now = now.addingTimeInterval(wait / .seconds(1))
            texts.append(ClockText.remaining(rest.remaining(at: now)))
        }
        #expect(texts.count == 75)
        #expect(texts.prefix(2) == ["1:14", "1:13"])
        #expect(texts.last == "0:00")
    }
}
