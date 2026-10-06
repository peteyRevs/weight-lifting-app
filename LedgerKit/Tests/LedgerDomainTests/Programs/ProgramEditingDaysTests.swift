import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criterion 5: adding, renaming, deleting and updating a training day, on the spec's seed
/// block (`Fixtures.fourDayProgram()`).
@Suite("ProgramEditing · days", .tags(.domain))
struct ProgramEditingDaysTests {
    private typealias Support = EditingTestSupport

    let program: Program
    let newDay = DayTemplateID(Fixtures.uuid(340))
    let lowerB = Fixtures.fourDayIDs[3]

    init() throws {
        program = try Fixtures.fourDayProgram()
    }

    @Test("\"+ Add training day\" appends \"New day\", tagged D5, with no slots, and no schedule changes (rule 8)")
    func addDay_isNamedAndTaggedByCount_withNoSlots() throws {
        let added = ProgramEditing.addDay(program, id: newDay, name: "New day")
        #expect(added.days.map(\.tag) == ["UA", "LA", "UB", "LB", "D5"])
        let day = try #require(added.days.last)
        #expect(day.id == newDay)
        #expect(day.name == "New day")
        #expect(day.slots.map(\.id) == [])
        let sameWeeks = added.weeks == program.weeks
        #expect(sameWeeks, "no schedule changed")
        #expect(Support.faults(in: added).isEmpty)
        #expect(ProgramEditing.addDay(program, id: newDay, name: " Arms\u{0} \n").days.last?.name == "Arms")
    }

    @Test("A new day's tag skips the numbers in use: after a deletion D5 is taken, so the next is D6")
    func addDay_tagSkipsNumbersInUse() {
        var edited = ProgramEditing.addDay(program, id: newDay, name: "New day")
        edited = ProgramEditing.deleteDay(edited, day: lowerB)
        #expect(edited.days.map(\.tag) == ["UA", "LA", "UB", "D5"])
        edited = ProgramEditing.addDay(edited, id: DayTemplateID(Fixtures.uuid(350)), name: "New day")
        #expect(edited.days.map(\.tag) == ["UA", "LA", "UB", "D5", "D6"])
        edited = ProgramEditing.addDay(edited, id: DayTemplateID(Fixtures.uuid(360)), name: "New day")
        #expect(edited.days.map(\.tag) == ["UA", "LA", "UB", "D5", "D6", "D7"], "three tags taken above the count")
        #expect(Support.faults(in: edited).isEmpty)
    }

    @Test("The first day of a program with none is D1")
    func addDay_toAProgramWithNoDays_isTaggedD1() {
        var empty = program
        for day in Fixtures.fourDayIDs {
            empty = ProgramEditing.deleteDay(empty, day: day)
        }
        #expect(ProgramEditing.addDay(empty, id: newDay, name: "New day").days.map(\.tag) == ["D1"])
    }

    @Test("A blank name, or a day id the program already has, adds nothing")
    func addDay_blankNameOrIDInUse_addsNothing() {
        let blank = ProgramEditing.addDay(program, id: newDay, name: " \u{0}\n")
        let reused = ProgramEditing.addDay(program, id: lowerB, name: "New day")
        #expect(blank.days.count == 4)
        #expect(reused.days.count == 4)
        #expect(Support.difference(blank, program).isEmpty)
        #expect(Support.difference(reused, program).isEmpty)
    }

    @Test("Renaming a day stores the cleaned name and leaves its tag, its slots and the schedule")
    func renameDay_setsTheCleanedName() throws {
        let block = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let renamed = ProgramEditing.renameDay(block, day: block.days[0].id, to: "  Push\u{7} day ")
        #expect(renamed.days.map(\.name) == ["Push day", "Upper B — Pull focus"])
        var expected = block
        expected.days[0].name = "Push day"
        #expect(Support.difference(renamed, expected).isEmpty)
    }

    @Test("A blank day name is not stored, and a day the program lacks is not renamed")
    func renameDay_blank_changesNothing() {
        let blank = ProgramEditing.renameDay(program, day: lowerB, to: "\t \n")
        let unknown = ProgramEditing.renameDay(program, day: DayTemplateID(Support.unknown), to: "Arms")
        #expect(blank.days.map(\.name) == program.days.map(\.name))
        #expect(Support.difference(blank, program).isEmpty)
        #expect(Support.difference(unknown, program).isEmpty)
    }

