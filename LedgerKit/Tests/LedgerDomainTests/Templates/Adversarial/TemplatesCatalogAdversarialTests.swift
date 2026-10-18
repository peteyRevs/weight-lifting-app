import Foundation
@testable import LedgerDomain
import Testing

/// F08 S1, G2 round 1: the catalog the generator is handed (amendment 4). Names match exactly, among catalog
/// exercises only; a missing one is `ProgramTemplateError.unknownExercise`, naming it.
@Suite("Adversarial F08 S1 · the catalog a block is written from", .tags(.domain))
struct TemplatesCatalogAdversarialTests {
    typealias Brief = BriefTemplates

    /// A split and one of the 22 template exercise names.
    struct Removal: Sendable, CustomStringConvertible {
        var days: DaysPerWeek
        var exercise: String

        var description: String {
            "\(days.rawValue) days without \(exercise)"
        }

        static let all: [Removal] = DaysPerWeek.allCases.flatMap { days in
            BriefTemplates.catalogRows.keys.sorted().map { Removal(days: days, exercise: $0) }
        }
    }

    static func input(_ days: DaysPerWeek, goal: TrainingGoal = .hypertrophy, units: Units = .lb) -> Brief.Case {
        Brief.Case(goal: goal, days: days, units: units)
    }

    /// A lifter's own exercise that reuses `exercise`'s name, with a load no template would start at.
    static func customTwin(of exercise: Exercise, number: Int, isCustom: Bool = true) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(880_000 + number)),
            name: exercise.name,
            shortName: exercise.shortName,
            equipment: exercise.equipment,
            primaryMuscle: exercise.primaryMuscle,
            pattern: exercise.pattern,
            defaultStartLoad: [.lb: .pounds(995), .kg: .kilograms(450)],
            isCustom: isCustom
        )
    }

    /// The bundled catalog with the exercise called `name` changed by `edit`.
    static func catalog(editing name: String, _ edit: (inout Exercise) -> Void) throws -> [Exercise] {
        var catalog = try Brief.catalog()
        let index = try #require(catalog.firstIndex { $0.name == name }, "\(name) is not in the catalog")
        edit(&catalog[index])
        return catalog
    }

    @Test(
        "Each split asks only for its own exercises: missing one it uses throws naming it, any other is fine",
        arguments: Removal.all
    )
    func missingExercise_throwsOnlyWhereUsed(_ removal: Removal) throws {
        let whole = try Brief.catalog()
        let catalog = whole.filter { $0.name != removal.exercise }
        try #require(catalog.count == whole.count - 1, "\(removal.exercise) is not in the catalog once")
        let input = Self.input(removal.days)
        if Brief.exerciseNames(removal.days).contains(removal.exercise) {
            #expect(throws: ProgramTemplateError.unknownExercise(removal.exercise), "\(removal)") {
                try Brief.program(input, catalog: catalog)
            }
        } else {
            #expect(try Brief.program(input, catalog: catalog) == Brief.program(input), "\(removal)")
        }
    }

    @Test(
        "An empty catalog throws for the first exercise of the first day, for every goal and unit",
        arguments: Brief.Case.all
    )
    func emptyCatalog_namesTheFirstExercise(_ input: Brief.Case) throws {
        let first = try #require(Brief.split(input.days).days.first?.lifts.first?.exercise)
        #expect(throws: ProgramTemplateError.unknownExercise(first), "\(input)") {
            try Brief.program(input, catalog: [])
        }
    }

    @Test(
        "With several exercises missing, the error names the first in day and slot order",
        arguments: DaysPerWeek.allCases
    )
    func severalMissing_namesTheFirstInTemplateOrder(_ days: DaysPerWeek) throws {
        let ordered = Brief.split(days).days.flatMap(\.lifts).map(\.exercise)
        let missing = Set([ordered[ordered.count - 1], ordered[ordered.count / 2], ordered[2]])
        let first = try #require(ordered.first { missing.contains($0) })
        let catalog = try Brief.catalog().filter { !missing.contains($0.name) }
        #expect(throws: ProgramTemplateError.unknownExercise(first), "\(days): \(missing.sorted())") {
            try Brief.program(Self.input(days), catalog: catalog)
        }
    }

    @Test(
        "A failed call leaves nothing behind: the next call with the whole catalog is the usual block",
        arguments: DaysPerWeek.allCases
    )
    func failure_thenSuccess_isTheUsualProgram(_ days: DaysPerWeek) throws {
        let input = Self.input(days)
        let last = try #require(Brief.split(days).days.last?.lifts.last?.exercise)
        let catalog = try Brief.catalog().filter { $0.name != last }
        var drawn = 0
        #expect(throws: ProgramTemplateError.unknownExercise(last)) {
            try ProgramTemplates.program(Brief.request(input), catalog: catalog, id: Brief.programID) {
                drawn += 1
                return Fixtures.uuid(drawn)
            }
        }
        let total = 8 + days.rawValue + Brief.split(days).days.flatMap(\.lifts).count
        #expect(drawn <= total, "\(days): \(drawn) of \(total) ids drawn before the throw")
        #expect(try Brief.program(input) == Brief.program(input))
    }
}

// MARK: - Namesakes and near misses

extension TemplatesCatalogAdversarialTests {
    @Test(
        "Custom exercises that reuse every template name are ignored, before or after the catalog's own",
        arguments: Brief.Case.pounds
    )
    func customNamesakes_areIgnored(_ input: Brief.Case) throws {
        let catalog = try Brief.catalog()
        let twins = catalog.filter { Brief.catalogRows[$0.name] != nil }.enumerated()
            .map { Self.customTwin(of: $0.element, number: $0.offset) }
        try #require(twins.count == 22)
        let baseline = try Brief.program(input)
        #expect(try Brief.program(input, catalog: twins + catalog) == baseline, "\(input): customs first")
        #expect(try Brief.program(input, catalog: catalog + twins) == baseline, "\(input): customs last")
    }

