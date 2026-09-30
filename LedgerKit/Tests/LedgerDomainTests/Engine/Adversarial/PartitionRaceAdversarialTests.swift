import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Criterion 9 and rule 12 on hand-built races: both sides of a partition edit the same set, the
/// same exercise, or depend on each other's envelopes, and a third device hears it all out of order.
@Suite("WorkoutEngine · partition races (adversarial)", .tags(.domain))
struct PartitionRaceAdversarialTests {
    typealias Adv = EngineAdv

    /// Every device receives `envelopes` in each of the given arrival orders; all must agree with replay.
    static func expectConvergence(_ envelopes: [EventEnvelope], orders: Int = 24) throws -> WorkoutState {
        let expected = try #require(WorkoutEngine.replay(envelopes))
        var generator = SeededGenerator(seed: 0xF04)
        for _ in 0 ..< orders {
            let arrival = envelopes.shuffled(using: &generator)
            #expect(Replica(arrival).state == expected, "arrival \(arrival.map(\.key.seq))")
        }
        return expected
    }

    @Test(
        "Same set, same wall clock: P logs while W bumps weight and un-logs — the device tie-break decides, everywhere."
    )
    func sameSetSameInstant_logTargetUnlog() throws {
        let state = try Self.expectConvergence([
            Adv.start(),
            Adv.env(Adv.logged(0, 0, pounds: "185", reps: 5, doneAt: 10), Adv.phone, seq: 2, at: 10),
            Adv.env(
                .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 0), weight: pounds("190"), reps: nil),
                Adv.watch,
                seq: 1,
                at: 10
            ),
            Adv.env(.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)), Adv.watch, seq: 2, at: 10)
        ])
        // Phone (lower ID) first, then the watch's two in seq order.
        #expect(Adv.row(state, 0, 0) == LoggedSet(
            id: Adv.sid(0, 0),
            weight: pounds("190"),
            reps: Reps(clamping: 5),
            kind: .working
        ))
        #expect(state.rest?.endsAt == engineTime(160), "un-log never clears rest (rule 22)")
    }

    @Test("Both devices log the same set during a partition: one done row, the first logger's rest, one cursor.")
    func bothLogSameSet() throws {
        let state = try Self.expectConvergence([
            Adv.start(),
            Adv.env(Adv.logged(0, 0, pounds: "185", reps: 5, doneAt: 12), Adv.phone, seq: 2, at: 12),
            Adv.env(Adv.logged(0, 0, pounds: "185", reps: 4, doneAt: 10), Adv.watch, seq: 1, at: 10)
        ])
        // The later envelope's values win (rule 3); rest comes from the first not-done → done transition.
        #expect(Adv.row(state, 0, 0)?.reps == Reps(clamping: 5))
        #expect(state.rest == RestTimer(endsAt: engineTime(160), total: .seconds(150)))
        #expect(state.cursor == Adv.cursor(0, 1))
        #expect(state.doneSets == 1)
    }

    @Test("W swaps exercise 1 while P logs its first set: the set stays done on the swapped exercise.")
    func swapVersusLog() throws {
        let newID = ExerciseID(EventBuilders.uuid(0xA3))
        let state = try Self.expectConvergence([
            Adv.start(),
            Adv.env(
                .exerciseSwapped(
                    exerciseIndex: 1,
                    exerciseID: newID,
                    name: "Machine Incline Press",
                    alsoUpdateProgram: false
                ),
                Adv.watch,
                seq: 1,
                at: 10
            ),
            Adv.env(Adv.logged(1, 0, pounds: "55", reps: 10, doneAt: 9), Adv.phone, seq: 2, at: 9)
        ])
        #expect(state.exercises[1].exerciseID == newID)
        #expect(Adv.row(state, 1, 0)?.isDone == true)
    }

    @Test("A third device hears P's log of W's added set before the add itself; it still converges on a done row.")
    func thirdDevice_logBeforeAdd() throws {
        let id = SetID(EventBuilders.uuid(0xADD))
        let add = Adv.env(
            .setAdded(
                exerciseIndex: 2,
                set: LoggedSet(id: id, weight: pounds("70"), reps: Reps(clamping: 8), kind: .added)
            ),
            Adv.watch, seq: 1, at: 10
        )
        let log = Adv.env(.setLogged(
            exerciseIndex: 2,
            setID: id,
            weight: pounds("70"),
            reps: Reps(clamping: 8),
            doneAt: engineTime(20)
        ), Adv.phone, seq: 2, at: 20)
        let state = try Self.expectConvergence([Adv.start(), add, log])
        #expect(state.exercises[2].sets.last?.isDone == true)
        // A device that just reduced in arrival order would disagree; ADR-004 rule 2 is why it must rebuild.
        #expect(Adv.state(after: [Adv.start(), log, add])?.exercises[2].sets.last?.isDone == false)
    }

    @Test("Criterion 9 with three devices: each edits a different field of the same set; every field survives.")
    func threeDevices_disjointFields() throws {
        let state = try Self.expectConvergence([
            Adv.start(),
            Adv.env(
                .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 3), weight: pounds("195"), reps: nil),
                Adv.phone,
                seq: 2,
                at: 5
            ),
            Adv.env(
                .setTargetChanged(exerciseIndex: 0, setID: Adv.sid(0, 3), weight: nil, reps: Reps(clamping: 3)),
                Adv.watch,
                seq: 1,
                at: 6
            ),
            Adv.env(.exerciseSelected(exerciseIndex: 0, setIndex: 3), Adv.tablet, seq: 1, at: 7)
        ])
        #expect(Adv.row(state, 0, 3)?.weight == pounds("195"))
        #expect(Adv.row(state, 0, 3)?.reps == Reps(clamping: 3))
        #expect(state.cursor == Adv.cursor(0, 3))
    }

    @Test("Rule 12 dedupe is per workout: a stray envelope from another workout never shadows this workout's same key.")
    func strayWorkoutEnvelope_doesNotShadowSameKey() throws {
        let stray = Adv.env(.restSkipped, Adv.watch, seq: 1, at: 5, workoutID: WorkoutID(EventBuilders.uuid(0xBAD)))
        let mine = Adv.env(Adv.logged(0, 0, doneAt: 10), Adv.watch, seq: 1, at: 10)
        // reduce ignores the stray (other workout), so a live device logs the set …
        #expect(Adv.row(Adv.state(after: [Adv.start(), stray, mine]), 0, 0)?.isDone == true)
        // … and replay of the same envelopes must agree.
        let state = try #require(WorkoutEngine.replay([Adv.start(), stray, mine]))
        #expect(
            Adv.row(state, 0, 0)?.isDone == true,
            "the other workout's (watch, 1) deduplicated this workout's (watch, 1)"
        )
        // The criterion-10 oracle dedupes the same way, so it cannot catch this.
        #expect(
            Adv.row(ModelOracle.replay([Adv.start(), stray, mine]), 0, 0)?.isDone == true,
            "ModelOracle shares the bug"
        )
    }
}
