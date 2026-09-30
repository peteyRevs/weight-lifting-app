import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Rules 3, 4 and 20 (spec §7.4) and criteria 1–4, attacked with supersets of 2–3 members, unequal
/// set counts, drop rows, added sets and unlog/relog.
@Suite("WorkoutEngine · setLogged and cursor (adversarial)", .tags(.domain))
struct SetLoggedCursorAdversarialTests {
    typealias Adv = EngineAdv

    /// Logs row (`exercise`, `set`) of `state` at `seconds`, as the next envelope from `device`.
    static func log(
        _ state: WorkoutState?,
        _ exercise: Int,
        _ set: Int,
        at seconds: Double,
        seq: UInt64,
        device: DeviceID = EngineAdv.phone
    ) -> (state: WorkoutState?, effects: [Effect]) {
        let setID = EngineAdv.row(state, exercise, set)?.id ?? EngineAdv.sid(exercise, set)
        let event = WorkoutEvent.setLogged(
            exerciseIndex: exercise, setID: setID, weight: pounds("50"), reps: Reps(clamping: 8),
            doneAt: engineTime(seconds)
        )
        return WorkoutEngine.reduce(state, EngineAdv.env(event, device, seq: seq, at: seconds))
    }

    @Test("Criterion 1: seed session, bench set 1 → rest ends at +150 s, cursor (0, 1), haptic and notification.")
    func criterion1_seedSession() throws {
        let doneAt = engineTime(42)
        let started = Adv.state(after: [Adv.start()])
        let (state, effects) = WorkoutEngine.reduce(started, Adv.env(Adv.logged(0, 0, doneAt: 42), seq: 2, at: 42))
        let rest = try #require(state?.rest)
        #expect(rest == RestTimer(endsAt: doneAt.addingTimeInterval(150), total: .seconds(150)))
        #expect(state?.cursor == Adv.cursor(0, 1))
        #expect(effects.contains(.haptic(.setLogged)))
        #expect(effects.contains(.scheduleRestNotification(endsAt: doneAt.addingTimeInterval(150))))
    }

    @Test("Criterion 1: the rest is anchored to the event's doneAt, not to the envelope's wall clock.")
    func rest_anchoredToDoneAt() {
        let started = Adv.state(after: [Adv.start()])
        let (state, _) = WorkoutEngine.reduce(started, Adv.env(Adv.logged(0, 0, doneAt: 30), Adv.watch, seq: 1, at: 50))
        #expect(state?.rest?.endsAt == engineTime(180))
    }

    @Test("Criterion 2: A(3, 90 s) + B(3, 60 s): A1 → no rest, cursor B1; B1 → 90 s rest, cursor A2.")
    func criterion2_superset() {
        var state = Adv.state(after: [Adv.start(EventBuilders.session(EventBuilders.supersetExercises))])
        state = Self.log(state, 0, 0, at: 10, seq: 2).state
        #expect(state?.rest == nil)
        #expect(state?.cursor == Adv.cursor(1, 0))
        state = Self.log(state, 1, 0, at: 20, seq: 3).state
        #expect(state?.rest == RestTimer(endsAt: engineTime(110), total: .seconds(90)))
        #expect(state?.cursor == Adv.cursor(0, 1))
    }

    @Test("Criterion 3: logging exercise 0's last set moves the cursor to (1, 0).")
    func criterion3_lastSetMovesToNextExercise() {
        var state = Adv.state(after: [Adv.start()])
        for set in 0 ..< 5 {
            state = Self.log(state, 0, set, at: Double(10 * (set + 1)), seq: UInt64(set + 2)).state
        }
        #expect(state?.cursor == Adv.cursor(1, 0))
    }