    @Test(
        "A custom exercise is no stand-in: with only a custom Deadlift, the Deadlift is unknown",
        arguments: DaysPerWeek.allCases
    )
    func onlyACustomNamesake_isUnknown(_ days: DaysPerWeek) throws {
        let catalog = try Self.catalog(editing: "Deadlift") { $0.isCustom = true }
        #expect(throws: ProgramTemplateError.unknownExercise("Deadlift"), "\(days)") {
            try Brief.program(Self.input(days), catalog: catalog)
        }
    }

    @Test(
        "Names match exactly: a near miss of Weighted Pull-Up is not it, though plain Pull-Up is in the catalog",
        arguments: [
            "weighted pull-up", "WEIGHTED PULL-UP", "Weighted Pull-Up ", " Weighted Pull-Up", "Weighted Pull Up",
            "Weighted Pull\u{2011}Up", "Weighted Pullup", "Pull-Up (Weighted)", ""
        ]
    )
    func nearMissName_isUnknown(_ name: String) throws {
        let catalog = try Self.catalog(editing: "Weighted Pull-Up") { $0.name = name }
        #expect(catalog.contains { $0.name == "Pull-Up" && !$0.isCustom })
        for days in DaysPerWeek.allCases {
            #expect(throws: ProgramTemplateError.unknownExercise("Weighted Pull-Up"), "\(days), “\(name)”") {
                try Brief.program(Self.input(days), catalog: catalog)
            }
        }
    }

    @Test("A short name is not a name: an exercise whose short name is a template's full name is not matched")
    func shortName_isNotMatched() throws {
        var catalog = try Brief.catalog().filter { $0.name != "Back Squat" }
        catalog.append(Exercise(
            id: ExerciseID(Fixtures.uuid(881_000)),
            name: "High-Bar Squat",
            shortName: "Back Squat",
            equipment: .barbell,
            primaryMuscle: .quads,
            pattern: .squat,
            defaultStartLoad: [.lb: .pounds(45), .kg: .kilograms(20)]
        ))
        #expect(throws: ProgramTemplateError.unknownExercise("Back Squat")) {
            try Brief.program(Self.input(.three), catalog: catalog)
        }
    }

    @Test("A catalog that lists every exercise three times, the last time reversed, gives the usual block")
    func repeatedCatalog_givesTheSameBlock() throws {
        let catalog = try Brief.catalog()
        for input in Brief.Case.pounds {
            let program = try Brief.program(input, catalog: catalog + catalog + catalog.reversed())
            #expect(try program == Brief.program(input), "\(input)")
        }
    }

    @Test("Of two catalog exercises with one name the first given is used, as the generator documents")
    func duplicateCatalogName_firstWins() throws {
        let catalog = try Brief.catalog()
        let bench = try #require(catalog.first { $0.name == "Barbell Bench Press" })
        let twin = Self.customTwin(of: bench, number: 99, isCustom: false)
        let input = Self.input(.four, goal: .both)
        let baseline = try Brief.program(input)
        #expect(try Brief.program(input, catalog: catalog + [twin]) == baseline)
        let other = try Brief.program(input, catalog: [twin] + catalog)
        #expect(other.days[0].slots[0].exerciseID == twin.id)
        #expect(other.days[0].slots[0].startLoad == .pounds(995))
        #expect(other.days.flatMap(\.slots).dropFirst() == baseline.days.flatMap(\.slots).dropFirst())
    }
}

// MARK: - Loads the catalog may hold

extension TemplatesCatalogAdversarialTests {
    @Test("An exercise with a load in the other unit only starts at `startLoad(in:)`: converted, on the unit's step")
    func loadInOtherUnitOnly_isConverted() throws {
        let catalog = try Self.catalog(editing: "Barbell Bench Press") { $0.defaultStartLoad = [.lb: .pounds(45)] }
        let program = try Brief.program(Self.input(.four, units: .kg), catalog: catalog)
        // 45 lb is 20.41 kg, which is 20 kg on a barbell's 2.5 kg step (decision #9).
        #expect(program.days[0].slots[0].startLoad == .kilograms(20))
        let other = try Self.catalog(editing: "Barbell Bench Press") { $0.defaultStartLoad = [.kg: .kilograms(20)] }
        // 20 kg is 44.09 lb, which is 45 lb on a barbell's 5 lb step.
        #expect(try Brief.program(Self.input(.four), catalog: other).days[0].slots[0].startLoad == .pounds(45))
    }

    @Test("An exercise with no load at all starts at zero and does not trap")
    func noLoad_startsAtZero() throws {
        let catalog = try Self.catalog(editing: "Deadlift") { $0.defaultStartLoad = [:] }
        for units in Units.allCases {
            let program = try Brief.program(Self.input(.four, units: units), catalog: catalog)
            #expect(program.days[3].slots[0].startLoad == .zero)
        }
    }

    @Test("A negative catalog load is the slot's validation error, as documented, not a block")
    func negativeLoad_throwsTheSlotError() throws {
        let catalog = try Self.catalog(editing: "Back Squat") { $0.defaultStartLoad[.lb] = .pounds(-45) }
        #expect(throws: SlotValidationError.negativeStartLoad(.pounds(-45))) {
            try Brief.program(Self.input(.six), catalog: catalog)
        }
        #expect(throws: Never.self) { try Brief.program(Self.input(.six, units: .kg), catalog: catalog) }
    }
}
