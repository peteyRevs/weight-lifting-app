@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Seeded checks of `ExercisePickerPresentation.make(_:)` on random inputs: the model is whole and agrees with
/// the input; the list is `ExerciseSearch`'s; every action is safe to apply twice; and any chain of taps
/// leaves picks that are stored, in the order picked, each once.
@Suite("ExercisePickerPresentation properties", .tags(.feature, .property))
nonisolated struct ExercisePickerPresentationPropertyTests {
    static let locales = ["en_US", "de_DE", "fr_FR", "ja_JP", "ar_EG", "hi_IN"]
    static let queries = ["", "", " ", "row", "PRESS", "curl ", "é", "db", "squat", "zzz", "a", "pull-up"]
    static let stranger = ExerciseID(Fixtures.uuid(99997))

    /// A random input: none to sixty of the catalog's exercises in any order, now and then with a custom one;
    /// a query; any muscle chip or none; any kind of equipment or none, those without a chip too; picks and
    /// day exercises drawn from the stored ones and a stranger, the picks with repeats.
    static func input(using generator: inout SeededGenerator) throws -> ExercisePickerInput {
        let catalog = try ExercisePickerFixtures.catalog().shuffled(using: &generator)
        var exercises = Array(catalog.prefix([0, 1, 60, Int.random(in: 0 ... 60, using: &generator)]
                .randomElement(using: &generator) ?? 0))
        if Bool.random(using: &generator) {
            exercises.append(ExercisePickerFixtures.customRow)
        }
        let known = exercises.map(\.id) + [stranger]
        let muscles: [ExerciseSearch.MuscleFilter?] = [nil] + ExerciseSearch.MuscleFilter.allCases
        let equipment: [Equipment?] = [nil] + Equipment.allCases
        return ExercisePickerInput(
            exercises: exercises,
            dayExercises: Set(known.filter { _ in Int.random(in: 0 ..< 4, using: &generator) == 0 }),
            query: queries.randomElement(using: &generator) ?? "",
            muscle: muscles.randomElement(using: &generator) ?? nil,
            equipment: equipment.randomElement(using: &generator) ?? nil,
            picks: (0 ..< Int.random(in: 0 ... 6, using: &generator)).compactMap { _ in
                known.randomElement(using: &generator)
            },
            locale: Locale(identifier: locales.randomElement(using: &generator) ?? "en_US")
        )
    }

    /// The picks as the criterion reads them, written here by hand: stored, each once, at its first place.
    static func expectedPicks(_ input: ExercisePickerInput) -> [ExerciseID] {
        var picks: [ExerciseID] = []
        for id in input.picks where input.exercises.contains(where: { $0.id == id }) && !picks.contains(id) {
            picks.append(id)
        }
        return picks
    }

    /// Every action the model hands out.
    static func actions(of model: ExercisePickerModel) -> [ExercisePickerAction] {
        [model.cancel.action] + model.muscles.chips.map(\.action) + model.equipment.chips.map(\.action)
            + model.rows.map(\.action) + [model.empty?.clear.action, model.foot.action].compactMap(\.self)
    }

    @Test("Any input gives a whole model that agrees with the input", arguments: PropertySeed.all)
    func make_randomInput_keepsTheInvariants(seed: PropertySeed) throws {
        var generator = seed.generator
        for _ in 0 ..< 2 {
            let input = try Self.input(using: &generator)
            let model = ExercisePickerPresentation.make(input)
            let isSame = ExercisePickerPresentation.make(input) == model
            #expect(isSame, "the same input gave another model")
            Self.checkList(model, input)
            Self.checkChips(model, input)
            Self.checkRows(model, input)
            Self.checkFoot(model, input)
        }
    }

    @Test("Every action of a model, applied twice, gives what one application gives", arguments: PropertySeed.all)
    func actions_randomInput_areSafeTwice(seed: PropertySeed) throws {
        var generator = seed.generator
        let input = try Self.input(using: &generator)
        for action in Self.actions(of: ExercisePickerPresentation.make(input)) {
            var screen = PickerScreen(input)
            try screen.tap(action)
            let once = ExercisePickerPresentation.make(screen.input)
            try screen.tap(action)
            let isSame = ExercisePickerPresentation.make(screen.input) == once
            #expect(isSame, "\(action) gave another model the second time")
        }
    }

    @Test("Any chain of taps leaves picks that are stored, each once, in the order picked", arguments: PropertySeed.all)
    func taps_randomInput_keepThePicksInOrder(seed: PropertySeed) throws {
        var generator = seed.generator
        var input = try Self.input(using: &generator)
        input.picks = Self.expectedPicks(input)
        var screen = PickerScreen(input)
        var order = input.picks
        for _ in 0 ..< 12 {
            let model = screen.model
            guard let action = Self.actions(of: model).randomElement(using: &generator) else {
                continue
            }
            try screen.tap(action)
            switch action {
            case let .setPicked(isPicked, exercise):
                order.removeAll { $0 == exercise }
                if isPicked {
                    order.append(exercise)
                }
            case .add, .cancel:
                order = []
            case .setQuery, .setMuscle, .setEquipment, .clearFilters:
                break
            }
            #expect(screen.input.picks == order, "after \(action)")
            #expect(screen.model.foot.action == (order.isEmpty ? nil : .add(order)))
            if case let .add(added) = action {
                #expect(screen.added.last == added && !added.isEmpty)
            }
            Self.checkRows(screen.model, screen.input)
        }
    }

    @Test("Clear filters always shows every stored exercise, and keeps the picks", arguments: PropertySeed.all)
    func clearFilters_randomInput_showsEveryStoredExercise(seed: PropertySeed) throws {
        var generator = seed.generator
        let input = try Self.input(using: &generator)
        var screen = PickerScreen(input)
        try screen.tap(.clearFilters)
        #expect(screen.model.rows.count == input.exercises.count)
        #expect(screen.model.foot == ExercisePickerPresentation.make(input).foot)
        #expect(screen.model.muscles.chips.first?.isSelected == true)
        #expect(screen.model.equipment.chips.first?.isSelected == true)
    }
}
