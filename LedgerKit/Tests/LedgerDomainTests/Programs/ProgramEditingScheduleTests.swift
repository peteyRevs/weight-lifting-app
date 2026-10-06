import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criterion 4 (F11 criteria 2 and 3): cycling a weekday, "Copy week n − 1" and "Apply to later
/// weeks", on the spec's seed block (`Fixtures.fourDayProgram()`).
@Suite("ProgramEditing · schedule", .tags(.domain))
struct ProgramEditingScheduleTests {
    private typealias Support = EditingTestSupport

    let program: Program

    init() throws {
        program = try Fixtures.fourDayProgram()
    }

    @Test("A weekday cycles rest, UA, LA, UB, LB, rest: the days in the program's order (rule 5, F11 criterion 2)")
    func cycleSchedule_restThenEachDayThenRest() {
        var cycled = program
        var tuesdays: [String] = []
        var counts: [Int] = []
        for _ in 1 ... 5 {
            cycled = ProgramEditing.cycleSchedule(cycled, week: 0, weekday: .tuesday)
            tuesdays.append(ProgramEditingTests.strip(cycled, week: 0)[1])
            counts.append(cycled.weeks[0].schedule.count)
        }
        #expect(tuesdays == ["UA", "LA", "UB", "LB", "REST"])
        #expect(counts == [5, 5, 5, 5, 4])
        #expect(Support.difference(cycled, program).isEmpty, "five taps come back to the start")
    }

