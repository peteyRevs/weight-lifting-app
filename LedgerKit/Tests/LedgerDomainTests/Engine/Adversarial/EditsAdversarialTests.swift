import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Rules 5–8 and 11 and criteria 11–12, attacked: field-wise LWW races, clamps, exact weights,
/// set IDs reused across devices and exercises, and swaps.
@Suite("WorkoutEngine · in-session edits (adversarial)", .tags(.domain))
struct EditsAdversarialTests {
    typealias Adv = EngineAdv

    static func target(_ weight: Weight?, _ reps: Int?, row set: Int = 1) -> WorkoutEvent {
        .setTargetChanged(
            exerciseIndex: 0,
            setID: Adv.sid(0, set),
            weight: weight,
            reps: reps.map { Reps(clamping: $0) }
        )
    }

    @Test("Criterion 11: W's 190 at t = 10 beats P's 195 at t = 9, in every arrival order.")
    func criterion11_lastWriterWins() {
        let watch = Adv.env(Self.target(pounds("190"), nil), Adv.watch, seq: 1, at: 10)
        let phone = Adv.env(Self.target(pounds("195"), nil), Adv.phone, seq: 2, at: 9)
        for arrival in [[Adv.start(), watch, phone], [Adv.start(), phone, watch], [phone, watch, Adv.start()]] {
            #expect(Adv.row(WorkoutEngine.replay(arrival), 0, 1)?.weight == pounds("190"))
            #expect(Adv.row(Replica(arrival).state, 0, 1)?.weight == pounds("190"))
        }
    }

    @Test("Rule 5: last-writer-wins is per field — an older reps edit survives a newer weight-only edit.")
    func lww_isPerField() {
        let phone = Adv.env(Self.target(pounds("200"), 3), Adv.phone, seq: 2, at: 9)
        let watch = Adv.env(Self.target(pounds("190"), nil), Adv.watch, seq: 1, at: 10)
        let row = Adv.row(WorkoutEngine.replay([Adv.start(), watch, phone]), 0, 1)
        #expect(row?.weight == pounds("190"))
        #expect(row?.reps == Reps(clamping: 3))
    }

    @Test("Rules 1 / 5 / 7 and spec §7.1: every weight an event writes is clamped to ≥ 0.")
    func negativeWeights_clampToZero() throws {
        let minus = Weight.zero - pounds("5")
        let added = LoggedSet(id: SetID(EventBuilders.uuid(0xADD)), weight: minus, reps: Reps.one, kind: .added)
        let state = try #require(WorkoutEngine.replay([
            Adv.start(),
            Adv.env(Self.target(minus, nil, row: 1), seq: 2, at: 1),
            Adv.env(
                .setLogged(
                    exerciseIndex: 0,
                    setID: Adv.sid(0, 2),
                    weight: minus,
                    reps: Reps.one,
                    doneAt: engineTime(2)
                ),
                seq: 3,
                at: 2
            ),
            Adv.env(.allSetsRepeated(exerciseIndex: 1, weight: minus, reps: Reps.one), seq: 4, at: 3),
            Adv.env(.setAdded(exerciseIndex: 2, set: added), seq: 5, at: 4)
        ]))
        #expect(Adv.row(state, 0, 1)?.weight == .zero)
        #expect(Adv.row(state, 0, 2)?.weight == .zero)
        #expect(state.exercises[1].sets.allSatisfy { $0.weight == .zero })
        #expect(state.exercises[2].sets.last?.weight == .zero)
        #expect(state.volume == .zero)
    }

    @Test("ADR-007: weights pass through events exactly (187.5 lb, 102.5 kg, 0.0000001 g) and volume stays exact.")
    func exactDecimalWeights() throws {
        let tiny = Weight(grams: dec("0.0000001"))
        let state = try #require(WorkoutEngine.replay([
            Adv.start(),
            Adv.env(Adv.logged(0, 0, pounds: "187.5", reps: 3, doneAt: 1), seq: 2, at: 1),
            Adv.env(Self.target(.kilograms(dec("102.5")), nil, row: 1), seq: 3, at: 2),
            Adv.env(Self.target(tiny, nil, row: 2), seq: 4, at: 3)
        ]))
        #expect(Adv.row(state, 0, 0)?.weight.grams == dec("85048.569375"))
        #expect(Adv.row(state, 0, 1)?.weight.grams == dec("102500"))
        #expect(Adv.row(state, 0, 2)?.weight.grams == dec("0.0000001"))
        #expect(state.volume.gramReps == dec("255145.708125"))
    }
}

// MARK: - Added, repeated and swapped rows (rules 6–8)

