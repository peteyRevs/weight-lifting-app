import Foundation
@testable import LedgerDomain
import Testing

// The Day editor's edits as values, so that one seeded edit goes both through `DayEditing` and through
// `DayModel`, and the generators that draw them.

/// A field with the value it is set to, in whole numbers: RPE in hundredths, the load in 10⁻⁷ g.
enum FieldValue {
    case sets(Int)
    case reps(Int)
    case repsHi(Int)
    case rpe(hundredths: Int)
    case rest(Int)
    case load(fine: Int)

    /// The same edit as `DayEditing.set` takes it.
    var field: SlotField {
        switch self {
        case let .sets(number): .sets(number)
        case let .reps(number): .reps(number)
        case let .repsHi(number): .repsHi(number)
        case let .rpe(hundredths): .rpe(EditAdv.decimal(hundredths: hundredths))
        case let .rest(seconds): .restSeconds(seconds)
        case let .load(fine): .startLoad(EditAdv.weight(fine: fine))
        }
    }

    /// A value from well below the field's range to well above it. An RPE half way between two halves is
    /// moved off the tie, which the plan's "nearest half" does not decide.
    static func random(using generator: inout SeededGenerator) -> FieldValue {
        switch Int.random(in: 0 ..< 6, using: &generator) {
        case 0: return .sets(Int.random(in: -3 ... 16, using: &generator))
        case 1: return .reps(Int.random(in: -3 ... 34, using: &generator))
        case 2: return .repsHi(Int.random(in: -3 ... 44, using: &generator))
        case 3:
            let hundredths = Int.random(in: 300 ... 1200, using: &generator)
            return .rpe(hundredths: EditAdv.isRPETie(hundredths: hundredths) ? hundredths + 1 : hundredths)
        case 4: return .rest(Int.random(in: -20 ... 340, using: &generator))
        default:
            let units = Units.allCases.randomElement(using: &generator) ?? .lb
            return .load(fine: EditAdv.fine(hundredths: Int.random(in: -500 ... 40000, using: &generator), units))
        }
    }
}

/// One edit of the Day editor.
enum DayEdit: CustomStringConvertible {
    case add([SlotRow], joined: [Bool])
    case remove(SlotID)
    case set(FieldValue, SlotID)
    case step(SlotField.Kind, StepDirection, SlotID)
    case progression(Progression, SlotID)
    case dropSet(Bool, SlotID)
    case superset(Bool, SlotID)
    case move(SlotID, MoveDirection)

    var description: String {
        switch self {
        case let .add(rows, joined): "add(\(rows.map { EditAdv.number($0.id.rawValue) }), joined \(joined))"
        case let .remove(id): "remove(\(EditAdv.number(id.rawValue)))"
        case let .set(value, id): "set(\(value), \(EditAdv.number(id.rawValue)))"
        case let .step(kind, direction, id): "step(\(kind), \(direction), \(EditAdv.number(id.rawValue)))"
        case let .progression(progression, id): "progression(\(progression), \(EditAdv.number(id.rawValue)))"
        case let .dropSet(isOn, id): "dropSet(\(isOn), \(EditAdv.number(id.rawValue)))"
        case let .superset(isOn, id): "superset(\(isOn), \(EditAdv.number(id.rawValue)))"
        case let .move(id, direction): "move(\(EditAdv.number(id.rawValue)), \(direction))"
        }
    }

    /// The edit through the code under test. A stepper button sends `set(stepped(…))`, as the plan says,
    /// with the slot's own exercise, or with `exercise` when one is given.
    func applied(to day: DayTemplate, units: Units, exercise: Exercise? = nil) throws -> DayTemplate {
        switch self {
        case let .add(rows, joined): try DayEditing.addSlots(day, zip(rows, joined).map { try $0.slot(joined: $1) })
        case let .remove(id): DayEditing.removeSlot(day, slot: id)
        case let .set(value, id): DayEditing.set(value.field, slot: id, in: day)
        case let .step(kind, direction, id):
            Self.stepping(day, StepPress(kind: kind, direction: direction, units: units, exercise: exercise), slot: id)
        case let .progression(progression, id): DayEditing.setProgression(progression, slot: id, in: day)
        case let .dropSet(isOn, id): DayEditing.setDropSet(isOn, slot: id, in: day)
        case let .superset(isOn, id): DayEditing.setSuperset(isOn, slot: id, in: day)
        case let .move(id, direction): DayEditing.move(day, slot: id, direction)
        }
    }

    /// A stepper button: the field, the side, the lifter's unit, and the exercise when it is not the slot's.
    struct StepPress {
        let kind: SlotField.Kind
        let direction: StepDirection
        let units: Units
        let exercise: Exercise?
    }

