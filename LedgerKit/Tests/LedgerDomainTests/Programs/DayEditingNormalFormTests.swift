import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criteria 1 and 8: no function of `DayEditing` traps, an id the day does not hold changes
/// nothing, and every result is in normal form (its first slot is joined to nothing), whatever arrives.
@Suite("DayEditing · totality and the normal form", .tags(.domain))
struct DayEditingNormalFormTests {
    private typealias Support = EditingSupport

    let upperA: DayTemplate

    init() throws {
        upperA = try Fixtures.upperA()
    }

    /// Every function that takes a slot id, applied to `slot` of `day`.
    private func everyEdit(of slot: SlotID, in day: DayTemplate) -> [(name: String, day: DayTemplate)] {
        [
            ("removeSlot", DayEditing.removeSlot(day, slot: slot)),
            ("set", DayEditing.set(.sets(7), slot: slot, in: day)),
            ("setProgression", DayEditing.setProgression(.fixed, slot: slot, in: day)),
            ("setDropSet", DayEditing.setDropSet(true, slot: slot, in: day)),
            ("setSuperset", DayEditing.setSuperset(true, slot: slot, in: day)),
            ("move up", DayEditing.move(day, slot: slot, .upward)),
            ("move down", DayEditing.move(day, slot: slot, .downward))
        ]
    }

    @Test("No edit changes a slot's misses or its exercise: a workout's save writes those (slice S1 criterion 12)")
    func everyEdit_leavesMissesAndTheExercise() {
        var day = upperA
        for index in day.slots.indices {
            day.slots[index].misses = [1, 3]
        }
        let exercises = Dictionary(uniqueKeysWithValues: day.slots.map { ($0.id, $0.exerciseID) })
        for slot in day.slots {
            let fields = Support.fields.map { (name: "set \($0)", day: DayEditing.set($0, slot: slot.id, in: day)) }
            for edit in everyEdit(of: slot.id, in: day) + fields {
                #expect(edit.day.slots.map(\.misses) == edit.day.slots.map { _ in [1, 3] }, "\(edit.name)")
                #expect(edit.day.slots.map(\.exerciseID) == edit.day.slots.map { exercises[$0.id] }, "\(edit.name)")
            }
        }
    }

    @Test("A slot id the day does not hold leaves the day unchanged, for every function")
    func unknownSlot_changesNothing() {
        for edit in everyEdit(of: SlotID(Support.unknown), in: upperA) {
            #expect(Support.difference(edit.day, upperA).isEmpty, "\(edit.name)")
        }
    }

    @Test("An empty day comes back empty from every function")
    func emptyDay_staysEmpty() {
        let empty = DayTemplate(id: upperA.id, name: "New day", tag: "D5")
        for edit in everyEdit(of: Support.slot(301), in: empty) {
            #expect(Support.difference(edit.day, empty).isEmpty, "\(edit.name)")
        }
        #expect(Support.difference(DayEditing.addSlots(empty, []), empty).isEmpty)
    }

    @Test("A day whose first slot arrives joined is read as its normal form, and comes back in it")
    func firstSlotArrivesJoined_isReadAsItsNormalForm() throws {
        let arriving = try Support.day(joined: [true, true, false])
        let normal = try Support.day(joined: [false, true, false])
        #expect(Support.groups(arriving) == [[1, 2], [3]], "readers ignore the first flag")
        for edit in everyEdit(of: SlotID(Support.unknown), in: arriving) {
            #expect(Support.difference(edit.day, normal).isEmpty, "\(edit.name)")
        }
        #expect(Support.difference(DayEditing.addSlots(arriving, []), normal).isEmpty)
        for (index, number) in [1, 2, 3].enumerated() {
            for edit in everyEdit(of: Support.slot(number), in: arriving) {
                let same = everyEdit(of: Support.slot(number), in: normal).first { $0.name == edit.name }
                #expect(same.map { Support.difference(edit.day, $0.day) } == "", "\(edit.name) on slot \(index)")
                #expect(Support.faults(in: edit.day).isEmpty, "\(edit.name) on slot \(index)")
            }
        }
        let removed = DayEditing.removeSlot(arriving, slot: Support.slot(1))
        #expect(Support.flags(removed) == [false, false], "slot 1 led the superset, so slot 2 leads what is left")
    }

    @Test("A slot whose numbers were set to the ends of Int outside the model makes no edit trap")
    func slotOutsideTheModel_noEditTraps() throws {
        var day = try Support.day(joined: [false, false])
        for (index, end) in [Int.max, Int.min].enumerated() {
            day.slots[index].sets = end
            day.slots[index].reps = end
            day.slots[index].repsHi = end
        }
        for slot in day.slots {
            for kind in [SlotField.Kind.sets, .reps, .repsHi] {
                let direction: StepDirection = slot.sets == .max ? .upward : .downward
                let field = DayEditing.stepped(kind, direction, of: slot, exercise: Fixtures.bench, units: .lb)
                #expect(field == Support.value(kind, of: slot), "\(kind) stays at the end of Int")
            }
            #expect(DayEditing.setProgression(.double, slot: slot.id, in: day).slots.count == 2)
            #expect(DayEditing.set(.repsHi(5), slot: slot.id, in: day).slots.count == 2)
            #expect(DayEditing.set(.reps(5), slot: slot.id, in: day).slots.count == 2)
        }
        #expect(DayEditing.set(.repsHi(5), slot: Support.slot(1), in: day).slots[0].repsHi == .max)
        #expect(DayEditing.setProgression(.double, slot: Support.slot(1), in: day).slots[0].repsHi == .max)
        #expect(DayEditing.setProgression(.double, slot: Support.slot(2), in: day).slots[1].repsHi == .min + 2)
    }
}
