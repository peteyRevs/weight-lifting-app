@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6: the Day editor's display model for the brief's worked examples. This file holds the header, the
/// meta line and the rows; the superset and the moves (criteria 10 and 11) are in `+Groups`, the loads in
/// `+Loads`, "Delete day" and the odd days in `+Total`.
@Suite("DayEditorPresentation", .tags(.feature))
nonisolated struct DayEditorPresentationTests {
    typealias DayIndex = ProgramFixtures.DayIndex

    @Test("Upper A of the seed program reads as the brief writes the Day editor, word for word")
    func seedDay_readsAsTheBrief() throws {
        let content = try DayEditorPresentation.make(DayEditorFixtures.seedInput()).content()
        #expect(content.header.back.title == "Program")
        #expect(content.header.position == "DAY 1 OF 4")
        #expect(content.header.done.title == "Done")
        #expect(content.header.name == "Upper A — Push focus")
        #expect(content.header.nameLabel == "Day name")
        #expect(content.header.tag == "UA")
        #expect(content.header.meta == "Week 1 · 5 exercises · 18 sets · ~39 min")
        #expect(content.order == [
            "1 Barbell Bench Press", "2 Incline DB Press", "3 Chest-Supported Row", "4A Lat Pulldown",
            "4B Cable Lateral Raise"
        ].joined(separator: " · "))
        #expect(content.rows.map(\.scheme) == ["5×5", "3×10", "4×8", "3×12", "3×15"])
        #expect(content.rows.map(\.load) == ["180 lb", "50 lb", "65 lb", "100 lb", "12.5 lb"])
        #expect(content.addExercise.title == "+ Add exercise from library")
        #expect(content.deleteDay.title == "Delete day")
        #expect(content.id == DayTemplateID(Fixtures.uuid(300)))
    }

    @Test("A sub line names the equipment, the progression, the RPE and the rest; a superset rests its longest")
    func subLine_linearDoubleFixedDropAndNoRest() throws {
        let upperA = try DayEditorPresentation.make(DayEditorFixtures.seedInput()).content()
        #expect(upperA.rows.map(\.sub) == [
            "Barbell · +5/wk · RPE 8 · 2:30 rest",
            "Dumbbell · Reps 10–12 · RPE 8 · 1:30 rest",
            "Machine · +2.5/wk · RPE 8 · 1:30 rest",
            "Cable · Reps 12–14 · RPE 9 · no rest",
            "Cable · Reps 15–17 · RPE 9 · 1:15 rest"
        ])
        // The superset's last row shows the rest the workout takes: the pulldown's 1:15, not its own minute.
        // Lower A ends on a fixed exercise that closes a superset; Upper B's curl has a drop set.
        let lowerA = try DayEditorPresentation.make(DayEditorFixtures.seedInput(dayIndex: DayIndex.lowerA)).content()
        #expect(lowerA.rows.map(\.sub).suffix(2) == [
            "Machine · Reps 12–14 · RPE 9 · no rest", "Machine · Fixed · RPE 9 · 1:30 rest"
        ])
        let upperB = try DayEditorPresentation.make(DayEditorFixtures.seedInput(dayIndex: DayIndex.upperB)).content()
        #expect(upperB.rows.last?.sub == "Barbell · Reps 12–14 · drop · RPE 9 · 1 min rest")
        #expect(upperB.rows.map(\.hasDropSet) == [false, false, false, true])
        #expect(upperB.rows.first?.sub == "Bodyweight · +2.5/wk · RPE 8 · 2:30 rest")
    }

    @Test("A rest reads 45s under a minute, 2 min on the minute and 2:30 between", arguments: [
        (45, "45s rest"), (60, "1 min rest"), (120, "2 min rest"), (150, "2:30 rest"), (300, "5 min rest")
    ])
    func subLine_rest_takesTheDomainsLabel(seconds: Int, expected: String) throws {
        var input = try DayEditorFixtures.input(slots: [DayEditorFixtures.slot(1)])
        input.program.days[0].slots[0].rest = try #require(RestDuration(seconds: seconds))
        let row = try #require(DayEditorPresentation.make(input).content().rows.first)
        #expect(row.sub == "Barbell · +5/wk · RPE 8 · \(expected)")
    }

    @Test("A deload week counts its own sets and minutes, and its rows show its sets, load and RPE")
    func meta_deloadWeek_countsThePrescribedSets() throws {
        let input = try DayEditorFixtures.seedInput(weekIndex: 7)
        let content = try DayEditorPresentation.make(input).content()
        // One set fewer for each of the five exercises: 18 − 5.
        let day = input.program.days[0]
        let exercises = input.exercises
        let prescribed = try Dictionary(uniqueKeysWithValues: day.slots.map { slot in
            try (slot.id, ProgressionRules.prescribe(
                week: input.program.weeks[7],
                weekIndex: 7,
                slot: slot,
                exercise: #require(exercises[slot.exerciseID]),
                units: .lb
            ))
        })
        let minutes = TimeEstimate.minutes(day: day, prescriptions: prescribed)
        #expect(minutes < TimeEstimate.minutes(day: day, prescriptions: [:]))
        #expect(content.header.meta == "Week 8 · 5 exercises · 13 sets · ~\(minutes) min")
        #expect(content.rows.map(\.scheme) == ["4×5", "2×11", "3×8", "2×13", "2×16"])
        #expect(content.rows.first?.load == "185 lb")
        #expect(content.rows.first?.sub == "Barbell · +5/wk · RPE 6 · 2:30 rest")
    }

    @Test("A drop set counts as a set of the day in the meta line")
    func meta_dropSet_isCounted() throws {
        let content = try DayEditorPresentation.make(DayEditorFixtures.seedInput(dayIndex: DayIndex.upperB)).content()
        #expect(content.header.position == "DAY 3 OF 4")
        #expect(content.header.meta == "Week 1 · 4 exercises · 15 sets · ~37 min")
    }

    @Test("Back and Done both ask the app to close the editor, and the library button asks for the library")
    func header_backAndDone_closeTheDay() throws {
        var screen = try DayScreen(DayEditorFixtures.seedInput())
        let content = try screen.content()
        try screen.tap(content.header.back.action)
        try screen.tap(content.header.done.action)
        try screen.tap(content.addExercise.action)
        #expect(screen.routes == [.closeDay, .closeDay])
        #expect(screen.libraryOpenings == 1)
        let isUntouched = try screen.input.program == Fixtures.seedProgram()
        #expect(isUntouched)
    }

    @Test("A typed name is one edit, and the header then shows the cleaned name; a blank one changes nothing")
    func header_rename_isOneEdit() throws {
        var screen = try DayScreen(DayEditorFixtures.seedInput())
        let day = try screen.content().id
        try screen.tap(.rename("  Push day\n", day: day))
        #expect(try screen.content().header.name == "Push day")
        try screen.tap(.rename("   ", day: day))
        #expect(try screen.content().header.name == "Push day")
        #expect(try screen.content().header.tag == "UA")
    }

    @Test("A row speaks its place and name, then the scheme, the load and the sub line as they are drawn")
    func row_speaksWhatIsDrawn() throws {
        let content = try DayEditorPresentation.make(DayEditorFixtures.seedInput()).content()
        let pulldown = try content.row("4A")
        #expect(pulldown.spokenLabel == "4A, Lat Pulldown")
        #expect(pulldown.spokenValue == "3×12 · 100 lb · Cable · Reps 12–14 · RPE 9 · no rest")
        #expect(try content.row("1").spokenLabel == "1, Barbell Bench Press")
        for row in content.rows {
            #expect(row.spokenValue == [row.scheme, row.load ?? "", row.sub].joined(separator: " · "))
        }
    }

    @Test("A tap on a row opens its panel, a tap on the open row closes it, and one panel is open at a time")
    func row_tap_opensAndCloses() throws {
        var screen = try DayScreen(DayEditorFixtures.seedInput())
        #expect(try screen.content().rows.allSatisfy { !$0.isOpen && $0.panel == nil })
        try screen.tap(screen.content().row("2").action)
        #expect(try screen.content().rows.map(\.isOpen) == [false, true, false, false, false])
        #expect(try screen.content().rows.map { $0.panel != nil } == [false, true, false, false, false])
        try screen.tap(screen.content().row("4A").action)
        #expect(try screen.content().rows.map(\.isOpen) == [false, false, false, true, false])
        try screen.tap(screen.content().row("4A").action)
        #expect(try screen.content().rows.allSatisfy { !$0.isOpen && $0.panel == nil })
        let isUntouched = try screen.input.program == Fixtures.seedProgram()
        #expect(isUntouched)
    }
}