    @Test("Deleting Lower B removes it and turns every Saturday into rest (F11 criterion 6)")
    func deleteDay_turnsItsScheduleEntriesIntoRest() {
        let deleted = ProgramEditing.deleteDay(program, day: lowerB)
        #expect(deleted.days.map(\.tag) == ["UA", "LA", "UB"])
        #expect(deleted.weeks.map { $0.schedule[.saturday] == nil } == Array(repeating: true, count: 8))
        #expect(deleted.weeks.map(\.schedule.count) == [3, 3, 3, 3, 3, 3, 3, 3])
        #expect((0 ..< 8).allSatisfy { ProgramEditingTests.strip(deleted, week: $0) == ProgramEditingTests.deloadWeek })
        #expect(deleted.weeks.map(\.isDeload) == program.weeks.map(\.isDeload))
        #expect(Support.faults(in: deleted).isEmpty)
    }

    @Test("A day scheduled twice in one week is cleared from both weekdays")
    func deleteDay_scheduledTwiceInAWeek_clearsBoth() {
        var edited = program
        for _ in 1 ... 4 {
            edited = ProgramEditing.cycleSchedule(edited, week: 0, weekday: .tuesday)
        }
        #expect(ProgramEditingTests.strip(edited, week: 0) == ["UA", "LB", "LA", "REST", "UB", "LB", "REST"])
        let deleted = ProgramEditing.deleteDay(edited, day: lowerB)
        #expect(ProgramEditingTests.strip(deleted, week: 0) == ProgramEditingTests.deloadWeek)
        #expect(Support.faults(in: deleted).isEmpty)
    }

    @Test("Every day can be deleted: the block is still one the model accepts, with rest on every weekday")
    func deleteDay_everyDay_leavesAValidProgram() {
        var edited = program
        for day in Fixtures.fourDayIDs {
            edited = ProgramEditing.deleteDay(edited, day: day)
        }
        #expect(edited.days.map(\.tag) == [])
        let everyWeekdayRests = edited.weeks.allSatisfy(\.schedule.isEmpty)
        #expect(everyWeekdayRests)
        #expect(edited.weeks.count == 8)
        #expect(Support.faults(in: edited).isEmpty)
    }

    @Test("Deleting a day the program does not hold changes nothing")
    func deleteDay_unknownDay_changesNothing() {
        let deleted = ProgramEditing.deleteDay(program, day: DayTemplateID(Support.unknown))
        #expect(Support.difference(deleted, program).isEmpty)
    }

    @Test("updateDay replaces one day by the change's result, in its place")
    func updateDay_replacesTheDay() throws {
        let block = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let bench = SlotID(Fixtures.uuid(301))
        let updated = ProgramEditing.updateDay(block, day: block.days[0].id) { DayEditing.removeSlot($0, slot: bench) }
        #expect(updated.days.map(\.slots.count) == [4, 1])
        #expect(updated.days[0].slots.map(\.id) == [302, 303, 304, 305].map { SlotID(Fixtures.uuid($0)) })
        let sameWeeks = updated.weeks == block.weeks
        #expect(sameWeeks, "no week changed")
        #expect(Support.faults(in: updated).isEmpty)
    }

    @Test("A change that returns a day with another id is ignored")
    func updateDay_resultWithAnotherID_isIgnored() throws {
        let other = try Fixtures.upperB()
        let updated = ProgramEditing.updateDay(program, day: lowerB) { _ in other }
        #expect(updated.days.map(\.id) == Fixtures.fourDayIDs)
        #expect(Support.difference(updated, program).isEmpty)
    }

    @Test("updateDay on a day the program does not hold changes nothing and never calls the change")
    func updateDay_unknownDay_changesNothing() {
        var calls = 0
        let updated = ProgramEditing.updateDay(program, day: DayTemplateID(Support.unknown)) { day in
            calls += 1
            return day
        }
        #expect(calls == 0)
        #expect(Support.difference(updated, program).isEmpty)
    }
}
