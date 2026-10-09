@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 adversarial round 1, criteria 6 to 10 and 13: `ExercisePickerPresentation.make` against the tester's
/// own reading of the screen (`AdvPicker`), on seeded inputs and on the cases the criteria name.
@Suite("Adversarial F11 S8 · the exercise library's model", .tags(.feature, .property))
nonisolated struct ExercisePickerModelAdversarialTests {
    static func catalogInput(
        query: String = "",
        muscle: ExerciseSearch.MuscleFilter? = nil,
        equipment: Equipment? = nil,
        picks: [ExerciseID] = [],
        day: Set<ExerciseID> = [],
        locale: String = "en_US"
    ) throws -> ExercisePickerInput {
        try ExercisePickerInput(
            exercises: ExerciseCatalog.seed(),
            dayExercises: day,
            query: query,
            muscle: muscle,
            equipment: equipment,
            picks: picks,
            locale: Locale(identifier: locale)
        )
    }

    @Test("On any input the model is the screen the tester's reading gives, line for line", arguments: PropertySeed.all)
    func make_seededInputs_matchTheTestersReading(seed: PropertySeed) {
        var generator = seed.generator
        for _ in 0 ..< 4 {
            let input = AdvPicker.input(using: &generator)
            let difference = AdvPicker.difference(input)
            #expect(difference == nil, "\(seed): \(difference ?? "")")
            let isSame = ExercisePickerPresentation.make(input) == ExercisePickerPresentation.make(input)
            #expect(isSame, "\(seed): the same input gave two models")
        }
    }

    @Test(
        "Any chain of taps, each applied as documented and then once more, keeps the screen the tester's reading",
        arguments: PropertySeed.all
    )
    func taps_seededChains_stayTheTestersReading(seed: PropertySeed) {
        var generator = seed.generator
        var input = AdvPicker.input(using: &generator)
        for step in 0 ..< 10 {
            let offered = AdvPicker.actions(of: ExercisePickerPresentation.make(input))
            let typed = ExercisePickerAction.search(AdvPicker.queries.randomElement(using: &generator) ?? "")
            guard let action = (offered + [typed]).randomElement(using: &generator) else {
                continue
            }
            let once = AdvPicker.apply(action, to: input)
            let twice = AdvPicker.apply(action, to: once.input)
            let isAbsolute = AdvPicker.lines(expectedFor: once.input) == AdvPicker.lines(expectedFor: twice.input)
                && ExercisePickerPresentation.make(once.input) == ExercisePickerPresentation.make(twice.input)
            #expect(isAbsolute, "\(seed) step \(step): \(action) is not absolute")
            let difference = AdvPicker.difference(once.input)
            #expect(difference == nil, "\(seed) step \(step) after \(action): \(difference ?? "")")
            if case let .add(ids) = action {
                let isThePicks = ids == AdvPicker.picks(input) && !ids.isEmpty && Set(ids).count == ids.count
                #expect(isThePicks, "\(seed) step \(step): add carries \(ids.count) ids")
                #expect(ids.allSatisfy { id in input.exercises.contains { $0.id == id } })
            }
            input = once.input
        }
    }

    @Test("The bundled catalog, under every chip pair and a query, is the tester's reading")
    func catalog_everyChipPair_matchesTheTestersReading() throws {
        let muscles: [ExerciseSearch.MuscleFilter?] = [nil] + ExerciseSearch.MuscleFilter.allCases
        let equipment: [Equipment?] = [nil] + Equipment.allCases
        let squat = try #require(ExerciseCatalog.seed().first { $0.name == "Back Squat" }).id
        var checked = 0
        for muscle in muscles {
            for kind in equipment {
                for query in ["", "  ", "ＲＯＷ", "prèss", "zzz"] {
                    let input = try Self.catalogInput(
                        query: query, muscle: muscle, equipment: kind, picks: [squat], day: [squat]
                    )
                    let difference = AdvPicker.difference(input)
                    #expect(difference == nil, "\(String(describing: muscle)) \(String(describing: kind)) \(query)")
                    checked += 1
                }
            }
        }
        #expect(checked == 6 * 8 * 5)
    }

    @Test("Equipment that has no chip filters nothing, selects All, and Clear filters and All both leave it")
    func equipmentWithoutChip_isAll() throws {
        for kind in [Equipment.kettlebell, .band] {
            let input = try Self.catalogInput(equipment: kind)
            let model = ExercisePickerPresentation.make(input)
            #expect(model.rows.count == 224, "\(kind)")
            #expect(model.equipment.selected == ["All"], "\(kind)")
            #expect(model.rows.contains { $0.detail.hasPrefix("Kettlebell") } && model.rows.contains {
                $0.detail.hasPrefix("Band")
            })
            for action in [model.equipment.chips[0].action, .clearFilters] {
                #expect(AdvPicker.apply(action, to: input).input.equipment == nil, "\(action)")
            }
        }
    }

    @Test("A query of blanks only, of any kind of blank, lists every exercise and is kept as typed")
    func blankQuery_listsEverything() throws {
        for query in ["", " ", "\t", "\n", "\u{3000}", " \u{00A0} ", "\u{2003}\u{2009}"] {
            let model = try ExercisePickerPresentation.make(Self.catalogInput(query: query))
            #expect(model.rows.count == 224, "«\(query.unicodeScalars.map(\.value))»")
            #expect(model.search.query == query)
        }
    }

    @Test("Clear filters resets the query and both chips, keeps the picks, and is offered only with no row")
    func clearFilters_resetsAllThree() throws {
        let squat = try #require(ExerciseCatalog.seed().first { $0.name == "Back Squat" }).id
        let input = try Self.catalogInput(query: "zzz", muscle: .arms, equipment: .cable, picks: [squat])
        let model = ExercisePickerPresentation.make(input)
        let clear = try #require(model.empty?.clear)
        #expect(clear.title == "Clear filters" && clear.action == .clearFilters)
        let after = AdvPicker.apply(clear.action, to: input).input
        #expect(after.query.isEmpty && after.muscle == nil && after.equipment == nil && after.picks == [squat])
        let cleared = ExercisePickerPresentation.make(after)
        #expect(cleared.rows.count == 224 && cleared.empty == nil)
        #expect(cleared.muscles.selected == ["All"] && cleared.equipment.selected == ["All"])
        #expect(cleared.foot.action == .add([squat]))
    }
}

