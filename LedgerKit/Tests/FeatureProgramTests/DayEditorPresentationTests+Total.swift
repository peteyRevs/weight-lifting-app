@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 criteria 6 and 9: "Delete day" with its confirmation, and the days and inputs at the edges, none of
/// which may trap.
nonisolated extension DayEditorPresentationTests {
    // MARK: Delete day

    @Test("The confirmation names the day by its short title and counts the weeks that train it")
    func deleteDay_confirmation_namesTheDayAndItsWeeks() throws {
        let upperA = try DayEditorPresentation.make(DayEditorFixtures.seedInput()).content().deleteDay
        #expect(upperA.title == "Delete day")
        #expect(upperA.confirmation.title == "Delete Upper A?")
        #expect(upperA.confirmation.message == "It's scheduled in 8 weeks. Those days become rest.")
        #expect(upperA.confirmation.confirm.title == "Delete")
        #expect(upperA.confirmation.cancel == "Cancel")
        // Lower B is left out of the deload week.
        let lowerB = try DayEditorPresentation.make(DayEditorFixtures.seedInput(dayIndex: DayIndex.lowerB)).content()
        #expect(lowerB.deleteDay.confirmation.title == "Delete Lower B?")
        #expect(lowerB.deleteDay.confirmation.message == "It's scheduled in 7 weeks. Those days become rest.")
    }

    @Test("A day one week trains reads in the singular, twice in a week counts once, and nowhere has no line")
    func deleteDay_oneWeekAndNowhere() throws {
        var input = try DayEditorFixtures.input(slots: [])
        #expect(try DayEditorPresentation.make(input).content().deleteDay.confirmation.message == nil)
        input.program.weeks[2].schedule = [.monday: input.day, .thursday: input.day]
        let confirmation = try DayEditorPresentation.make(input).content().deleteDay.confirmation
        #expect(confirmation.message == "It's scheduled in 1 week. Those days become rest.")
        #expect(confirmation.title == "Delete Arms?")
    }

    @Test("Confirming removes the day, turns its weekdays to rest and leaves a model that says the day is gone")
    func deleteDay_confirm_removesTheDay() throws {
        var screen = try DayScreen(DayEditorFixtures.seedInput(dayIndex: DayIndex.lowerB))
        let deleted = screen.input.day
        try screen.tap(screen.content().deleteDay.confirmation.confirm.action)
        #expect(screen.model.isGone)
        #expect(screen.input.program.days.map(\.tag) == ["UA", "LA", "UB"])
        #expect(screen.input.program.weeks.allSatisfy { !$0.schedule.values.contains(deleted) })
        #expect(screen.input.program.weeks.map(\.schedule.count) == [3, 3, 3, 3, 3, 3, 3, 3])
    }

    @Test("The last day left can be deleted too")
    func deleteDay_theOnlyDay_isAllowed() throws {
        var screen = try DayScreen(DayEditorFixtures.input(slots: [DayEditorFixtures.slot(1)]))
        try screen.tap(screen.content().deleteDay.confirmation.confirm.action)
        #expect(screen.model.isGone)
        #expect(screen.input.program.days.isEmpty)
    }

    // MARK: Pure and total

    @Test("A day the program does not hold gives the model that says it is gone")
    func missingDay_isGone() throws {
        var input = try DayEditorFixtures.seedInput()
        input.day = DayTemplateID(Fixtures.uuid(999))
        #expect(DayEditorPresentation.make(input).isGone)
        input.program.days = []
        #expect(DayEditorPresentation.make(input).isGone)
    }

    @Test("A day with no exercise has no row, says so in the meta line, and can still be added to and deleted")
    func noSlots_showsNoRow() throws {
        let content = try DayEditorPresentation.make(DayEditorFixtures.input(slots: [])).content()
        #expect(content.groups.isEmpty)
        #expect(content.header.position == "DAY 1 OF 1")
        #expect(content.header.meta == "Week 1 · No exercises yet")
        #expect(content.addExercise.action == .openLibrary)
        #expect(content.deleteDay.confirmation.confirm.action == .edit(.deleteDay(content.id), closesPanel: true))
    }

    @Test("A day with one exercise reads in the singular and offers no move and no superset action")
    func oneSlot_offersOnlyRemove() throws {
        var input = try DayEditorFixtures.input(slots: [DayEditorFixtures.slot(1)])
        input.program.days[0].slots[0].sets = 1
        input.openSlot = DayEditorFixtures.slotID(1)
        let content = try DayEditorPresentation.make(input).content()
        #expect(content.header.meta == "Week 1 · 1 exercise · 1 set · ~2 min")
        #expect(content.indices == "1")
        #expect(content.rows.first?.panel?.actionLine == "Remove")
    }

    @Test("A week outside the block is read as the nearest week", arguments: [
        (-3, "Week 1", "WEEK 1"), (0, "Week 1", "WEEK 1"), (6, "Week 7", "WEEK 7"),
        (7, "Week 8", "WEEK 8 · DELOAD"), (8, "Week 8", "WEEK 8 · DELOAD"), (Int.max, "Week 8", "WEEK 8 · DELOAD"),
        (Int.min, "Week 1", "WEEK 1")
    ])
    func weekIndex_outsideTheBlock_readsAsTheNearest(weekIndex: Int, meta: String, eyebrow: String) throws {
        var input = try DayEditorFixtures.seedInput(weekIndex: weekIndex)
        input.openSlot = input.program.days[0].slots[0].id
        let content = try DayEditorPresentation.make(input).content()
        #expect(content.header.meta.hasPrefix(meta + " · "), "\(content.header.meta)")
        #expect(content.rows.first?.panel?.details?.week.eyebrow == eyebrow)
        #expect(content.rows.first?.panel?.details?.strip.entries.filter(\.isShown).count == 1)
    }

    @Test("An open slot the day does not hold is read as none open")
    func openSlot_notInTheDay_isNoneOpen() throws {
        var input = try DayEditorFixtures.seedInput()
        // A slot of another day of the same program.
        input.openSlot = input.program.days[1].slots[0].id
        let content = try DayEditorPresentation.make(input).content()
        #expect(content.rows.allSatisfy { !$0.isOpen && $0.panel == nil })
        var closed = input
        closed.openSlot = nil
        let isSame = DayEditorPresentation.make(closed) == .editing(content)
        #expect(isSame, "a foreign open slot changed the model")
    }

    @Test("A slot whose exercise is not stored is listed under a dash, can be opened, moved and removed")
    func slotOfAMissingExercise_isListedAndRemovable() throws {
        var screen = try DayScreen(DayEditorFixtures.seedInput(weekIndex: 7))
        screen.input.exercises[Fixtures.CatalogID.benchPress] = nil
        let row = try screen.content().row("1")
        #expect(row.name == "—")
        #expect(row.load == nil)
        // Its own numbers: no prescription can be worked out without the exercise.
        #expect(row.scheme == "5×5")
        #expect(row.sub == "RPE 8 · 2:30 rest")
        #expect(row.spokenLabel == "1, —")
        #expect(row.spokenValue == "5×5 · RPE 8 · 2:30 rest")
        // The day still counts it, with its own sets: 5 + 2 + 3 + 2 + 2.
        #expect(try screen.content().header.meta.hasPrefix("Week 8 · 5 exercises · 14 sets · "))
        try screen.open("1")
        let hasDetails = try screen.panel().details != nil
        #expect(!hasDetails)
        #expect(try screen.panel().actionLine == "Superset with next · Move down · Remove")
        try screen.tap(screen.panel().remove.action)
        #expect(try screen.content().rows.map(\.name).contains("—") == false)
        #expect(try screen.content().rows.count == 4)
    }

    @Test("A program emptied of its weeks does not trap: the rows show the slots' own numbers")
    func noWeeks_doesNotTrap() throws {
        var input = try DayEditorFixtures.seedInput(weekIndex: 3)
        input.program.weeks = []
        input.openSlot = input.program.days[0].slots[1].id
        let content = try DayEditorPresentation.make(input).content()
        #expect(content.header.meta == "Week 1 · 5 exercises · 18 sets · ~39 min")
        #expect(content.rows.map(\.scheme) == ["5×5", "3×10", "4×8", "3×12", "3×15"])
        #expect(content.rows.allSatisfy { $0.load == nil })
        let panel = try #require(content.row("2").panel)
        let hasDetails = panel.details != nil
        #expect(!hasDetails)
        #expect(content.deleteDay.confirmation.message == nil)
    }

    @Test("A day that arrives with its first exercise joined to nothing before it is read as the Domain reads it")
    func firstSlotFlagged_isReadAsNormalForm() throws {
        var slots = try DayEditorFixtures.fiveWithASuperset()
        slots[0].isSupersetWithPrevious = true
        var input = try DayEditorFixtures.input(slots: slots)
        input.openSlot = slots[0].id
        let content = try DayEditorPresentation.make(input).content()
        #expect(content.indices == "1 · 2 · 3A · 3B · 4")
        #expect(try content.row("1").panel?.actionLine == "Superset with next · Move down · Remove")
    }

    @Test("A day that holds a slot id twice does not trap: both rows are drawn from the first's prescription")
    func slotIDTwice_doesNotTrap() throws {
        let slot = try DayEditorFixtures.slot(1)
        var input = try DayEditorFixtures.input(slots: [slot, slot])
        input.openSlot = slot.id
        let content = try DayEditorPresentation.make(input).content()
        #expect(content.indices == "1 · 2")
        #expect(content.rows.map(\.load) == content.rows.reversed().map(\.load))
        #expect(content.rows.map(\.isOpen) == [true, true])
    }

    @Test("The same input gives the same model, in any order of the exercises handed in")
    func sameInput_givesTheSameModel() throws {
        var input = try DayEditorFixtures.seedInput(weekIndex: 3)
        input.openSlot = input.program.days[0].slots[3].id
        let model = DayEditorPresentation.make(input)
        var generator = SeededGenerator(seed: 11)
        for _ in 0 ..< 5 {
            var shuffled = input
            shuffled.exercises = Dictionary(
                uniqueKeysWithValues: input.exercises.map { ($0.key, $0.value) }.shuffled(using: &generator)
            )
            let isSame = DayEditorPresentation.make(shuffled) == model
            #expect(isSame)
        }
    }

    @Test("Digits follow the locale handed in; loads, RPEs and rests are the Domain's own text")
    func locale_picksTheDigits() throws {
        var input = try DayEditorFixtures.seedInput()
        input.locale = Locale(identifier: "ar_EG")
        input.openSlot = input.program.days[0].slots[0].id
        let content = try DayEditorPresentation.make(input).content()
        #expect(content.header.position == "DAY ١ OF ٤")
        let row = try #require(content.rows.first)
        #expect(row.index == "١")
        #expect(row.scheme == "٥×٥")
        #expect(row.load == "180 lb")
        #expect(row.panel?.details?.fields.first?.value == "٥")
    }
}
