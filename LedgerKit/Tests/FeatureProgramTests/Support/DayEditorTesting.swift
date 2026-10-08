@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The Day editor's worked examples as inputs: a day of the spec's seed program with the bundled catalog's
/// exercises, in pounds and en_US, week 1 shown and no exercise open.
nonisolated enum DayEditorFixtures {
    typealias DayIndex = ProgramFixtures.DayIndex

    /// An input for the day at `dayIndex` of `program`.
    static func input(_ program: Program, dayIndex: Int = 0, weekIndex: Int = 0) throws -> DayEditorInput {
        try DayEditorInput(
            program: program,
            day: program.days[dayIndex].id,
            exercises: ProgramFixtures.exercises(),
            settings: Fixtures.settingsLb,
            weekIndex: weekIndex,
            locale: Fixtures.locale
        )
    }

    /// A day of the seed program: Upper A unless another is asked for.
    static func seedInput(dayIndex: Int = DayIndex.upperA, weekIndex: Int = 0) throws -> DayEditorInput {
        try input(Fixtures.seedProgram(), dayIndex: dayIndex, weekIndex: weekIndex)
    }

    /// The seed program's eight weeks around one day of `slots`, scheduled nowhere.
    static func input(slots: [Slot], units: Units = .lb) throws -> DayEditorInput {
        let day = DayTemplate(id: DayTemplateID(Fixtures.uuid(500)), name: "Arms — Pump", tag: "AR", slots: slots)
        var program = try Fixtures.seedProgram()
        program.days = [day]
        for place in program.weeks.indices {
            program.weeks[place].schedule = [:]
        }
        var input = try input(program)
        input.settings.units = units
        return input
    }

    /// Slot `number` on a catalog exercise: 3 × 8, top 10, RPE 8, 90 s, linear unless said otherwise.
    static func slot(
        _ number: Int,
        _ exercise: ExerciseID = Fixtures.CatalogID.benchPress,
        reps: Int = 8,
        repsHi: Int = 10,
        progression: Progression = .linear,
        startLoad: Weight? = nil,
        superset: Bool = false,
        misses: Set<Int> = []
    ) throws -> Slot {
        try Slot(
            id: slotID(number),
            exerciseID: exercise,
            sets: 3,
            reps: reps,
            repsHi: repsHi,
            rpe: 8,
            restSeconds: 90,
            progression: progression,
            startLoad: startLoad,
            isSupersetWithPrevious: superset,
            misses: misses
        )
    }

    static func slotID(_ number: Int) -> SlotID {
        SlotID(Fixtures.uuid(600 + number))
    }

    /// The brief's criterion 10: five exercises, the third and fourth a superset, read "1, 2, 3A, 3B, 4".
    static func fiveWithASuperset() throws -> [Slot] {
        let catalog = Fixtures.CatalogID.self
        return try [
            slot(1, catalog.benchPress), slot(2, catalog.inclineDBPress), slot(3, catalog.latPulldown),
            slot(4, catalog.cableLateralRaise, superset: true), slot(5, catalog.barbellCurl)
        ]
    }

    /// The catalog's exercise of this name.
    static func exercise(named name: String) throws -> Exercise {
        try #require(ProgramFixtures.exercises().values.first { $0.name == name }, "no exercise named \(name)")
    }
}

