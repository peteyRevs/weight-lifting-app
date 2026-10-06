import Foundation
@testable import LedgerDomain
import Testing

// A model of a training day written from the plan's table "What each function does, and the rule it
// enforces" (S2) and from "Group-aware move, defined". It keeps every number as a whole number (RPE in half
// points, loads in 10⁻⁷ g) and the day as its superset groups, so that neither the flags nor a decimal are
// ever taken from the code under test.

/// An exercise the model knows: its start load in each unit, in hundredths of the unit.
struct Lift {
    let exercise: Exercise
    let start: [Units: Int]

    init(_ number: Int, _ equipment: Equipment, pounds: Int, kilograms: Int) {
        start = [.lb: pounds, .kg: kilograms]
        exercise = Adversarial.catalogExercise(
            number,
            equipment,
            loads: [
                .lb: EditAdv.weight(fine: EditAdv.fine(hundredths: pounds, .lb)),
                .kg: EditAdv.weight(fine: EditAdv.fine(hundredths: kilograms, .kg))
            ]
        )
    }
}

extension EditAdv {
    /// A barbell lift (180 lb / 80 kg), a dumbbell lift (50 lb / 22.5 kg) and a kettlebell lift
    /// (25 lb / 12 kg): the three default steps of each unit (decisions #9 and #22).
    static let lifts: [Lift] = [
        Lift(801, .barbell, pounds: 18000, kilograms: 8000),
        Lift(802, .dumbbell, pounds: 5000, kilograms: 2250),
        Lift(803, .kettlebell, pounds: 2500, kilograms: 1200)
    ]

    static func lift(_ id: ExerciseID) -> Lift? {
        lifts.first { $0.exercise.id == id }
    }
}

/// A slot in whole numbers.
struct SlotRow {
    var id: SlotID
    var exerciseID: ExerciseID
    var sets: Int
    var reps: Int
    var repsHi: Int
    /// RPE × 2: 10…20.
    var rpeHalves: Int
    var rest: Int
    var progression: Progression
    /// The slot's own start load and step in 10⁻⁷ g; `nil` for the exercise's and the equipment's.
    var load: Int?
    var step: Int?
    var drop: Int
    var misses: Set<Int>

    /// The slot, built through `Slot.init`.
    func slot(joined: Bool) throws -> Slot {
        try Slot(
            id: id,
            exerciseID: exerciseID,
            sets: sets,
            reps: reps,
            repsHi: repsHi,
            rpe: EditAdv.rpe(halves: rpeHalves),
            restSeconds: rest,
            progression: progression,
            startLoad: load.map(EditAdv.weight(fine:)),
            step: step.map(EditAdv.weight(fine:)),
            isSupersetWithPrevious: joined,
            dropSets: drop,
            misses: misses
        )
    }

    /// The first field in which `slot` is not this row (the superset flag aside), or `nil`.
    func difference(from slot: Slot) -> String? {
        let fields = [
            "exercise", "sets", "reps", "top of range", "RPE", "rest", "progression", "start load", "step",
            "drop sets", "misses"
        ]
        let holds = [
            slot.exerciseID == exerciseID, slot.sets == sets, slot.reps == reps, slot.repsHi == repsHi,
            slot.rpe.value == EditAdv.rpe(halves: rpeHalves), slot.rest.seconds == rest,
            slot.progression == progression, slot.startLoad == load.map(EditAdv.weight(fine:)),
            slot.step == step.map(EditAdv.weight(fine:)), slot.dropSets == drop, slot.misses == misses
        ]
        guard let place = holds.firstIndex(of: false) else {
            return nil
        }
        return "slot \(EditAdv.number(id.rawValue)): \(fields[place]); found \(Self.brief(slot)), expected \(text)"
    }

    /// The row's numbers on one line.
    var text: String {
        let weights = [load, step].map { $0.map { "\(EditAdv.weight(fine: $0).grams)" } ?? "nil" }
        return "\(sets)x\(reps)-\(repsHi) rpe \(EditAdv.rpe(halves: rpeHalves)) rest \(rest) \(progression) "
            + "load \(weights[0]) g step \(weights[1]) g drop \(drop) misses \(misses.sorted())"
    }

    /// A slot's numbers on one line, in the same form.
    static func brief(_ slot: Slot) -> String {
        let weights = [slot.startLoad, slot.step].map { $0.map { "\($0.grams)" } ?? "nil" }
        return "\(slot.sets)x\(slot.reps)-\(slot.repsHi) rpe \(slot.rpe.value) rest \(slot.rest.seconds) "
            + "\(slot.progression) load \(weights[0]) g step \(weights[1]) g drop \(slot.dropSets) "
            + "misses \(slot.misses.sorted())"
    }
}

/// A training day as its superset groups and its slots by id.
struct DayModel {
    var groups: [[SlotID]]
    var rows: [SlotID: SlotRow]
    let units: Units

    init(units: Units) {
        groups = []
        rows = [:]
        self.units = units
    }

    var ids: [SlotID] {
        groups.flatMap(\.self)
    }

    /// The day in normal form, every slot built through `Slot.init`.
    func day(id: Int = 4000) throws -> DayTemplate {
        let flags = EditAdv.flags(groups)
        let slots = try zip(ids, flags).compactMap { try rows[$0]?.slot(joined: $1) }
        return DayTemplate(id: EditAdv.dayID(id), name: "Day \(id)", tag: "T\(id)", slots: slots)
    }