nonisolated extension ExercisePickerModelAdversarialTests {
    @Test("No exercise stored gives the empty state, whatever else the input holds, and nothing to add")
    func emptyCatalog_isTheEmptyState() {
        let stranger = AdvPicker.stranger
        for query in ["", "row"] {
            let input = ExercisePickerInput(
                exercises: [], dayExercises: [stranger], query: query, muscle: .legs, equipment: .band,
                picks: [stranger, stranger], locale: Locale(identifier: "ar_EG")
            )
            let model = ExercisePickerPresentation.make(input)
            #expect(model.empty?.message == "Nothing matches that filter.")
            #expect(model.foot.title == "Select exercises to add" && model.foot.action == nil)
            #expect(AdvPicker.difference(input) == nil)
        }
    }

    @Test("Ten thousand stored exercises, a thousand of them picked, are one model, built in under two seconds")
    func tenThousandExercises_areOneModel() {
        var generator = SeededGenerator(seed: 8)
        let exercises = (0 ..< 10000).map { AdvPicker.exercise($0, using: &generator) }
        let picks = exercises.prefix(1000).map(\.id).shuffled(using: &generator)
        let input = ExercisePickerInput(
            exercises: exercises, dayExercises: Set(exercises.suffix(500).map(\.id)), query: "", muscle: nil,
            equipment: nil, picks: picks + picks, locale: Locale(identifier: "en_US")
        )
        let clock = ContinuousClock()
        var model: ExercisePickerModel?
        let taken = clock.measure { model = ExercisePickerPresentation.make(input) }
        #expect(model?.rows.count == 10000)
        #expect(model?.foot.title == "Add 1,000 exercises")
        #expect(model?.foot.action == .add(picks))
        #expect(model?.rows.count(where: \.isPicked) == 1000)
        #expect(model?.rows.first { $0.id == picks[999] }?.pickMark == "1,000")
        #expect(taken < .seconds(2), "\(taken)")
    }

    @Test("An exercise stored twice under one id does not trap and is added once (question F11-S8-Q1: two rows)")
    func exerciseStoredTwice_isAddedOnce() throws {
        let squat = try #require(ExerciseCatalog.seed().first { $0.name == "Back Squat" })
        let input = ExercisePickerInput(
            exercises: [squat, squat], dayExercises: [], query: "", muscle: nil, equipment: nil,
            picks: [squat.id], locale: Locale(identifier: "en_US")
        )
        let model = ExercisePickerPresentation.make(input)
        // `make` lists it twice, two rows of one id (the question); that it adds the exercise once is not one.
        #expect(model.foot.action == .add([squat.id]))
        #expect(!model.rows.isEmpty && model.rows.allSatisfy(\.isPicked))
    }
}
