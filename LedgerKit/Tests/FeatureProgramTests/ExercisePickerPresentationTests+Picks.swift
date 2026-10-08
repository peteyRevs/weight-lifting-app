@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 criteria 8, 10 and 11: an exercise's row, the picks, the foot, and the picks as the slots the
/// Domain builds (the second half of the brief's criterion 12).
nonisolated extension ExercisePickerPresentationTests {
    // MARK: Criterion 8: the rows

    @Test("A row reads the equipment and the primary muscle; an exercise the day holds says so, apart as well")
    func row_readsEquipmentMuscleAndTheDaysMark() throws {
        let squat = try Fixture.id("Back Squat")
        let model = try ExercisePickerPresentation.make(Fixture.input(dayExercises: [squat]))
        let inDay = try model.row("Back Squat")
        #expect(inDay.detail == "Barbell · Quads")
        #expect(inDay.inDayMark == "already in this day")
        #expect(inDay.line == "Barbell · Quads · already in this day")
        #expect(inDay.spokenLabel == "Back Squat")
        #expect(inDay.spokenValue == "Barbell · Quads · already in this day")
        let other = try model.row("Lat Pulldown")
        #expect(other.detail == "Cable · Back")
        #expect(other.inDayMark == nil)
        #expect(other.line == "Cable · Back")
        #expect(other.spokenValue == "Cable · Back")
        #expect(model.rows.count { $0.inDayMark != nil } == 1)
    }

    @Test("Every kind of equipment and every muscle group has its word on a row")
    func rows_nameEveryEquipmentAndMuscle() throws {
        let details = try Set(ExercisePickerPresentation.make(Fixture.input()).rows.map(\.detail))
        let words = Set(details.flatMap { $0.components(separatedBy: " · ") })
        #expect(words == [
            "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Band",
            "Chest", "Back", "Shoulders", "Quads", "Hamstrings", "Glutes", "Calves", "Biceps", "Triceps",
            "Forearms", "Core"
        ])
    }

    @Test("An exercise the day holds can still be picked: the day may hold it twice")
    func rowInTheDay_canBePicked() throws {
        let squat = try Fixture.id("Back Squat")
        var screen = try PickerScreen(Fixture.input(dayExercises: [squat]))
        #expect(try screen.model.row("Back Squat").action == .setPicked(true, exercise: squat))
        try screen.tapRow("Back Squat")
        let row = try screen.model.row("Back Squat")
        #expect(row.isPicked)
        #expect(row.inDayMark == "already in this day")
        #expect(screen.model.foot.action == .add([squat]))
    }

    @Test("A picked row carries its place among the picks, and its tap takes it out again")
    func picks_carryTheirPlace_andUnpick() throws {
        var screen = try PickerScreen(Fixture.input())
        #expect(try screen.model.row("Leg Press").isPicked == false)
        #expect(try screen.model.row("Leg Press").pickMark == nil)
        for name in ["Leg Press", "Back Squat", "Lat Pulldown"] {
            try screen.tapRow(name)
        }
        #expect(screen.model.pickLine == "1 Leg Press · 2 Back Squat · 3 Lat Pulldown")
        let squat = try Fixture.id("Back Squat")
        #expect(try screen.model.row("Back Squat").action == .setPicked(false, exercise: squat))
        try screen.tapRow("Back Squat")
        #expect(screen.model.pickLine == "1 Leg Press · 2 Lat Pulldown")
        #expect(try screen.model.row("Back Squat").isPicked == false)
        // Picked again, it goes to the end.
        try screen.tapRow("Back Squat")
        #expect(screen.model.pickLine == "1 Leg Press · 2 Lat Pulldown · 3 Back Squat")
    }

    @Test("A pick's action says what becomes true: applied twice it is one pick, at its place")
    func pickAction_appliedTwice_isOnePick() throws {
        var screen = try PickerScreen(Fixture.input())
        let pickPress = try screen.model.row("Leg Press").action
        let pickSquat = try screen.model.row("Back Squat").action
        for action in [pickPress, pickSquat, pickPress, pickPress] {
            try screen.tap(action)
        }
        #expect(try screen.input.picks == [Fixture.id("Leg Press"), Fixture.id("Back Squat")])
        let unpick = try screen.model.row("Leg Press").action
        try screen.tap(unpick)
        try screen.tap(unpick)
        #expect(try screen.input.picks == [Fixture.id("Back Squat")])
    }

    // MARK: Criterion 10: the foot

    @Test("The foot reads the brief's three texts, and is disabled with no pick")
    func foot_readsTheBriefsTexts() throws {
        var screen = try PickerScreen(Fixture.input())
        #expect(screen.model.foot == ExercisePickerModel.Foot(title: "Select exercises to add", action: nil))
        try screen.tapRow("Leg Press")
        #expect(screen.model.foot.title == "Add 1 exercise")
        try screen.tapRow("Back Squat")
        try screen.tapRow("Lat Pulldown")
        #expect(screen.model.foot.title == "Add 3 exercises")
        try screen.tapRow("Leg Press")
        try screen.tapRow("Back Squat")
        try screen.tapRow("Lat Pulldown")
        #expect(screen.model.foot == ExercisePickerModel.Foot(title: "Select exercises to add", action: nil))
    }

    @Test("The foot's action carries the picks in the order picked, also those the filter hides")
    func foot_carriesThePicksInOrder() throws {
        let picks = try ["Leg Press", "Back Squat", "Lat Pulldown"].map(Fixture.id)
        var screen = try PickerScreen(Fixture.input(picks: picks))
        #expect(screen.model.foot.action == .add(picks))
        try screen.tapChip("Back", in: \.muscles)
        #expect(screen.model.pickLine == "3 Lat Pulldown", "the place is the pick's, not the listed row's")
        #expect(screen.model.foot == ExercisePickerModel.Foot(title: "Add 3 exercises", action: .add(picks)))
        try screen.tap(.search("zzz"))
        #expect(screen.model.empty != nil)
        #expect(screen.model.foot.action == .add(picks))
    }

    @Test("A pick that comes twice counts once, at its first place; one that is no longer stored is ignored")
    func picks_twiceOrNotStored_areReadOnce() throws {
        let press = try Fixture.id("Leg Press")
        let squat = try Fixture.id("Back Squat")
        let gone = ExerciseID(Fixtures.uuid(7999))
        let model = try ExercisePickerPresentation.make(Fixture.input(picks: [gone, press, squat, press, gone]))
        #expect(model.foot == ExercisePickerModel.Foot(title: "Add 2 exercises", action: .add([press, squat])))
        #expect(model.pickLine == "1 Leg Press · 2 Back Squat")
        let none = try ExercisePickerPresentation.make(Fixture.input(picks: [gone], dayExercises: [gone]))
        #expect(none.foot.action == nil)
        #expect(none.rows.count == 224)
        #expect(none.rows.allSatisfy { !$0.isPicked && $0.inDayMark == nil })
    }

    // MARK: Criterion 11: the picks become slots through the Domain

    /// What the store does with the foot's action, by `ExercisePickerAction.add`'s documentation: a slot from
    /// `DayEditing.newSlot` for each id, in order, handed to the Day editor as one edit.
    static func edit(
        adding picked: [ExerciseID],
        to day: DayTemplateID,
        exercises: [Exercise],
        settings: Settings,
        firstID: Int = 9100
    ) throws -> DayEditorEdit {
        let slots = try picked.enumerated().map { place, id in
            try DayEditing.newSlot(
                id: SlotID(Fixtures.uuid(firstID + place)),
                exercise: #require(exercises.first { $0.id == id }),
                units: settings.units,
                defaultRest: settings.defaultRest
            )
        }
        return .slot(.add(slots), day: day)
    }

    @Test("Adding three picks appends three slots with rule 7's defaults, in the order picked, and closes the sheet")
    func add_appendsRuleSevenSlotsInPickOrder() throws {
        var day = try DayScreen(DayEditorFixtures.seedInput())
        let before = try day.content().rows.count
        var library = try PickerScreen(Fixture.input(
            muscle: .legs,
            dayExercises: Set(#require(day.day).slots.map(\.exerciseID))
        ))
        for name in ["Leg Press", "Back Squat", "Hack Squat"] {
            try library.tapRow(name)
        }
        #expect(library.model.foot.title == "Add 3 exercises")
        try library.tap(library.model.foot.action)
        let picked = try #require(library.added.first)
        try day.tap(.edit(Self.edit(
            adding: picked,
            to: day.input.day,
            exercises: library.input.exercises,
            settings: day.input.settings
        )))

        let rows = try day.content().rows
        #expect(rows.count == before + 3)
        #expect(rows.suffix(3).map(\.name) == ["Leg Press", "Back Squat", "Hack Squat"])
        let added = try #require(day.day).slots.suffix(3)
        let defaults = added.map { "\($0.sets)×\($0.reps)–\($0.repsHi) \($0.progression)" }
        #expect(defaults == Array(repeating: "3×8–10 linear", count: 3))
        #expect(added.allSatisfy { $0.rpe.value == 8 && $0.rest == day.input.settings.defaultRest })
        #expect(added.allSatisfy { !$0.isSupersetWithPrevious && $0.dropSets == 0 && $0.misses.isEmpty })
        #expect(added.allSatisfy { $0.step == nil })
        #expect(rows.suffix(3).map(\.load) == ["40 lb", "45 lb", "40 lb"], "each exercise's start load")
        // The sheet closes; the chips stay, the query and the picks go.
        #expect(!library.isOpen)
        #expect(library.model.muscles.selected == ["Legs"])
        #expect(library.model.search.query.isEmpty)
        #expect(library.model.foot.action == nil)
    }

    @Test("The picks' edit is DayEditing.addSlots, safe to apply twice, and the same exercise may come twice")
    func addEdit_isAddSlots_andSafeTwice() throws {
        let program = try Fixtures.seedProgram()
        let day = program.days[0]
        let bench = Fixtures.CatalogID.benchPress
        let edit = try Self.edit(
            adding: [bench, bench],
            to: day.id,
            exercises: Fixture.catalog(),
            settings: Fixtures.settingsKg
        )
        guard case let .slot(.add(slots), _) = edit else {
            Issue.record("not an add")
            return
        }
        let once = edit.applied(to: program)
        let isAddSlots = once == ProgramEditing.updateDay(program, day: day.id) { DayEditing.addSlots($0, slots) }
        #expect(isAddSlots)
        #expect(once.days[0].slots.count == day.slots.count + 2)
        #expect(once.days[0].slots.suffix(2).map(\.exerciseID) == [bench, bench])
        #expect(once.days[0].slots.suffix(2).allSatisfy { $0.rest == Fixtures.settingsKg.defaultRest })
        #expect(once.days[0].slots.suffix(2).allSatisfy { $0.startLoad == slots[0].startLoad })
        let isSame = edit.applied(to: once) == once
        #expect(isSame, "the slots carry their ids: a second application adds nothing")
        #expect(edit.isRelative == false)
        // A day the program does not hold, and slots the day already holds, change nothing.
        let elsewhere = DayEditorEdit.slot(.add(slots), day: DayTemplateID(Fixtures.uuid(999)))
        let isUntouched = elsewhere.applied(to: program) == program
        #expect(isUntouched)
        let held = DayEditorEdit.slot(.add(day.slots), day: day.id)
        let isUnchanged = held.applied(to: program) == program
        #expect(isUnchanged)
    }

    @Test("Cancel closes the sheet with nothing added, and empties the query and the picks")
    func cancel_closesAndAddsNothing() throws {
        var screen = try PickerScreen(Fixture.input(query: "press", equipment: .machine))
        try screen.tapRow("Leg Press")
        try screen.tap(screen.model.cancel.action)
        #expect(!screen.isOpen)
        #expect(screen.added.isEmpty)
        #expect(screen.model.foot.action == nil)
        #expect(screen.model.search.query.isEmpty)
        #expect(screen.model.equipment.selected == ["Machine"])
    }
}