    static func stepping(_ day: DayTemplate, _ press: StepPress, slot id: SlotID) -> DayTemplate {
        guard let slot = day.slots.first(where: { $0.id == id }),
              let exercise = press.exercise ?? EditAdv.lift(slot.exerciseID)?.exercise
        else {
            return day
        }
        let field = DayEditing.stepped(press.kind, press.direction, of: slot, exercise: exercise, units: press.units)
        return DayEditing.set(field, slot: id, in: day)
    }

    /// The same edit on the model.
    func apply(to model: inout DayModel) {
        switch self {
        case let .add(rows, joined): model.add(rows, joined: joined)
        case let .remove(id): model.remove(id)
        case let .set(value, id): model.set(value, id)
        case let .step(kind, direction, id): model.step(kind, direction, id)
        case let .progression(progression, id): model.setProgression(progression, id)
        case let .dropSet(isOn, id): model.setDropSet(isOn, id)
        case let .superset(isOn, id): model.setSuperset(isOn, id)
        case let .move(id, direction): model.move(id, direction)
        }
    }
}

// MARK: - Generators

extension SlotRow {
    /// A slot `Slot.init` accepts, anywhere in its ranges, with or without a load and a step of its own.
    static func random(id: Int, using generator: inout SeededGenerator) -> SlotRow {
        let reps = Int.random(in: 1 ... 30, using: &generator)
        let units = Units.allCases.randomElement(using: &generator) ?? .lb
        let load = EditAdv.fine(hundredths: 25 * Int.random(in: 0 ... 1600, using: &generator), units)
        let step = EditAdv.fine(hundredths: [125, 200, 250, 500].randomElement(using: &generator) ?? 250, units)
        return SlotRow(
            id: EditAdv.slotID(id),
            exerciseID: (EditAdv.lifts.randomElement(using: &generator) ?? EditAdv.lifts[0]).exercise.id,
            sets: Int.random(in: 1 ... 12, using: &generator),
            reps: reps,
            repsHi: Int.random(in: reps + 1 ... 40, using: &generator),
            rpeHalves: Int.random(in: 10 ... 20, using: &generator),
            rest: 15 * Int.random(in: 2 ... 20, using: &generator),
            progression: Progression.allCases.randomElement(using: &generator) ?? .linear,
            load: Bool.random(using: &generator) ? load : nil,
            step: Bool.random(using: &generator) ? step : nil,
            drop: Int.random(in: 0 ... 1, using: &generator),
            misses: Set((0 ..< 8).filter { _ in Int.random(in: 0 ..< 4, using: &generator) == 0 })
        )
    }
}

extension DayEdit {
    /// A seeded edit of a day that holds `ids`. One time in ten the slot is one the day does not hold.
    /// `step` gives new slots ids no other slot has had.
    static func random(ids: [SlotID], step: Int, using generator: inout SeededGenerator) -> DayEdit {
        let known = ids.randomElement(using: &generator) ?? EditAdv.slotID(999)
        let slot = Int.random(in: 0 ..< 10, using: &generator) == 0 ? EditAdv.slotID(999) : known
        switch Int.random(in: 0 ..< 12, using: &generator) {
        case 0: return added(ids: ids, step: step, using: &generator)
        case 1: return .remove(slot)
        case 2, 3: return .set(.random(using: &generator), slot)
        case 4, 5: return stepped(slot, using: &generator)
        case 6: return .progression(Progression.allCases.randomElement(using: &generator) ?? .linear, slot)
        case 7: return .dropSet(Bool.random(using: &generator), slot)
        case 8, 9: return .superset(Bool.random(using: &generator), slot)
        default: return .move(slot, Bool.random(using: &generator) ? .upward : .downward)
        }
    }

    static func stepped(_ slot: SlotID, using generator: inout SeededGenerator) -> DayEdit {
        let kind = SlotField.Kind.allCases.randomElement(using: &generator) ?? .sets
        return .step(kind, Bool.random(using: &generator) ? .upward : .downward, slot)
    }

    /// One to three slots from the library, any of them arriving joined; one time in four one of them
    /// carries the id of a slot the day already holds, with another exercise and other misses.
    static func added(ids: [SlotID], step: Int, using generator: inout SeededGenerator) -> DayEdit {
        var rows = (0 ..< Int.random(in: 1 ... 3, using: &generator)).map { offset in
            SlotRow.random(id: 8000 + 4 * step + offset, using: &generator)
        }
        if let taken = ids.randomElement(using: &generator), Int.random(in: 0 ..< 4, using: &generator) == 0 {
            rows[0].id = taken
        }
        return .add(rows, joined: rows.map { _ in Int.random(in: 0 ..< 3, using: &generator) == 0 })
    }
}
