@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 criteria 6 to 10 and 13: the exercise library sheet as a display model, on the bundled catalog. The
/// brief's criterion 12 is `rowBackMachine_isExactlyChestSupportedRow` and, for its second half, the tests of
/// `+Picks`; the chips are in `+Chips`.
@Suite("ExercisePickerPresentation", .tags(.feature))
nonisolated struct ExercisePickerPresentationTests {
    typealias Fixture = ExercisePickerFixtures

    // MARK: Criterion 6: one input, one model; the list is ExerciseSearch's

    @Test("With no filter the sheet lists the whole catalog in name order, under its title and its search field")
    func noFilter_listsTheCatalogInNameOrder() throws {
        let catalog = try Fixture.catalog()
        let model = try ExercisePickerPresentation.make(Fixture.input())
        #expect(model.title == "Exercise library")
        #expect(model.cancel == ExercisePickerModel.Control(title: "Cancel", action: .cancel))
        #expect(model.search == ExercisePickerModel.Search(placeholder: "Search exercises", query: ""))
        #expect(model.rows.count == 224)
        let isInNameOrder = model.rows.map(\.id) == ExerciseSearch.sorted(catalog).map(\.id)
        #expect(isInNameOrder)
        #expect(model.names.prefix(3) == ["Ab Wheel Rollout", "Arnold Press", "Back Extension"])
    }

    @Test("Typing \"row\" with Back and Machine chosen lists exactly Chest-Supported Row (the brief's criterion 12)")
    func rowBackMachine_isExactlyChestSupportedRow() throws {
        var screen = try PickerScreen(Fixture.input())
        try screen.tap(.setQuery("row"))
        try screen.tapChip("Back", in: \.muscles)
        try screen.tapChip("Machine", in: \.equipment)
        let model = screen.model
        #expect(model.names == ["Chest-Supported Row"])
        #expect(model.search.query == "row")
        #expect(model.muscles.selected == ["Back"])
        #expect(model.equipment.selected == ["Machine"])
        #expect(try model.row("Chest-Supported Row").line == "Machine · Back")
    }

    @Test("A custom exercise is a row like any other, found by the same filter")
    func customExercise_isARowLikeAnyOther() throws {
        var input = try Fixture.input(query: "ROW", muscle: .back, equipment: .machine)
        input.exercises.append(Fixture.customRow)
        let model = ExercisePickerPresentation.make(input)
        #expect(model.names == ["Chest-Supported Row", "Garage T-Bar Row"])
        let row = try model.row("Garage T-Bar Row")
        #expect(row.id == Fixture.customRow.id)
        #expect(row.line == "Machine · Back")
        #expect(row.action == .setPicked(true, exercise: Fixture.customRow.id))
    }

    @Test(
        "The list is ExerciseSearch.filtered's, in its order, whatever is typed and chosen",
        arguments: ["", "row", " PRESS ", "élévation", "zzz"],
        [nil, ExerciseSearch.MuscleFilter.back, .legs, .arms]
    )
    func list_isExerciseSearchFiltered(query: String, muscle: ExerciseSearch.MuscleFilter?) throws {
        let catalog = try Fixture.catalog()
        for equipment in [nil] + ExercisePickerPresentation.equipmentChips {
            let input = try Fixture.input(query: query, muscle: muscle, equipment: equipment)
            let expected = ExerciseSearch.filtered(catalog, query: query, muscle: muscle, equipment: equipment)
            let isSame = ExercisePickerPresentation.make(input).rows.map(\.id) == expected.map(\.id)
            #expect(isSame, "\(query) \(String(describing: muscle)) \(String(describing: equipment))")
        }
    }

    @Test("The stored exercises may arrive in any order: the list is the same")
    func exercisesInAnyOrder_giveTheSameList() throws {
        var input = try Fixture.input(muscle: .chest)
        let names = ExercisePickerPresentation.make(input).names
        input.exercises.reverse()
        #expect(ExercisePickerPresentation.make(input).names == names)
        #expect(names.count > 10)
    }

    // MARK: Criterion 9: nothing matches

    @Test("A filter no exercise passes shows the brief's line and Clear filters, which empties all three")
    func nothingMatches_offersClearFilters() throws {
        var screen = try PickerScreen(Fixture.input(query: "zzz", muscle: .arms, equipment: .cable))
        let empty = try #require(screen.model.empty)
        #expect(empty.message == "Nothing matches that filter.")
        #expect(empty.clear == ExercisePickerModel.Control(title: "Clear filters", action: .clearFilters))
        #expect(screen.model.rows.isEmpty)
        try screen.tap(empty.clear.action)
        #expect(screen.model.rows.count == 224)
        #expect(screen.model.search.query.isEmpty)
        #expect(screen.model.muscles.selected == ["All"])
        #expect(screen.model.equipment.selected == ["All"])
    }

    @Test("A catalog with no exercise gives the same empty state, with the chips and the foot")
    func noExercises_givesTheEmptyState() throws {
        var input = try Fixture.input(picks: [Fixture.id("Back Squat")], dayExercises: [Fixture.id("Leg Press")])
        input.exercises = []
        let model = ExercisePickerPresentation.make(input)
        #expect(model.empty?.message == "Nothing matches that filter.")
        #expect(model.empty?.clear.title == "Clear filters")
        #expect(model.muscles.chips.count == 6 && model.equipment.chips.count == 6)
        #expect(model.foot == ExercisePickerModel.Foot(title: "Select exercises to add", action: nil))
    }

    // MARK: Criterion 13: pure and total

    @Test("The same input gives the same model, and the locale picks the digits")
    func sameInput_givesTheSameModel() throws {
        let picks = try ["Back Squat", "Leg Press", "Lat Pulldown"].map(Fixture.id)
        var input = try Fixture.input(muscle: .legs, picks: picks, dayExercises: [picks[0]])
        let isSame = ExercisePickerPresentation.make(input) == ExercisePickerPresentation.make(input)
        #expect(isSame)
        input.locale = Locale(identifier: "ar_EG")
        let arabic = ExercisePickerPresentation.make(input)
        #expect(arabic.foot.title == "Add ٣ exercises")
    }

    @Test("The search field's action stores the query as typed, and the model hands it back")
    func setQuery_keepsTheQueryAsTyped() throws {
        var screen = try PickerScreen(Fixture.input())
        try screen.tap(.setQuery(" Row "))
        #expect(screen.model.search.query == " Row ")
        #expect(screen.model.names.contains("Chest-Supported Row"), "the filter trims; the field does not")
    }
}
