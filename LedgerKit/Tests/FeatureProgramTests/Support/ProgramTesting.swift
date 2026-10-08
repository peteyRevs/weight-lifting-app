@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Tags live in the test target, as in every other one (F02 notes: tags in LedgerTestSupport would pull
/// swift-testing into the features, which link it).
extension Tag {
    /// Every FeatureProgram suite (layer tag).
    @Tag static var feature: Self
    /// Seeded property-style tests; the case count comes from `LEDGER_PROPERTY_SEED_COUNT`.
    @Tag static var property: Self
}

/// Deterministic SplitMix64 generator for property tests (testing-strategy §3 rule 5).
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// One property-test case. A failing case names its seed, which is then added as a fixed regression test.
nonisolated struct PropertySeed: Sendable, CustomStringConvertible {
    let value: UInt64

    var description: String {
        "seed \(value)"
    }

    var generator: SeededGenerator {
        SeededGenerator(seed: value)
    }

    /// `LEDGER_PROPERTY_SEED_COUNT` seeds (PR lane 200, nightly 2,000); 200 when unset or invalid.
    static let all: [PropertySeed] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init)
        let count = max(1, configured ?? 200)
        return (0 ..< count).map { PropertySeed(value: UInt64($0) &* 7919 &+ 17) }
    }()
}

/// The brief's worked examples as inputs: the spec's seed program (`Fixtures.seedProgram()`) with the bundled
/// catalog's exercises, in en_US, with a Monday week start and week 1 selected.
nonisolated enum ProgramFixtures {
    /// The four days of the seed program, by their place in `Program.days`.
    enum DayIndex {
        static let upperA = 0
        static let lowerA = 1
        static let upperB = 2
        static let lowerB = 3
    }

    /// The bundled catalog by id, decoded once.
    private static let catalog = Result {
        try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
    }

    /// The bundled catalog by id: what the store hands the presentation.
    static func exercises() throws -> [ExerciseID: Exercise] {
        try catalog.get()
    }

    /// An input for `program` with the catalog's exercises, in UTC and en_US, with a Monday week start, no
    /// logged week and no notice. Tests change the fields their case is about.
    static func input(_ program: Program, selectedWeek: Int = 0) throws -> ProgramBuilderInput {
        try ProgramBuilderInput(
            program: program,
            exercises: exercises(),
            settings: Fixtures.settingsLb,
            selectedWeek: selectedWeek,
            calendar: Fixtures.calendar,
            locale: Fixtures.locale
        )
    }

    /// The input of the brief's criterion 1: the seed program with week 1 selected.
    static func seedInput(selectedWeek: Int = 0) throws -> ProgramBuilderInput {
        try input(Fixtures.seedProgram(), selectedWeek: selectedWeek)
    }

    /// A program of `weekCount` weeks and of `days`, nothing scheduled.
    static func program(weekCount: Int, days: [DayTemplate]) throws -> Program {
        try Program(
            id: Fixtures.programID,
            name: "Block",
            startDate: #require(CivilDate(year: 2026, month: 8, day: 17)),
            weeks: (0 ..< weekCount).map { Week(id: WeekID(Fixtures.uuid(200 + $0)), index: $0) },
            days: days
        )
    }

    /// Day `number` named and tagged by it, with `slotCount` slots of 3 × 8 on the bench press.
    static func day(_ number: Int, slotCount: Int = 0) throws -> DayTemplate {
        let slots = try (0 ..< slotCount).map { index in
            try Slot(
                id: SlotID(Fixtures.uuid(number * 100 + index)),
                exerciseID: Fixtures.CatalogID.benchPress,
                sets: 3,
                reps: 8,
                repsHi: 10,
                rpe: 8,
                restSeconds: 90,
                progression: .linear
            )
        }
        return DayTemplate(
            id: DayTemplateID(Fixtures.uuid(number)),
            name: "Day \(number)",
            tag: "D\(number)",
            slots: slots
        )
    }
}

/// What a store holds for the builder, with the actions applied as the model's documentation says a store
/// applies them and nothing more: the tests tap a control of the model and read the next model.
nonisolated struct BuilderScreen {
    var input: ProgramBuilderInput
    /// Every route emitted, in order.
    var routes: [ProgramRoute] = []
    /// The ids a store draws from its `uuid` dependency: 900, 901, …
    private var nextID = 900

    init(_ input: ProgramBuilderInput) {
        self.input = input
    }

    var model: ProgramBuilderModel {
        ProgramPresentation.make(input)
    }

    private mutating func drawID() -> UUID {
        defer { nextID += 1 }
        return Fixtures.uuid(nextID)
    }

    /// Applies `action`; a nil action is a disabled control, which a test must not tap.
    mutating func tap(_ action: ProgramBuilderAction?) throws {
        switch try #require(action, "the control is disabled") {
        case let .selectWeek(place):
            input.selectedWeek = place
            input.notice = nil
        case let .edit(edit, notice):
            input.program = try edit.applied(to: input.program)
            input.notice = notice
        case let .addWeek(selecting):
            input.program = try ProgramBuilderEdit.addWeek(WeekID(drawID())).applied(to: input.program)
            input.selectedWeek = selecting
            input.notice = nil
        case let .addDay(name, weekIndex):
            let id = DayTemplateID(drawID())
            input.program = try ProgramBuilderEdit.addDay(id, name: name).applied(to: input.program)
            input.notice = nil
            routes.append(.day(id, weekIndex: weekIndex))
        case let .notice(notice):
            input.notice = notice
        case let .route(route):
            routes.append(route)
        }
    }

    /// Taps the cell of `weekday` in the selected week's strip.
    mutating func tapCell(_ weekday: Weekday) throws {
        try tap(model.week.cells.first { $0.weekday == weekday }?.action)
    }
}

// MARK: - Small views of a model, so that a failure prints a line and not a model

nonisolated extension ProgramBuilderModel.SelectedWeek {
    /// "M UA · T REST · W LA · T REST · F UB · S LB · S REST": the strip as the brief writes it.
    var strip: String {
        cells.map { "\($0.letter) \($0.label)" }.joined(separator: " · ")
    }

    /// "Monday, Upper A · Tuesday, Rest · …": the strip as VoiceOver reads it.
    var spokenStrip: String {
        cells.map { "\($0.spokenLabel), \($0.spokenValue)" }.joined(separator: " · ")
    }

    func cell(_ weekday: Weekday) -> ProgramBuilderModel.Cell? {
        cells.first { $0.weekday == weekday }
    }
}

nonisolated extension ProgramBuilderModel.Block {
    /// "W1 4 DAYS · W2 4 DAYS · … · W8 DELOAD".
    var chipLine: String {
        chips.map { "\($0.title) \($0.subtitle)" }.joined(separator: " · ")
    }

    /// The places of the chips marked selected.
    var selectedPlaces: [Int] {
        chips.indices.filter { chips[$0].isSelected }
    }
}
