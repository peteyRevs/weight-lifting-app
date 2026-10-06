import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criterion 7: `DayEditing.set` clamps and then couples; `stepped` gives the value one step
/// away and does not clamp. Expected values are the spec's (§3.4, rules 1–3 and 6), worked by hand.
@Suite("DayEditing · fields", .tags(.domain))
struct DayEditingFieldsTests {
    private typealias Support = EditingSupport

    /// What `set` stores for a value, on a slot of 1 rep with the top of its range at 2 (so that the clamp
    /// of the top of the range is seen without the coupling).
    struct ClampRow: Sendable, CustomStringConvertible {
        let set: SlotField
        let stores: SlotField

        var description: String {
            "\(set) → \(stores)"
        }

        static let sets: [ClampRow] = [
            ClampRow(set: .sets(0), stores: .sets(1)),
            ClampRow(set: .sets(1), stores: .sets(1)),
            ClampRow(set: .sets(7), stores: .sets(7)),
            ClampRow(set: .sets(12), stores: .sets(12)),
            ClampRow(set: .sets(13), stores: .sets(12)),
            ClampRow(set: .sets(.min), stores: .sets(1)),
            ClampRow(set: .sets(.max), stores: .sets(12))
        ]
        static let reps: [ClampRow] = [
            ClampRow(set: .reps(0), stores: .reps(1)),
            ClampRow(set: .reps(1), stores: .reps(1)),
            ClampRow(set: .reps(30), stores: .reps(30)),
            ClampRow(set: .reps(31), stores: .reps(30)),
            ClampRow(set: .reps(.min), stores: .reps(1)),
            ClampRow(set: .reps(.max), stores: .reps(30)),
            ClampRow(set: .repsHi(0), stores: .repsHi(2)),
            ClampRow(set: .repsHi(1), stores: .repsHi(2)),
            ClampRow(set: .repsHi(2), stores: .repsHi(2)),
            ClampRow(set: .repsHi(40), stores: .repsHi(40)),
            ClampRow(set: .repsHi(41), stores: .repsHi(40)),
            ClampRow(set: .repsHi(.min), stores: .repsHi(2)),
            ClampRow(set: .repsHi(.max), stores: .repsHi(40))
        ]
        static let rpe: [ClampRow] = [
            ClampRow(set: .rpe(dec("4.5")), stores: .rpe(5)),
            ClampRow(set: .rpe(5), stores: .rpe(5)),
            ClampRow(set: .rpe(10), stores: .rpe(10)),
            ClampRow(set: .rpe(dec("10.5")), stores: .rpe(10)),
            ClampRow(set: .rpe(-3), stores: .rpe(5)),
            ClampRow(set: .rpe(.greatestFiniteMagnitude), stores: .rpe(10)),
            ClampRow(set: .rpe(.nan), stores: .rpe(5)),
            ClampRow(set: .rpe(dec("7.2")), stores: .rpe(7)),
            ClampRow(set: .rpe(dec("7.25")), stores: .rpe(dec("7.5"))),
            ClampRow(set: .rpe(dec("7.3")), stores: .rpe(dec("7.5"))),
            ClampRow(set: .rpe(dec("7.74")), stores: .rpe(dec("7.5"))),
            ClampRow(set: .rpe(dec("7.75")), stores: .rpe(8))
        ]
        static let rest: [ClampRow] = [
            ClampRow(set: .restSeconds(15), stores: .restSeconds(30)),
            ClampRow(set: .restSeconds(30), stores: .restSeconds(30)),
            ClampRow(set: .restSeconds(300), stores: .restSeconds(300)),
            ClampRow(set: .restSeconds(315), stores: .restSeconds(300)),
            ClampRow(set: .restSeconds(0), stores: .restSeconds(30)),
            ClampRow(set: .restSeconds(.min), stores: .restSeconds(30)),
            ClampRow(set: .restSeconds(.max), stores: .restSeconds(300)),
            ClampRow(set: .restSeconds(37), stores: .restSeconds(30)),
            ClampRow(set: .restSeconds(38), stores: .restSeconds(45)),
            ClampRow(set: .restSeconds(100), stores: .restSeconds(105)),
            ClampRow(set: .restSeconds(292), stores: .restSeconds(285)),
            ClampRow(set: .restSeconds(293), stores: .restSeconds(300))
        ]
        static let startLoad: [ClampRow] = [
            ClampRow(set: .startLoad(.pounds(-5)), stores: .startLoad(.zero)),
            ClampRow(set: .startLoad(.zero), stores: .startLoad(.zero)),
            ClampRow(set: .startLoad(Weight(grams: .nan)), stores: .startLoad(.zero)),
            ClampRow(set: .startLoad(.pounds(dec("181.3"))), stores: .startLoad(.pounds(dec("181.3")))),
            ClampRow(set: .startLoad(.kilograms(dec("81.25"))), stores: .startLoad(.kilograms(dec("81.25"))))
        ]
    }