/// What a store holds for the Day editor, with the actions applied as the model's documentation says a store
/// applies them and nothing more: the tests tap a control of the model and read the next model.
nonisolated struct DayScreen {
    var input: DayEditorInput
    /// Every route emitted, in order.
    var routes: [ProgramRoute] = []
    /// How often the exercise library was asked for.
    var libraryOpenings = 0

    init(_ input: DayEditorInput) {
        self.input = input
    }

    var model: DayEditorModel {
        DayEditorPresentation.make(input)
    }

    /// The day as the program on screen holds it.
    var day: DayTemplate? {
        input.program.days.first { $0.id == input.day }
    }

    /// The editor's content; fails when the day is gone.
    func content() throws -> DayEditorModel.Content {
        try model.content()
    }

    /// The panel of the open exercise; fails when none is open.
    func panel() throws -> SlotEditorModel {
        try #require(content().rows.first(where: \.isOpen)?.panel, "no exercise is open")
    }

    /// The open panel's parts that need the exercise; fails when it is not stored.
    func details() throws -> SlotEditorModel.Details {
        try #require(panel().details, "the open exercise is not stored")
    }

    /// Applies `action`; a nil action is a control the model does not offer, which a test must not tap.
    mutating func tap(_ action: DayEditorAction?) throws {
        switch try #require(action, "the control is not offered") {
        case let .open(slot):
            input.openSlot = slot
        case let .edit(edit, closesPanel):
            input.program = edit.applied(to: input.program)
            if closesPanel {
                input.openSlot = nil
            }
        case .openLibrary:
            libraryOpenings += 1
        case let .route(route):
            routes.append(route)
        }
    }

    /// Opens the row at `index` ("3A") when it is closed.
    mutating func open(_ index: String) throws {
        let row = try content().row(index)
        if !row.isOpen {
            try tap(row.action)
        }
    }

    /// Taps "−" or "+" of the open exercise's field with this label, `times` times.
    mutating func step(_ label: String, _ direction: StepDirection, times: Int = 1) throws {
        for _ in 0 ..< times {
            let field = try details().field(label)
            try tap(direction == .upward ? field.increment : field.decrement)
        }
    }
}

// MARK: - Small views of a model, so that a failure prints a line and not a model

nonisolated extension DayEditorModel {
    func content() throws -> Content {
        guard case let .editing(content) = self else {
            throw DayIsGone()
        }
        return content
    }

    struct DayIsGone: Error {}

    /// Whether the model says the day is gone: a flag to expect, so that a failure prints no model.
    var isGone: Bool {
        self == .dayIsGone
    }
}

nonisolated extension DayEditorModel.Content {
    /// Every row, in the day's order.
    var rows: [DayEditorModel.Row] {
        groups.flatMap(\.rows)
    }

    /// "1 Barbell Bench Press · 2 Incline DB Press · 3A Lat Pulldown · …": the day's order as it is drawn.
    var order: String {
        rows.map { "\($0.index) \($0.name)" }.joined(separator: " · ")
    }

    /// "1 · 2 · 3A · 3B · 4".
    var indices: String {
        rows.map(\.index).joined(separator: " · ")
    }

    func row(_ index: String) throws -> DayEditorModel.Row {
        try #require(rows.first { $0.index == index }, "no row \(index) among \(indices)")
    }

    /// The superset headers' notes, in order.
    var supersetNotes: [String] {
        groups.compactMap(\.header?.note)
    }
}

nonisolated extension SlotEditorModel.Details {
    /// "SETS 3 · REPS 8 · START LOAD 180 lb · TARGET RPE 8 · REST 1:30".
    var fieldLine: String {
        fields.map { "\($0.label) \($0.value)" }.joined(separator: " · ")
    }

    func field(_ label: String) throws -> SlotEditorModel.Field {
        try #require(fields.first { $0.label == label }, "no field \(label) in \(fieldLine)")
    }

    func value(_ label: String) throws -> String {
        try field(label).value
    }

    /// The titles of the progression chips marked selected.
    var selectedProgressions: [String] {
        progression.chips.filter(\.isSelected).map(\.title)
    }
}

nonisolated extension SlotEditorModel {
    /// "Break out · Superset with next · Move up · Move down · Remove": the slot's actions that are offered.
    var actionLine: String {
        (supersetActions + [moveUp, moveDown, remove].compactMap(\.self)).map(\.title).joined(separator: " · ")
    }

    func supersetAction(_ title: String) -> DayEditorAction? {
        supersetActions.first { $0.title == title }?.action
    }
}

nonisolated extension SlotEdit {
    /// The slot the edit names.
    var slot: SlotID {
        switch self {
        case let .set(_, slot), let .setProgression(_, slot), let .setDropSet(_, slot), let .setSuperset(_, slot),
             let .move(_, slot), let .remove(slot):
            slot
        }
    }
}
