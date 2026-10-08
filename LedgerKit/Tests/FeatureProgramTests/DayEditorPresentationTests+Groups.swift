@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6, the brief's criteria 10 and 11 as display models: a superset's header and letters, "Move up" and
/// "Move down" with a superset moving as one, "Superset with next" and "Break out".
nonisolated extension DayEditorPresentationTests {
    @Test("A superset has a header that counts its exercises and names the letter the lifter rests after")
    func supersetHeader_countsAndNamesTheLastLetter() throws {
        let content = try DayEditorPresentation.make(DayEditorFixtures.seedInput()).content()
        #expect(content.groups.map(\.rows.count) == [1, 1, 1, 2])
        #expect(content.groups.map { $0.header == nil } == [true, true, true, false])
        let header = try #require(content.groups.last?.header)
        #expect(header.title == "SUPERSET")
        #expect(header.note == "2 exercises back to back · rest after B")
        #expect(header.spokenLabel == "Superset")
        #expect(content.groups.compactMap(\.id) == [301, 302, 303, 304].map { SlotID(Fixtures.uuid($0)) })
    }

    @Test("A superset's last row shows the longest rest of its members, the one the workout and the minutes take")
    func superset_lastRow_showsTheGroupsRest() throws {
        var screen = try DayScreen(DayEditorFixtures.seedInput())
        // Lat Pulldown rests 1:15 and Cable Lateral Raise a minute: the round rests 1:15.
        #expect(try screen.content().row("4B").sub == "Cable · Reps 15–17 · RPE 9 · 1:15 rest")
        #expect(try screen.content().row("4B").spokenValue.hasSuffix("1:15 rest"))
        // The last member's own stepper still shows its own minute; raising it past 1:15 changes the row.
        try screen.open("4B")
        #expect(try screen.details().value("REST") == "1 min")
        try screen.step("REST", .upward, times: 2)
        #expect(try screen.content().row("4B").sub.hasSuffix("1:30 rest"))
        // Raising the first member's rest changes the last row too, as it changes the minutes.
        try screen.open("4A")
        try screen.step("REST", .upward, times: 3)
        #expect(try screen.content().row("4A").sub.hasSuffix("no rest"))
        #expect(try screen.content().row("4B").sub.hasSuffix("2 min rest"))
    }

    @Test("Three exercises back to back are lettered A, B and C, and only C rests")
    func superset_ofThree_lettersAndRests() throws {
        let slots = try [
            DayEditorFixtures.slot(1), DayEditorFixtures.slot(2, superset: true),
            DayEditorFixtures.slot(3, superset: true)
        ]
        let content = try DayEditorPresentation.make(DayEditorFixtures.input(slots: slots)).content()
        #expect(content.indices == "1A · 1B · 1C")
        #expect(content.supersetNotes == ["3 exercises back to back · rest after C"])
        #expect(content.rows.map { $0.sub.hasSuffix("no rest") } == [true, true, false])
    }

    @Test("Move down on an exercise above a superset carries it below the whole superset (criterion 10)")
    func moveDown_soloAboveASuperset_passesTheWholeSuperset() throws {
        var screen = try DayScreen(DayEditorFixtures.input(slots: DayEditorFixtures.fiveWithASuperset()))
        #expect(try screen.content().indices == "1 · 2 · 3A · 3B · 4")
        try screen.open("2")
        try screen.tap(screen.panel().moveDown?.action)
        #expect(try screen.content().order == [
            "1 Barbell Bench Press", "2A Lat Pulldown", "2B Cable Lateral Raise", "3 Incline DB Press",
            "4 Barbell Curl"
        ].joined(separator: " · "))
        // The moved exercise stays open.
        #expect(try screen.content().row("3").isOpen)
    }

    @Test("Move down on the first of a superset swaps it with the second, and the letters follow the new order")
    func moveDown_insideASuperset_swapsAndReletters() throws {
        var screen = try DayScreen(DayEditorFixtures.input(slots: DayEditorFixtures.fiveWithASuperset()))
        try screen.open("3A")
        try screen.tap(screen.panel().moveDown?.action)
        #expect(try screen.content().order == [
            "1 Barbell Bench Press", "2 Incline DB Press", "3A Cable Lateral Raise", "3B Lat Pulldown",
            "4 Barbell Curl"
        ].joined(separator: " · "))
        #expect(try screen.content().row("3B").isOpen)
        #expect(try screen.content().supersetNotes == ["2 exercises back to back · rest after B"])
        #expect(try screen.content().row("3A").sub.hasSuffix("no rest"))
    }

    @Test("Move up on the first of a superset carries the whole superset above the exercise before it")
    func moveUp_firstOfASuperset_carriesTheSuperset() throws {
        var screen = try DayScreen(DayEditorFixtures.input(slots: DayEditorFixtures.fiveWithASuperset()))
        try screen.open("3A")
        try screen.tap(screen.panel().moveUp?.action)
        #expect(try screen.content().order == [
            "1 Barbell Bench Press", "2A Lat Pulldown", "2B Cable Lateral Raise", "3 Incline DB Press",
            "4 Barbell Curl"
        ].joined(separator: " · "))
        // The first of every group is joined to nothing, as the Domain's normal form has it.
        let flags = try #require(screen.day).slots.map(\.isSupersetWithPrevious)
        #expect(flags == [false, false, true, false, false])
    }

    @Test("A move is offered only where it changes the day: not up from the top, not down from the foot")
    func moves_atTheDaysEdges_areNotOffered() throws {
        var screen = try DayScreen(DayEditorFixtures.input(slots: DayEditorFixtures.fiveWithASuperset()))
        try screen.open("1")
        #expect(try screen.panel().actionLine == "Superset with next · Move down · Remove")
        try screen.open("4")
        #expect(try screen.panel().actionLine == "Move up · Remove")
        // Inside a superset both members can move: one swaps, the other carries the superset.
        try screen.open("3A")
        #expect(try screen.panel().actionLine == "Move up · Move down · Remove")
        try screen.open("3B")
        #expect(try screen.panel().actionLine == "Break out · Superset with next · Move up · Move down · Remove")
    }

    @Test("Superset with next joins the next exercise, heads the pair and closes the panel (criterion 11)")
    func supersetWithNext_joinsTheNextExercise() throws {
        let catalog = Fixtures.CatalogID.self
        let slots = try [
            DayEditorFixtures.slot(1), DayEditorFixtures.slot(2, catalog.inclineDBPress),
            DayEditorFixtures.slot(3, catalog.chestSupportedRow), DayEditorFixtures.slot(4, catalog.latPulldown),
            DayEditorFixtures.slot(5, catalog.cableLateralRaise)
        ]
        var screen = try DayScreen(DayEditorFixtures.input(slots: slots))
        #expect(try screen.content().supersetNotes == [])
        try screen.open("4")
        #expect(try screen.panel().supersetActions.map(\.title) == ["Superset with next"])
        try screen.tap(screen.panel().supersetAction("Superset with next"))
        let content = try screen.content()
        #expect(try #require(screen.day).slots.map(\.isSupersetWithPrevious) == [false, false, false, false, true])
        #expect(content.indices == "1 · 2 · 3 · 4A · 4B")
        #expect(content.supersetNotes == ["2 exercises back to back · rest after B"])
        #expect(try content.row("4A").sub == "Cable · +2.5/wk · RPE 8 · no rest")
        #expect(try content.row("4B").sub == "Cable · +2.5/wk · RPE 8 · 1:30 rest")
        #expect(content.rows.allSatisfy { !$0.isOpen })
    }

    @Test("Break out on B detaches it, and the header goes with the superset")
    func breakOut_detachesTheExercise() throws {
        var screen = try DayScreen(DayEditorFixtures.seedInput())
        try screen.open("4A")
        #expect(try screen.panel().supersetActions.map(\.title) == [])
        try screen.open("4B")
        #expect(try screen.panel().supersetActions.map(\.title) == ["Break out"])
        try screen.tap(screen.panel().supersetAction("Break out"))
        #expect(try screen.content().indices == "1 · 2 · 3 · 4 · 5")
        #expect(try screen.content().supersetNotes == [])
        #expect(try screen.content().rows.allSatisfy { !$0.isOpen })
        #expect(try screen.content().row("4").sub == "Cable · Reps 12–14 · RPE 9 · 1:15 rest")
    }

    @Test("Superset with next on the last of a superset makes the two groups one (behaviour 9)")
    func supersetWithNext_beforeAnotherSuperset_mergesTheTwo() throws {
        let slots = try [
            DayEditorFixtures.slot(1), DayEditorFixtures.slot(2, superset: true), DayEditorFixtures.slot(3),
            DayEditorFixtures.slot(4, superset: true)
        ]
        var screen = try DayScreen(DayEditorFixtures.input(slots: slots))
        #expect(try screen.content().indices == "1A · 1B · 2A · 2B")
        try screen.open("1B")
        try screen.tap(screen.panel().supersetAction("Superset with next"))
        #expect(try screen.content().indices == "1A · 1B · 1C · 1D")
        #expect(try screen.content().supersetNotes == ["4 exercises back to back · rest after D"])
    }

    @Test("Remove takes the exercise out and closes the panel; the next member leads what is left (behaviour 7)")
    func remove_firstOfASuperset_theNextMemberLeads() throws {
        var screen = try DayScreen(DayEditorFixtures.input(slots: DayEditorFixtures.fiveWithASuperset()))
        try screen.open("3A")
        #expect(try screen.panel().remove.title == "Remove")
        try screen.tap(screen.panel().remove.action)
        #expect(try screen.content().order == [
            "1 Barbell Bench Press", "2 Incline DB Press", "3 Cable Lateral Raise", "4 Barbell Curl"
        ].joined(separator: " · "))
        #expect(screen.input.openSlot == nil)
        #expect(try screen.content().header.meta.hasPrefix("Week 1 · 4 exercises · 12 sets"))
    }
}