    /// One slot: `reps` with the top of the range at `repsHi`.
    private func day(reps: Int, repsHi: Int) throws -> DayTemplate {
        try DayTemplate(
            id: DayTemplateID(Fixtures.uuid(500)),
            name: "Day",
            tag: "DY",
            slots: [Fixtures.slot(Fixtures.bench, id: 1, reps: reps, repsHi: repsHi)]
        )
    }

    /// Reps and the top of the range after `field` is set on a slot of `reps` and `repsHi`.
    private func range(_ field: SlotField, reps: Int, repsHi: Int) throws -> [Int] {
        let slot = try DayEditing.set(field, slot: Support.slot(1), in: day(reps: reps, repsHi: repsHi)).slots[0]
        return [slot.reps, slot.repsHi]
    }

    @Test(
        "Every field is clamped to its range, and a value off the step goes to the nearest step (rules 2, 3, 6)",
        arguments: ClampRow.sets + ClampRow.reps + ClampRow.rpe + ClampRow.rest + ClampRow.startLoad
    )
    func set_clampsEveryField(row: ClampRow) throws {
        let before = try day(reps: 1, repsHi: 2)
        let after = DayEditing.set(row.set, slot: Support.slot(1), in: before)
        let kind = Support.kind(of: row.set)
        #expect(Support.value(kind, of: after.slots[0]) == row.stores)
        #expect(Support.faults(in: after).isEmpty)
        let changed = Set(Support.changedFields(before.slots[0], after.slots[0]))
        #expect(changed.isSubset(of: ["\(kind)", "repsHi"]), "only the field, and the top of the range with reps")
        #expect(Support.difference(DayEditing.set(row.set, slot: Support.slot(1), in: after), after).isEmpty)
    }

    @Test("Reps raised to the top of the range or above push the top to reps + 1 (rule 2, F11 criterion 8)")
    func setReps_atOrAboveTheTop_pushesTheTop() throws {
        #expect(try range(.reps(9), reps: 8, repsHi: 10) == [9, 10])
        #expect(try range(.reps(10), reps: 8, repsHi: 10) == [10, 11])
        #expect(try range(.reps(12), reps: 8, repsHi: 10) == [12, 13])
        #expect(try range(.reps(7), reps: 8, repsHi: 10) == [7, 10], "lowering reps leaves the top")
        #expect(try range(.reps(30), reps: 8, repsHi: 10) == [30, 31])
        #expect(try range(.reps(99), reps: 8, repsHi: 10) == [30, 31], "clamped first, then coupled")
        #expect(try range(.reps(30), reps: 8, repsHi: 40) == [30, 40])
        #expect(try range(.reps(-4), reps: 8, repsHi: 10) == [1, 10])
    }

    @Test("A top of the range lowered to reps or below snaps to reps + 1 (rule 2, F11 criterion 8)")
    func setRepsHi_atOrBelowReps_snapsAbove() throws {
        #expect(try range(.repsHi(8), reps: 8, repsHi: 10) == [8, 9])
        #expect(try range(.repsHi(3), reps: 8, repsHi: 10) == [8, 9])
        #expect(try range(.repsHi(9), reps: 8, repsHi: 10) == [8, 9])
        #expect(try range(.repsHi(11), reps: 8, repsHi: 10) == [8, 11])
        #expect(try range(.repsHi(0), reps: 8, repsHi: 10) == [8, 9], "clamped to 2, then lifted above reps")
        #expect(try range(.repsHi(30), reps: 30, repsHi: 31) == [30, 31])
        #expect(try range(.repsHi(41), reps: 30, repsHi: 31) == [30, 40])
        #expect(try range(.repsHi(1), reps: 1, repsHi: 2) == [1, 2])
    }

    @Test("A start load is stored exactly as given, in either unit, with no rounding to a step")
    func setStartLoad_isStoredExactly() throws {
        let upperA = try Fixtures.upperA()
        let slot = Support.slot(302)
        #expect(upperA.slots[1].startLoad == nil)
        let pounds = DayEditing.set(.startLoad(.pounds(dec("52.5"))), slot: slot, in: upperA).slots[1]
        #expect(pounds.startLoad?.grams == dec("23813.599425"))
        let kilograms = DayEditing.set(.startLoad(.kilograms(dec("23.75"))), slot: slot, in: upperA).slots[1]
        #expect(kilograms.startLoad?.grams == 23750)
        #expect(Support.changedFields(upperA.slots[1], pounds) == ["startLoad"])
    }
}

// MARK: - stepped

extension DayEditingFieldsTests {
    struct StepRow: Sendable, CustomStringConvertible {
        let kind: SlotField.Kind
        let downward: SlotField
        let upward: SlotField