    @Test("A weekday that trains a day goes to the next day, and only that cell changes")
    func cycleSchedule_fromADay_goesToTheNext() {
        let once = ProgramEditing.cycleSchedule(program, week: 3, weekday: .monday)
        #expect(ProgramEditingTests.strip(once, week: 3) == ["LA", "REST", "LA", "REST", "UB", "LB", "REST"])
        let saturday = ProgramEditing.cycleSchedule(program, week: 3, weekday: .saturday)
        #expect(
            ProgramEditingTests.strip(saturday, week: 3) == ["UA", "REST", "LA", "REST", "UB", "REST", "REST"],
            "the last day → rest"
        )
        #expect(ProgramEditingTests.strip(once, week: 2) == ProgramEditingTests.trainingWeek)
        #expect(ProgramEditingTests.strip(once, week: 4) == ProgramEditingTests.trainingWeek)
        #expect(Support.faults(in: once).isEmpty)
    }

    @Test("With no day to assign, a weekday stays at rest")
    func cycleSchedule_noDays_changesNothing() throws {
        let empty = try Program(
            id: Fixtures.programID,
            name: "Empty",
            startDate: Fixtures.civil(2026, 8, 17),
            weeks: [Fixtures.week(0), Fixtures.week(1)],
            days: []
        )
        let cycled = ProgramEditing.cycleSchedule(empty, week: 0, weekday: .friday)
        #expect(cycled.weeks[0].schedule.isEmpty)
        #expect(Support.difference(cycled, empty).isEmpty)
    }

    @Test("With one day, a weekday goes rest, the day, rest")
    func cycleSchedule_oneDay_alternates() {
        var single = program
        for day in Fixtures.fourDayIDs.dropFirst() {
            single = ProgramEditing.deleteDay(single, day: day)
        }
        let once = ProgramEditing.cycleSchedule(single, week: 1, weekday: .sunday)
        #expect(once.weeks[1].schedule[.sunday] == Fixtures.fourDayIDs[0])
        let twice = ProgramEditing.cycleSchedule(once, week: 1, weekday: .sunday)
        #expect(twice.weeks[1].schedule[.sunday] == nil)
        #expect(Support.difference(twice, single).isEmpty)
    }

    @Test("\"Copy week 2\" gives week 3 the schedule of week 2 and keeps week 3's own flag (F11 criterion 3)")
    func copyPreviousWeek_takesTheScheduleOnly() {
        var edited = ProgramEditing.cycleSchedule(program, week: 1, weekday: .tuesday)
        edited = ProgramEditing.toggleDeload(edited, week: 1)
        let copied = ProgramEditing.copyPreviousWeek(edited, week: 2)
        #expect(ProgramEditingTests.strip(copied, week: 2) == ["UA", "UA", "LA", "REST", "UB", "LB", "REST"])
        #expect(copied.weeks[2].schedule == copied.weeks[1].schedule)
        #expect(copied.weeks.map(\.isDeload) == [false, true, false, false, false, false, false, true])
        #expect(
            ProgramEditingTests.strip(copied, week: 3) == ProgramEditingTests.trainingWeek,
            "later weeks are untouched"
        )
        let intoDeload = ProgramEditing.copyPreviousWeek(program, week: 7)
        #expect(ProgramEditingTests.strip(intoDeload, week: 7) == ProgramEditingTests.trainingWeek)
        #expect(intoDeload.weeks[7].isDeload)
    }

    @Test("\"Copy week 1\" gives the second week the first week's schedule")
    func copyPreviousWeek_onTheSecondWeek_takesTheFirstWeeks() {
        let edited = ProgramEditing.cycleSchedule(program, week: 0, weekday: .sunday)
        let copied = ProgramEditing.copyPreviousWeek(edited, week: 1)
        #expect(ProgramEditingTests.strip(copied, week: 1) == ["UA", "REST", "LA", "REST", "UB", "LB", "UA"])
        #expect(ProgramEditingTests.strip(copied, week: 2) == ProgramEditingTests.trainingWeek)
    }

    @Test("\"Copy\" on the first week changes nothing: there is no week before it")
    func copyPreviousWeek_onTheFirstWeek_changesNothing() {
        let edited = ProgramEditing.cycleSchedule(program, week: 0, weekday: .sunday)
        #expect(Support.difference(ProgramEditing.copyPreviousWeek(edited, week: 0), edited).isEmpty)
    }

    @Test(
        "\"Apply to later weeks\" copies week 3's schedule to weeks 4–8 and leaves every deload flag (F11 criterion 3)"
    )
    func applyToLaterWeeks_leavesTheDeloadFlags() {
        let edited = ProgramEditing.cycleSchedule(program, week: 2, weekday: .tuesday)
        let applied = ProgramEditing.applyToLaterWeeks(edited, week: 2)
        let weekThree = ["UA", "UA", "LA", "REST", "UB", "LB", "REST"]
        #expect((2 ..< 8).allSatisfy { ProgramEditingTests.strip(applied, week: $0) == weekThree })
        #expect(ProgramEditingTests.strip(applied, week: 7) == weekThree, "week 8 now trains Saturday and Tuesday too")
        #expect(applied.weeks.filter(\.isDeload).map(\.index) == [7], "week 8 is still the only deload")
        #expect(ProgramEditingTests.strip(applied, week: 0) == ProgramEditingTests.trainingWeek)
        #expect(ProgramEditingTests.strip(applied, week: 1) == ProgramEditingTests.trainingWeek)
        #expect(Support.faults(in: applied).isEmpty)
    }

    @Test("\"Apply to later weeks\" on the last week changes nothing")
    func applyToLaterWeeks_onTheLastWeek_changesNothing() {
        #expect(Support.difference(ProgramEditing.applyToLaterWeeks(program, week: 7), program).isEmpty)
    }

    @Test(
        "A week the block does not have leaves the program unchanged, for every function that takes a week",
        arguments: [-1, 8, 9, Int.max, Int.min]
    )
    func weekOutsideTheBlock_changesNothing(week: Int) {
        let results = [
            ProgramEditing.toggleDeload(program, week: week),
            ProgramEditing.cycleSchedule(program, week: week, weekday: .monday),
            ProgramEditing.copyPreviousWeek(program, week: week),
            ProgramEditing.applyToLaterWeeks(program, week: week)
        ]
        #expect(results.map { Support.difference($0, program) } == ["", "", "", ""])
    }
}
