@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The exercise library's worked examples as inputs: the bundled catalog, no filter, no pick, en_US.
nonisolated enum ExercisePickerFixtures {
    /// The bundled catalog, in the order the file has it.
    static func catalog() throws -> [Exercise] {
        try ExerciseCatalog.seed()
    }

    /// An input over the bundled catalog; tests change the fields their case is about.
    static func input(
        query: String = "",
        muscle: ExerciseSearch.MuscleFilter? = nil,
        equipment: Equipment? = nil,
        picks: [ExerciseID] = [],
        dayExercises: Set<ExerciseID> = []
    ) throws -> ExercisePickerInput {
        try ExercisePickerInput(
            exercises: catalog(),
            dayExercises: dayExercises,
            query: query,
            muscle: muscle,
            equipment: equipment,
            picks: picks,
            locale: Fixtures.locale
        )
    }

    /// The id of the catalog's exercise of this name.
    static func id(_ name: String) throws -> ExerciseID {
        try DayEditorFixtures.exercise(named: name).id
    }

    /// An exercise the lifter made: a machine row for the back, named so that "row" finds it.
    static let customRow = Exercise(
        id: ExerciseID(Fixtures.uuid(7001)),
        name: "Garage T-Bar Row",
        shortName: "T-BAR",
        equipment: .machine,
        primaryMuscle: .back,
        pattern: .horizontalPull,
        defaultStartLoad: [.lb: .pounds(90)],
        isCustom: true
    )
}

/// What a store holds for the exercise library, with the actions applied as `ExercisePickerAction`'s
/// documentation says a store applies them and nothing more: the tests tap a control of the model and read
/// the next model.
nonisolated struct PickerScreen {
    var input: ExercisePickerInput
    var isOpen = true
    /// What each "Add" handed over, in order.
    var added: [[ExerciseID]] = []

    init(_ input: ExercisePickerInput) {
        self.input = input
    }

    var model: ExercisePickerModel {
        ExercisePickerPresentation.make(input)
    }

    /// Applies `action`; a nil action is a control the model does not offer, which a test must not tap.
    mutating func tap(_ action: ExercisePickerAction?) throws {
        switch try #require(action, "the control is not offered") {
        case let .setQuery(text):
            input.query = text
        case let .setMuscle(muscle):
            input.muscle = muscle
        case let .setEquipment(equipment):
            input.equipment = equipment
        case let .setPicked(isPicked, exercise):
            if !isPicked {
                input.picks.removeAll { $0 == exercise }
            } else if !input.picks.contains(exercise) {
                input.picks.append(exercise)
            }
        case .clearFilters:
            input.query = ""
            input.muscle = nil
            input.equipment = nil
        case let .add(exercises):
            added.append(exercises)
            close()
        case .cancel:
            close()
        }
    }

    /// The sheet closes: the query and the picks are emptied, the two chips stay.
    private mutating func close() {
        input.query = ""
        input.picks = []
        isOpen = false
    }

    /// Taps the row of the exercise of this name; fails when the list does not show it.
    mutating func tapRow(_ name: String) throws {
        try tap(model.row(name).action)
    }

    /// Taps the chip of this title in the muscle row or in the equipment row.
    mutating func tapChip(_ title: String, in row: KeyPath<ExercisePickerModel, ExercisePickerModel.ChipRow>) throws {
        let chips = model[keyPath: row].chips
        try tap(#require(chips.first { $0.title == title }, "no chip \(title)").action)
    }
}

// MARK: - Small views of a model, so that a failure prints a line and not a model

nonisolated extension ExercisePickerModel {
    /// The rows; none when nothing matches.
    var rows: [Row] {
        guard case let .rows(rows) = content else {
            return []
        }
        return rows
    }

    /// The empty state; nil when the list has a row.
    var empty: Empty? {
        guard case let .nothingMatches(empty) = content else {
            return nil
        }
        return empty
    }

    /// The names of the exercises listed, in order.
    var names: [String] {
        rows.map(\.name)
    }

    func row(_ name: String) throws -> Row {
        try #require(rows.first { $0.name == name }, "no row \(name) among \(rows.count) rows")
    }

    /// "1 Back Squat · 2 Leg Press": the picked rows that are listed, each by its place in the order "Add"
    /// adds them (the rows carry no place of their own since S14, Pete's question 4).
    var pickLine: String {
        guard case let .add(ids)? = foot.action else {
            return ""
        }
        return ids.enumerated().compactMap { place, id in
            rows.first { $0.id == id && $0.isPicked }.map { "\(place + 1) \($0.name)" }
        }.joined(separator: " · ")
    }
}

nonisolated extension ExercisePickerModel.ChipRow {
    /// "All, Chest, Back, Shoulders, Legs, Arms".
    var titles: String {
        chips.map(\.title).joined(separator: ", ")
    }

    /// The titles of the chips marked selected.
    var selected: [String] {
        chips.filter(\.isSelected).map(\.title)
    }
}

/// The row's grey line in its parts, for the tests that read one: the model has the line alone since S14
/// (Pete's question 4, A: the mark is drawn as the end of the line).
nonisolated extension ExercisePickerModel.Row {
    private static let mark = " · already in this day"

    /// Whether the line ends with "already in this day".
    var isMarkedInDay: Bool {
        line.hasSuffix(Self.mark)
    }

    /// "Machine · Back": the line without the mark.
    var detail: String {
        isMarkedInDay ? String(line.dropLast(Self.mark.count)) : line
    }
}