    @Test("Criterion 4 / rule 22: unlogging a done set keeps the cursor and the running rest.")
    func criterion4_unlogKeepsCursorAndRest() throws {
        let logged = Self.log(Adv.state(after: [Adv.start()]), 0, 0, at: 10, seq: 2).state
        let before = try #require(logged)
        let (after, effects) = WorkoutEngine.reduce(
            before, Adv.env(.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)), Adv.watch, seq: 1, at: 11)
        )
        #expect(after?.cursor == before.cursor)
        #expect(after?.rest == before.rest)
        #expect(Adv.row(after, 0, 0)?.isDone == false)
        #expect(!effects.contains(.cancelRestNotification))
    }

    @Test("Rules 19–20: A(3, 60) B(2, 90) C(4, 120) + D: rest only after each round's last member, cursor round-robin.")
    func threeMemberSuperset_unequalCounts() {
        let specs = [
            Adv.spec("A", sets: 3, rest: 60), Adv.spec("B", sets: 2, rest: 90, superset: true),
            Adv.spec("C", sets: 4, rest: 120, superset: true), Adv.spec("D", sets: 2, rest: 30)
        ]
        // Display order A1 B1 C1 A2 B2 C2 A3 C3 C4; rounds end at C1, C2, C3 (B has no 3rd) and C4.
        let order = [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (2, 2), (2, 3)]
        let lastOfRound: Set = [2, 5, 7, 8]
        var state = Adv.state(after: [Adv.start(EventBuilders.session(specs))])
        for (step, (exercise, set)) in order.enumerated() {
            let seconds = Double(10 * (step + 1))
            let previousRest = state?.rest
            state = Self.log(state, exercise, set, at: seconds, seq: UInt64(step + 2)).state
            if lastOfRound.contains(step) {
                #expect(
                    state?.rest == RestTimer(endsAt: engineTime(seconds + 120), total: .seconds(120)),
                    "step \(step)"
                )
            } else {
                #expect(state?.rest == previousRest, "step \(step): only the round's last member rests")
            }
            let next = step + 1 < order.count ? Adv.cursor(order[step + 1].0, order[step + 1].1) : Adv.cursor(3, 0)
            #expect(state?.cursor == next, "step \(step)")
        }
    }

    @Test("Rule 26 + 19: a set added to B mid-workout makes A2 no longer the last of its round.")
    func addedSet_changesLastOfRound() {
        let specs = [
            Adv.spec("A", sets: 2, rest: 90),
            Adv.spec("B", sets: 1, rest: 60, superset: true),
            Adv.spec("D", sets: 1, rest: 30)
        ]
        let start = Adv.state(after: [Adv.start(EventBuilders.session(specs))])
        let added = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)),
            weight: pounds("50"),
            reps: Reps(clamping: 8),
            kind: .added
        )
        // Without the added set: rounds [A1 B1] [A2] — A2 ends its round.
        var control = Self.log(start, 0, 0, at: 10, seq: 2).state
        control = Self.log(control, 1, 0, at: 20, seq: 3).state
        control = Self.log(control, 0, 1, at: 30, seq: 4).state
        #expect(control?.rest?.endsAt == engineTime(120))
        // With it: rounds [A1 B1] [A2 B2+].
        var state = WorkoutEngine.reduce(
            start,
            Adv.env(.setAdded(exerciseIndex: 1, set: added), Adv.watch, seq: 1, at: 5)
        ).0
        state = Self.log(state, 0, 0, at: 10, seq: 2).state
        state = Self.log(state, 1, 0, at: 20, seq: 3).state
        state = Self.log(state, 0, 1, at: 30, seq: 4).state
        #expect(state?.rest?.endsAt == engineTime(110), "A2 is no longer last of round; B1's rest keeps running")
        #expect(state?.cursor == Adv.cursor(1, 1))
        state = Self.log(state, 1, 1, at: 40, seq: 5).state
        #expect(state?.rest == RestTimer(endsAt: engineTime(130), total: .seconds(90)))
        #expect(state?.cursor == Adv.cursor(2, 0))
    }

    @Test("Rule 3: unlog then relog is a fresh not-done → done transition: rest restarts, cursor advances again.")
    func unlogThenRelog_restartsRest() {
        let start = Adv.state(after: [Adv.start(EventBuilders.session(EventBuilders.supersetExercises))])
        var state = Self.log(start, 0, 0, at: 10, seq: 2).state
        state = Self.log(state, 1, 0, at: 20, seq: 3).state
        state = WorkoutEngine.reduce(
            state,
            Adv.env(.setUnlogged(exerciseIndex: 1, setID: Adv.sid(1, 0)), seq: 4, at: 25)
        ).0
        #expect(state?.rest?.endsAt == engineTime(110))
        #expect(state?.cursor == Adv.cursor(0, 1))
        state = WorkoutEngine.reduce(state, Adv.env(.exerciseSelected(exerciseIndex: 1, setIndex: 1), seq: 5, at: 26)).0
        state = Self.log(state, 1, 0, at: 30, seq: 6).state
        #expect(state?.rest == RestTimer(endsAt: engineTime(120), total: .seconds(90)))
        #expect(state?.cursor == Adv.cursor(0, 1), "next undone after B1 in display order is A2")
    }

    @Test("Rule 3: re-logging an already-done set overwrites its values but leaves rest and cursor alone.")
    func relogDoneSet_onlyOverwrites() throws {
        let once = Self.log(Adv.state(after: [Adv.start()]), 0, 0, at: 10, seq: 2).state
        let before = try #require(once)
        let (after, _) = WorkoutEngine.reduce(
            before,
            Adv.env(Adv.logged(0, 0, pounds: "190", reps: 3, doneAt: 50), Adv.watch, seq: 1, at: 50)
        )
        #expect(Adv.row(after, 0, 0) == LoggedSet(
            id: Adv.sid(0, 0), weight: pounds("190"), reps: Reps(clamping: 3), kind: .working, doneAt: engineTime(50)
        ))
        #expect(after?.rest == before.rest)
        #expect(after?.cursor == before.cursor)
    }
}