        var description: String {
            "\(kind): \(downward) and \(upward)"
        }

        /// From Upper A's bench press: 5 × 5, top 7, RPE 8, rest 150 s, start load 180 lb from the exercise.
        static let fromBench: [StepRow] = [
            StepRow(kind: .sets, downward: .sets(4), upward: .sets(6)),
            StepRow(kind: .reps, downward: .reps(4), upward: .reps(6)),
            StepRow(kind: .repsHi, downward: .repsHi(6), upward: .repsHi(8)),
            StepRow(kind: .rpe, downward: .rpe(dec("7.5")), upward: .rpe(dec("8.5"))),
            StepRow(kind: .rest, downward: .restSeconds(135), upward: .restSeconds(165)),
            StepRow(kind: .startLoad, downward: .startLoad(.pounds(175)), upward: .startLoad(.pounds(185)))
        ]

        /// From a slot at every upper limit, and from one at every lower limit: the value past the limit.
        static let pastTheLimits: [StepRow] = [
            StepRow(kind: .sets, downward: .sets(0), upward: .sets(13)),
            StepRow(kind: .reps, downward: .reps(0), upward: .reps(31)),
            StepRow(kind: .repsHi, downward: .repsHi(1), upward: .repsHi(41)),
            StepRow(kind: .rpe, downward: .rpe(dec("4.5")), upward: .rpe(dec("10.5"))),
            StepRow(kind: .rest, downward: .restSeconds(15), upward: .restSeconds(315))
        ]
    }

    private func stepped(_ kind: SlotField.Kind, _ direction: StepDirection, of slot: Slot) -> SlotField {
        DayEditing.stepped(kind, direction, of: slot, exercise: Fixtures.bench, units: .lb)
    }

    @Test(
        "A step is 1 for sets and reps, 0.5 for RPE, 15 s for rest and the unit step for the load (rules 1, 3, 6)",
        arguments: StepRow.fromBench
    )
    func stepped_isOneStepAway(row: StepRow) throws {
        let bench = try Fixtures.upperA().slots[0]
        #expect(stepped(row.kind, .downward, of: bench) == row.downward)
        #expect(stepped(row.kind, .upward, of: bench) == row.upward)
    }

    @Test("stepped does not clamp: from a limit it gives the value past it", arguments: StepRow.pastTheLimits)
    func stepped_atALimit_doesNotClamp(row: StepRow) throws {
        let lowest = try Fixtures.slot(Fixtures.bench, id: 1, sets: 1, reps: 1, repsHi: 2, rpe: 5, rest: 30)
        let highest = try Fixtures.slot(Fixtures.bench, id: 2, sets: 12, reps: 30, repsHi: 40, rpe: 10, rest: 300)
        #expect(stepped(row.kind, .downward, of: lowest) == row.downward)
        #expect(stepped(row.kind, .upward, of: highest) == row.upward)
    }

    @Test("A stepper at its limit leaves the value where it is: set(stepped(…)) changes nothing")
    func setStepped_atALimit_theValueStays() throws {
        let lowest = try Fixtures.slot(
            Fixtures.bench,
            id: 1,
            sets: 1,
            reps: 1,
            repsHi: 2,
            rpe: 5,
            rest: 30,
            startLoad: .zero
        )
        let highest = try Fixtures.slot(Fixtures.bench, id: 2, sets: 12, reps: 30, repsHi: 40, rpe: 10, rest: 300)
        let day = DayTemplate(id: DayTemplateID(Fixtures.uuid(500)), name: "Day", tag: "DY", slots: [lowest, highest])
        for kind in SlotField.Kind.allCases {
            let down = DayEditing.set(stepped(kind, .downward, of: lowest), slot: lowest.id, in: day)
            #expect(Support.difference(down, day).isEmpty, "\(kind) down")
        }
        for kind in SlotField.Kind.allCases where kind != .startLoad {
            let upward = DayEditing.set(stepped(kind, .upward, of: highest), slot: highest.id, in: day)
            #expect(Support.difference(upward, day).isEmpty, "\(kind) up: a start load has no upper limit")
        }
    }

    @Test("Stepping reps into the top of the range, or the top down onto reps, keeps the top above reps")
    func setStepped_repsAgainstTheTop_keepsTheRange() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, reps: 8, repsHi: 9)
        let day = DayTemplate(id: DayTemplateID(Fixtures.uuid(500)), name: "Day", tag: "DY", slots: [slot])
        let repsUp = DayEditing.set(stepped(.reps, .upward, of: slot), slot: slot.id, in: day).slots[0]
        #expect(repsUp.reps == 9)
        #expect(repsUp.repsHi == 10)
        let topDown = DayEditing.set(stepped(.repsHi, .downward, of: slot), slot: slot.id, in: day).slots[0]
        #expect(topDown.reps == 8)
        #expect(topDown.repsHi == 9)
    }
}
