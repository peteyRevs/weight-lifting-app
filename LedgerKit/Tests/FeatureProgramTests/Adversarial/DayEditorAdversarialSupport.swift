@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport

/// F11 S6 adversarial round 1: what the tester's Day editor suites share. Inputs are filled as the store will
/// fill them, an action is applied as its documentation tells the store to apply it, with the Domain call
/// spelled here and not taken from the feature, and days are drawn from seeds.
nonisolated enum AdvDay {
    static let english = Locale(identifier: "en_US")

    static func input(
        _ program: Program,
        day: DayTemplateID,
        exercises: [ExerciseID: Exercise],
        units: Units = .lb,
        week: Int = 0,
        open: SlotID? = nil
    ) -> DayEditorInput {
        var settings = Settings.default
        settings.units = units
        return DayEditorInput(
            program: program,
            day: day,
            exercises: exercises,
            settings: settings,
            weekIndex: week,
            openSlot: open,
            locale: english
        )
    }

    static func catalog() throws -> [ExerciseID: Exercise] {
        try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
    }

    /// The spec's seed program on its day `place` (0 Upper A, 1 Lower A, 2 Upper B, 3 Lower B), with the slot
    /// at `open` open.
    static func seed(day place: Int, units: Units = .lb, week: Int = 0, open: Int? = nil) throws -> DayEditorInput {
        let program = try Fixtures.seedProgram()
        let day = program.days[place]
        return try input(
            program,
            day: day.id,
            exercises: catalog(),
            units: units,
            week: week,
            open: open.map { day.slots[$0].id }
        )
    }

    static func content(_ input: DayEditorInput) -> DayEditorModel.Content? {
        if case let .editing(content) = DayEditorPresentation.make(input) {
            return content
        }
        return nil
    }

    static func rows(_ input: DayEditorInput) -> [DayEditorModel.Row] {
        content(input)?.groups.flatMap(\.rows) ?? []
    }

    /// The open slot's panel, or nil when the model has none.
    static func panel(_ input: DayEditorInput) -> SlotEditorModel? {
        rows(input).first { $0.id == input.openSlot }?.panel
    }

    static func field(_ kind: SlotField.Kind, _ input: DayEditorInput) -> SlotEditorModel.Field? {
        panel(input)?.details?.fields.first { $0.kind == kind }
    }

    static func day(_ input: DayEditorInput) -> DayTemplate? {
        input.program.days.first { $0.id == input.day }
    }

    static func slot(_ input: DayEditorInput) -> Slot? {
        day(input)?.slots.first { $0.id == input.openSlot }
    }
}

// MARK: - The store's part

nonisolated extension AdvDay {
    struct Step {
        var input: DayEditorInput
        var edits = 0
        var route: ProgramRoute?
        var opensLibrary = false
    }

    /// One slot edit as one `DayEditing` call, spelled by the tester.
    static func edited(_ day: DayTemplate, _ edit: SlotEdit) -> DayTemplate {
        switch edit {
        case let .set(field, slot): DayEditing.set(field, slot: slot, in: day)
        case let .setProgression(progression, slot): DayEditing.setProgression(progression, slot: slot, in: day)
        case let .setDropSet(isOn, slot): DayEditing.setDropSet(isOn, slot: slot, in: day)
        case let .setSuperset(isOn, slot): DayEditing.setSuperset(isOn, slot: slot, in: day)
        case let .move(direction, slot): DayEditing.move(day, slot: slot, direction)
        case let .remove(slot): DayEditing.removeSlot(day, slot: slot)
        }
    }

    /// One edit as one `ProgramEditing` call, spelled by the tester.
    static func edited(_ program: Program, _ edit: DayEditorEdit) -> Program {
        switch edit {
        case let .renameDay(name, day): ProgramEditing.renameDay(program, day: day, to: name)
        case let .deleteDay(day): ProgramEditing.deleteDay(program, day: day)
        case let .slot(slotEdit, day): ProgramEditing.updateDay(program, day: day) { edited($0, slotEdit) }
        }
    }

    /// `input` after `action`, as the actions' documentation gives the store's part.
    static func apply(_ action: DayEditorAction, to input: DayEditorInput) -> Step {
        var step = Step(input: input)
        switch action {
        case let .open(slot):
            step.input.openSlot = slot
        case let .edit(edit, closesPanel):
            step.input.program = edited(input.program, edit)
            step.edits = 1
            if closesPanel {
                step.input.openSlot = nil
            }
        case .openLibrary:
            step.opensLibrary = true
        case let .route(route):
            step.route = route
        }
        return step
    }

    /// The edit an action carries, or nil.
    static func edit(of action: DayEditorAction?) -> DayEditorEdit? {
        if case let .edit(edit, _) = action {
            return edit
        }
        return nil
    }

    /// The slot edit an action carries, or nil.
    static func slotEdit(of action: DayEditorAction?) -> SlotEdit? {
        if case let .slot(slotEdit, _) = edit(of: action) {
            return slotEdit
        }
        return nil
    }

    /// Every action the model holds, with a name for a message.
    static func actions(_ input: DayEditorInput) -> [(name: String, action: DayEditorAction)] {
        guard let content = content(input) else {
            return []
        }
        var found: [(String, DayEditorAction)] = [
            ("back", content.header.back.action), ("done", content.header.done.action),
            ("add", content.addExercise.action), ("delete", content.deleteDay.confirmation.confirm.action)
        ]
        for row in content.groups.flatMap(\.rows) {
            found.append(("row \(row.index)", row.action))
            guard let panel = row.panel else {
                continue
            }
            for field in panel.details?.fields ?? [] {
                found.append(("\(field.label) −", field.decrement))
                found.append(("\(field.label) +", field.increment))
            }
            for chip in panel.details?.progression.chips ?? [] {
                if let action = chip.action {
                    found.append((chip.title, action))
                }
            }
            if let dropSet = panel.details?.dropSet {
                found.append(("drop set", dropSet.action))
            }
            found += panel.supersetActions.map { ($0.title, $0.action) }
            found += [panel.moveUp, panel.moveDown, panel.remove].compactMap(\.self).map { ($0.title, $0.action) }
        }
        return found
    }
}