extension EditsAdversarialTests {
    @Test("Rule 6: setAdded is idempotent by set.id — the same ID from two devices adds one row, first by order wins.")
    func setAdded_sameIDFromTwoDevices() throws {
        let id = SetID(EventBuilders.uuid(0xADD))
        let fromWatch = Adv.env(
            .setAdded(exerciseIndex: 1, set: LoggedSet(id: id, weight: pounds("60"), reps: Reps.one, kind: .added)),
            Adv.watch, seq: 1, at: 10
        )
        let fromPhone = Adv.env(
            .setAdded(exerciseIndex: 1, set: LoggedSet(id: id, weight: pounds("65"), reps: Reps.one, kind: .added)),
            Adv.phone, seq: 2, at: 11
        )
        for arrival in [[Adv.start(), fromWatch, fromPhone], [Adv.start(), fromPhone, fromWatch]] {
            let state = try #require(Replica(arrival).state)
            #expect(state.exercises[1].sets.count(where: { $0.id == id }) == 1)
            #expect(state.exercises[1].sets.last?.weight == pounds("60"))
            #expect(state.totalSets == 19)
        }
    }

    @Test("Rule 26: an added row goes at the very end (after the drop row), undone, of kind .added.")
    func setAdded_appendsUndoneAddedRow() throws {
        let specs = [Adv.spec("A", sets: 2, rest: 60, drop: true)]
        let id = SetID(EventBuilders.uuid(0xADD))
        // The originating device already ticked it and mislabelled it; the row is still a new undone .added set.
        let odd = LoggedSet(id: id, weight: pounds("45"), reps: Reps.one, kind: .drop, doneAt: engineTime(3))
        let state = try #require(WorkoutEngine.replay([
            Adv.start(EventBuilders.session(specs)), Adv.env(.setAdded(exerciseIndex: 0, set: odd), seq: 2, at: 5)
        ]))
        let last = try #require(state.exercises[0].sets.last)
        #expect(state.exercises[0].sets.count == 4)
        #expect(last.id == id)
        #expect(last.kind == .added, "rule 26: an added set has no drop flag")
        #expect(last.doneAt == nil, "rule 26: an added set is new and undone")
    }

    @Test("Rule 6: a setAdded reusing a set ID that another exercise already holds is ignored (IDs stay unique).")
    func setAdded_idTakenByAnotherExercise_isIgnored() throws {
        let clash = LoggedSet(id: Adv.sid(0, 0), weight: pounds("45"), reps: Reps.one, kind: .added)
        let state = try #require(WorkoutEngine.replay([
            Adv.start(),
            Adv.env(.setAdded(exerciseIndex: 3, set: clash), seq: 2, at: 5)
        ]))
        let ids = state.exercises.flatMap(\.sets).map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(state.totalSets == 18)
    }

    @Test("Rule 7 / rule 25: repeat writes into every row incl. drop and added rows; done flags and times kept.")
    func allSetsRepeated_everyRowKeepsDone() throws {
        let specs = [Adv.spec("A", sets: 2, rest: 60, drop: true)]
        let added = LoggedSet(id: SetID(EventBuilders.uuid(0xADD)), weight: pounds("10"), reps: Reps.one, kind: .added)
        let state = try #require(WorkoutEngine.replay([
            Adv.start(EventBuilders.session(specs)),
            Adv.env(.setAdded(exerciseIndex: 0, set: added), seq: 2, at: 1),
            Adv.env(Adv.logged(0, 1, pounds: "50", reps: 8, doneAt: 2), seq: 3, at: 2),
            Adv.env(.allSetsRepeated(exerciseIndex: 0, weight: pounds("52.5"), reps: Reps(clamping: 10)), seq: 4, at: 3)
        ]))
        #expect(state.exercises[0].sets.allSatisfy { $0.weight == pounds("52.5") && $0.reps.value == 10 })
        #expect(state.exercises[0].sets.map(\.doneAt) == [nil, engineTime(2), nil, nil])
    }

    @Test("Rule 8 / rule 27: a swap changes only exerciseID and name (also inside a superset, decision #13).")
    func swap_keepsEverythingElse() throws {
        let snapshot = EventBuilders.session(EventBuilders.supersetExercises)
        let newID = ExerciseID(EventBuilders.uuid(0xA9))
        let logged = try #require(Adv.state(after: [
            Adv.start(snapshot),
            Adv.env(Adv.logged(1, 0, doneAt: 1), seq: 2, at: 1)
        ]))
        let state = try #require(Adv.state(after: [
            Adv.env(
                .exerciseSwapped(
                    exerciseIndex: 1,
                    exerciseID: newID,
                    name: "Seated Cable Row",
                    alsoUpdateProgram: false
                ),
                Adv.watch,
                seq: 1,
                at: 2
            )
        ], from: logged))
        var expected = logged.exercises[1]
        expected.exerciseID = newID
        expected.name = "Seated Cable Row"
        #expect(state.exercises[1] == expected)
        #expect(state.exercises[0] == logged.exercises[0])
        #expect(state.programUpdates.isEmpty)
        #expect(state.rest == logged.rest)
        #expect(state.cursor == logged.cursor)
    }
}
