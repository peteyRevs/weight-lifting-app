import Foundation
@testable import LedgerDomain
import Testing

/// How `ProgramTemplates.program` finds its exercises in the catalog it is given: by exact name, among the
/// catalog's own exercises (F08 criterion 7, the brief's amendment 4).
@Suite("ProgramTemplates · catalog", .tags(.domain))
struct ProgramTemplatesCatalogTests {
    /// A second exercise called `name`, as a lifter's own or as another catalog row.
    private func exercise(named name: String, number: Int, isCustom: Bool) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(number)),
            name: name,
            shortName: "OTHER",
            equipment: .dumbbell,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .pounds(100), .kg: .kilograms(50)],
            isCustom: isCustom
        )
    }

    /// The 22 exercise names of the brief's templates.
    private static let briefNames: Set<String> = Set(
        DaysPerWeek.allCases.flatMap { TemplateOracle.split(for: $0).days.flatMap(\.exercises) }
    )

    @Test("Every template exercise name is a catalog exercise's full name", arguments: DaysPerWeek.allCases)
    func templates_everyExerciseName_isInTheBundledCatalog(days: DaysPerWeek) throws {
        let catalog = try BundledCatalog.exercises()
        let names = ProgramTemplates.split(for: days).days.flatMap(\.lifts).map(\.exercise)
        #expect(!names.isEmpty)
        for name in names {
            let matches = catalog.filter { $0.name == name }
            #expect(matches.count == 1, "\(name)")
            #expect(matches.allSatisfy { !$0.isCustom }, "\(name)")
        }
        #expect(Self.briefNames.count == 22)
        #expect(Self.briefNames.isSuperset(of: names))
    }

    @Test("Every spec §6.4 row belongs to an exercise of the 4-day split")
    func specSeed_namesTheFourDaySplitsExercises() {
        let names = ProgramTemplates.upperLower.days.flatMap(\.lifts).map(\.exercise)
        #expect(names.count == 16)
        #expect(Set(ProgramTemplates.specSeed.keys) == Set(names))
        #expect(DaysPerWeek.allCases.filter { !ProgramTemplates.split(for: $0).seed.isEmpty } == [.four])
    }

    @Test("Upper B opens with Weighted Pull-Up, not the catalog's unloaded Pull-Up", arguments: Units.allCases)
    func program_fourDay_pullUpIsTheWeightedOne(units: Units) throws {
        let catalog = try BundledCatalog.byID()
        let program = try TemplateCase(goal: .both, days: .four, units: units).program()
        let slot = try #require(program.days.first { $0.tag == "UB" }?.slots.first)
        let weighted = try #require(catalog[slot.exerciseID])
        #expect(weighted.name == "Weighted Pull-Up")
        #expect(try #require(slot.startLoad) > .zero)
        // The trap is real: the catalog has a "Pull-Up" too, and it starts with no load.
        let unloaded = try #require(catalog.values.first { $0.name == "Pull-Up" })
        #expect(unloaded.id != weighted.id)
        #expect(unloaded.startLoad(in: units) == .zero)
    }

    @Test("With no catalog the first template exercise is unknown", arguments: [
        (DaysPerWeek.three, "Back Squat"),
        (.four, "Barbell Bench Press"),
        (.five, "Barbell Bench Press"),
        (.six, "Barbell Bench Press")
    ])
    func program_emptyCatalog_throwsUnknownExercise(days: DaysPerWeek, first: String) {
        #expect(throws: ProgramTemplateError.unknownExercise(first)) {
            try TemplateCase(goal: .both, days: days).program(catalog: [])
        }
    }

    @Test("A catalog that lacks one template exercise names it", arguments: ["Seated Leg Curl", "Weighted Pull-Up"])
    func program_missingExercise_throwsUnknownExercise(missing: String) throws {
        let catalog = try BundledCatalog.exercises().filter { $0.name != missing }
        #expect(throws: ProgramTemplateError.unknownExercise(missing)) {
            try TemplateCase(goal: .strength, days: .four).program(catalog: catalog)
        }
    }

    @Test("A generation that fails has drawn no id, whichever exercise is missing", arguments: DaysPerWeek.allCases)
    func program_unknownExercise_drawsNoID(days: DaysPerWeek) throws {
        let bundled = try BundledCatalog.exercises()
        let block = TemplateCase(goal: .both, days: days)
        var drawn = 0
        let newID = {
            drawn += 1
            return Fixtures.uuid(drawn)
        }
        let names = Set(TemplateOracle.split(for: days).days.flatMap(\.exercises))
        #expect(names.count >= 3 * days.rawValue)
        for missing in names {
            let catalog = bundled.filter { $0.name != missing }
            #expect(throws: ProgramTemplateError.unknownExercise(missing)) {
                try ProgramTemplates.program(block.request, catalog: catalog, id: Fixtures.programID, newID: newID)
            }
            #expect(drawn == 0, "\(missing): \(drawn) ids drawn before the throw")
        }
        // So the id source is as it was: the next call, with the whole catalog, is the usual block.
        let program = try ProgramTemplates.program(
            block.request,
            catalog: bundled,
            id: Fixtures.programID,
            newID: newID
        )
        #expect(try program == (block.program()))
        #expect(drawn == 8 + program.days.count + program.days.flatMap(\.slots).count)
    }

    @Test("A custom exercise with a template's name is not used: alone it leaves the name unknown")
    func program_customExerciseWithATemplatesName_isIgnored() throws {
        let bundled = try BundledCatalog.exercises()
        let custom = exercise(named: "Barbell Bench Press", number: 7001, isCustom: true)
        let block = TemplateCase(goal: .both, days: .four)
        #expect(throws: ProgramTemplateError.unknownExercise("Barbell Bench Press")) {
            try block.program(catalog: [custom] + bundled.filter { $0.name != custom.name })
        }
        // Beside the catalog's own exercise, wherever it sits in the list, the catalog's is the one used.
        for catalog in [[custom] + bundled, bundled + [custom]] {
            #expect(try block.program(catalog: catalog) == block.program(catalog: bundled))
        }
    }

    @Test("Of two catalog exercises with one name, the first in the list is used")
    func program_twoCatalogExercisesWithOneName_usesTheFirst() throws {
        let bundled = try BundledCatalog.exercises()
        let twin = exercise(named: "Barbell Bench Press", number: 7002, isCustom: false)
        let block = TemplateCase(goal: .both, days: .four)
        #expect(try block.program(catalog: bundled + [twin]) == block.program(catalog: bundled))
        let slot = try #require(block.program(catalog: [twin] + bundled).days.first?.slots.first)
        #expect(slot.exerciseID == twin.id)
        #expect(slot.startLoad == .pounds(100))
    }

    @Test(
        "A slot's start load is the catalog's for its exercise and unit, and it has no step",
        arguments: TemplateCase.all
    )
    func program_startLoads_areTheCatalogs(_ block: TemplateCase) throws {
        let catalog = try BundledCatalog.byID()
        for slot in try block.program().days.flatMap(\.slots) {
            let exercise = try #require(catalog[slot.exerciseID])
            #expect(slot.startLoad == exercise.defaultStartLoad[block.units], "\(exercise.name)")
            #expect(slot.step == nil, "\(exercise.name)")
        }
    }

    @Test(
        "Criterion 8: in kilograms every start load is the catalog's kilogram load, a multiple of the kg step",
        arguments: TemplateCase.all.filter { $0.units == .kg }
    )
    func program_kilograms_startLoadsAreMultiplesOfTheStep(_ block: TemplateCase) throws {
        let catalog = try BundledCatalog.byID()
        for slot in try block.program().days.flatMap(\.slots) {
            let exercise = try #require(catalog[slot.exerciseID])
            let load = try #require(slot.startLoad)
            // Decision #22's kilogram steps, written out: 2.5 and 1.25 are exact as literals.
            let step: Weight = switch exercise.equipment {
            case .barbell: .kilograms(2.5)
            case .kettlebell: .kilograms(2)
            default: .kilograms(1.25)
            }
            #expect(load == exercise.defaultStartLoad[.kg], "\(exercise.name)")
            #expect(load > .zero, "\(exercise.name)")
            #expect(load.rounded(toStep: step) == load, "\(exercise.name): \(load.kilograms) kg")
        }
    }
}