// MARK: - Days from seeds

nonisolated extension AdvDay {
    static let equipment: [Equipment] = [.barbell, .dumbbell, .cable, .machine, .bodyweight, .kettlebell, .band]

    /// Exercise `number` (0 … 13): every kind of equipment twice; a start load in pounds only, in kilograms
    /// only, in both, or none.
    static func exercise(_ number: Int) -> Exercise {
        let loads: [[Units: Weight]] = [
            [.lb: .pounds(45), .kg: .kilograms(20)], [.lb: .pounds(135)], [.kg: .kilograms(42.5)], [:]
        ]
        return Exercise(
            id: ExerciseID(Fixtures.uuid(41000 + number)),
            name: "Lift \(number)",
            shortName: "L\(number)",
            equipment: equipment[number % equipment.count],
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: loads[number % loads.count]
        )
    }

    static func stored() -> [ExerciseID: Exercise] {
        Dictionary(uniqueKeysWithValues: (0 ..< 14).map { exercise($0) }.map { ($0.id, $0) })
    }

    /// A slot of any shape `Slot.init` accepts. `missing` gives it an exercise that is not stored.
    static func slot(_ number: Int, joined: Bool, missing: Bool = false, using rng: inout SplitMix64) throws -> Slot {
        let reps = Int.random(in: 1 ... 30, using: &rng)
        let loads: [Weight?] = [nil, .pounds(180), .kilograms(60), .zero, .pounds(52.5), .kilograms(101.25)]
        let steps: [Weight?] = [nil, nil, .pounds(5), .pounds(2.5), .kilograms(2.5), .kilograms(1.25), .kilograms(2)]
        let exercise = missing ? 900 : Int.random(in: 0 ..< 14, using: &rng)
        return try Slot(
            id: SlotID(Fixtures.uuid(51000 + number)),
            exerciseID: ExerciseID(Fixtures.uuid(41000 + exercise)),
            sets: Int.random(in: 1 ... 12, using: &rng),
            reps: reps,
            repsHi: Int.random(in: (reps + 1) ... max(reps + 1, min(40, reps + 4)), using: &rng),
            rpe: 5 + Decimal(Int.random(in: 0 ... 10, using: &rng)) / 2,
            restSeconds: 30 + 15 * Int.random(in: 0 ... 18, using: &rng),
            progression: Progression.allCases[Int.random(in: 0 ..< 3, using: &rng)],
            startLoad: loads[Int.random(in: 0 ..< loads.count, using: &rng)],
            step: steps[Int.random(in: 0 ..< steps.count, using: &rng)],
            isSupersetWithPrevious: joined,
            dropSets: Int.random(in: 0 ... 3, using: &rng) == 0 ? 1 : 0
        )
    }

    /// A program of 2 to 9 weeks (any deload flags) and three days, the second one drawn from `seed`: 0 to 7
    /// slots, supersets and drop sets among them, and when `missing`, one slot in six of an exercise that is
    /// not stored. No slot has a miss.
    static func random(seed: UInt64, missing: Bool = false) throws -> (program: Program, day: DayTemplateID) {
        var rng = SplitMix64(seed: seed)
        var slots: [Slot] = []
        for index in 0 ..< Int.random(in: 0 ... 7, using: &rng) {
            let joined = index > 0 && Int.random(in: 0 ... 2, using: &rng) == 0
            let isMissing = missing && Int.random(in: 0 ... 5, using: &rng) == 0
            try slots.append(slot(index, joined: joined, missing: isMissing, using: &rng))
        }
        let days = [
            AdvProgram.day(0, slots: []), AdvProgram.day(1, name: "Day \(seed)", slots: slots), AdvProgram.day(2)
        ]
        let weekCount = Int.random(in: 2 ... 9, using: &rng)
        let deloads = Set((0 ..< weekCount).filter { _ in Int.random(in: 0 ... 3, using: &rng) == 0 })
        let trained = (0 ..< weekCount).map { _ in Bool.random(using: &rng) }
        let program = try AdvProgram.program(weeks: weekCount, days: days, deloads: deloads) { week, weekday in
            trained[week] && weekday == .tuesday ? 1 : nil
        }
        return (program, days[1].id)
    }
}