    /// The first thing in which `day` is not this model, or `nil`: the order, the flags, then each slot.
    func difference(from day: DayTemplate) -> String? {
        let expected = zip(ids, EditAdv.flags(groups)).map { "\(EditAdv.number($0.rawValue))\($1 ? "+" : "")" }
        let found = EditAdv.brief(day.slots)
        if found != expected.joined(separator: " ") {
            return "slots [\(found)], expected [\(expected.joined(separator: " "))]"
        }
        return day.slots.lazy.compactMap { rows[$0.id]?.difference(from: $0) }.first
    }
}

// MARK: - The rules

extension DayModel {
    /// Appended in order; one whose id the day holds is left out. A slot that arrives joined joins the slot
    /// before it, and the day's first slot is never joined.
    mutating func add(_ new: [SlotRow], joined: [Bool]) {
        for (row, joins) in zip(new, joined) where rows[row.id] == nil {
            rows[row.id] = row
            if joins, !groups.isEmpty {
                groups[groups.count - 1].append(row.id)
            } else {
                groups.append([row.id])
            }
        }
    }

    /// The slot goes; the members left of its group stay together, so the next member leads if it led.
    mutating func remove(_ id: SlotID) {
        rows[id] = nil
        groups = groups.map { $0.filter { $0 != id } }.filter { !$0.isEmpty }
    }

    /// The clamp, then the top of the range kept above reps (rules 2, 3 and 6).
    mutating func set(_ value: FieldValue, _ id: SlotID) {
        guard var row = rows[id] else {
            return
        }
        switch value {
        case let .sets(number):
            row.sets = EditAdv.clamped(number, 1, 12)
        case let .reps(number):
            row.reps = EditAdv.clamped(number, 1, 30)
            row.repsHi = max(row.repsHi, row.reps + 1)
        case let .repsHi(number):
            row.repsHi = max(EditAdv.clamped(number, 2, 40), row.reps + 1)
        case let .rpe(hundredths):
            row.rpeHalves = EditAdv.referenceRPEHalves(hundredths: hundredths)
        case let .rest(seconds):
            row.rest = EditAdv.referenceRest(seconds)
        case let .load(fine):
            row.load = max(0, fine)
        }
        rows[id] = row
    }

    /// A stepper button: the value one step away, then `set`.
    mutating func step(_ kind: SlotField.Kind, _ direction: StepDirection, _ id: SlotID) {
        guard let row = rows[id] else {
            return
        }
        let sign = direction == .upward ? 1 : -1
        switch kind {
        case .sets: set(.sets(row.sets + sign), id)
        case .reps: set(.reps(row.reps + sign), id)
        case .repsHi: set(.repsHi(row.repsHi + sign), id)
        case .rpe: set(.rpe(hundredths: (row.rpeHalves + sign) * 50), id)
        case .rest: set(.rest(row.rest + 15 * sign), id)
        case .startLoad: set(.load(fine: steppedLoad(row, direction)), id)
        }
    }

    /// The next multiple of the slot's step, or of the equipment's in the lifter's unit, from the slot's
    /// start load, or from the exercise's in the lifter's unit.
    func steppedLoad(_ row: SlotRow, _ direction: StepDirection) -> Int {
        guard let lift = EditAdv.lift(row.exerciseID) else {
            return row.load ?? 0
        }
        let load = row.load ?? EditAdv.fine(hundredths: lift.start[units] ?? 0, units)
        let equipmentStep = EditAdv.defaultStepHundredths(lift.exercise.equipment, units)
        return EditAdv.referenceStep(
            load: load,
            step: row.step ?? EditAdv.fine(hundredths: equipmentStep, units),
            direction
        )
    }

    /// Double progression makes the top of the range at least reps + 2; leaving it keeps the top.
    mutating func setProgression(_ progression: Progression, _ id: SlotID) {
        guard var row = rows[id] else {
            return
        }
        row.progression = progression
        if progression == .double {
            row.repsHi = max(row.repsHi, row.reps + 2)
        }
        rows[id] = row
    }

    mutating func setDropSet(_ isOn: Bool, _ id: SlotID) {
        rows[id]?.drop = isOn ? 1 : 0
    }

    /// On: the slot, with the members after it, joins the group before it. Off: the slot and the members
    /// after it leave their group as a new one. The day's first slot is never joined.
    mutating func setSuperset(_ isOn: Bool, _ id: SlotID) {
        guard let groupIndex = groups.firstIndex(where: { $0.contains(id) }),
              let memberIndex = groups[groupIndex].firstIndex(of: id)
        else {
            return
        }
        if isOn, memberIndex == 0, groupIndex > 0 {
            groups[groupIndex - 1] += groups[groupIndex]
            groups.remove(at: groupIndex)
        } else if !isOn, memberIndex > 0 {
            let tail = Array(groups[groupIndex][memberIndex...])
            groups[groupIndex].removeSubrange(memberIndex...)
            groups.insert(tail, at: groupIndex + 1)
        }
    }

    mutating func move(_ id: SlotID, _ direction: MoveDirection) {
        groups = EditAdv.moved(groups, slot: id, direction)
    }
}
