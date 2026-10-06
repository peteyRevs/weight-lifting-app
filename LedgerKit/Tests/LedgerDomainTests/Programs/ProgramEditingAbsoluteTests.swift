import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S5, criterion 12: the edits of a cell and of a deload by what they become, and the one function
/// that holds the order of a cell's cycle, on the spec's seed block (`Fixtures.fourDayProgram()`). An edit by
/// what it becomes gives the same program applied once or twice, which the relative `cycleSchedule` and
/// `toggleDeload` do not.
@Suite("ProgramEditing · absolute edits", .tags(.domain))
struct ProgramEditingAbsoluteTests {
    private typealias Support = EditingTestSupport

    let program: Program

    init() throws {
        program = try Fixtures.fourDayProgram()
    }

    @Test("The cycle goes rest, UA, LA, UB, LB, rest: the days in the program's order (rule 5)")
    func nextInCycle_restThenEachDayThenRest() {
        let ids = Fixtures.fourDayIDs
        #expect(ProgramEditing.nextInCycle(after: nil, in: program) == ids[0])
        #expect(ProgramEditing.nextInCycle(after: ids[0], in: program) == ids[1])
        #expect(ProgramEditing.nextInCycle(after: ids[1], in: program) == ids[2])
        #expect(ProgramEditing.nextInCycle(after: ids[2], in: program) == ids[3])
        #expect(ProgramEditing.nextInCycle(after: ids[3], in: program) == nil)
    }

    @Test("An entry that names a day the program does not hold cycles as rest does: to the first day")
    func nextInCycle_afterAMissingDay_isTheFirstDay() {
        let missing = DayTemplateID(Fixtures.uuid(999))
        #expect(ProgramEditing.nextInCycle(after: missing, in: program) == Fixtures.fourDayIDs[0])
    }

    @Test("With no day, the cycle stays at rest; with one, it goes rest, the day, rest")
    func nextInCycle_noDayAndOneDay() {
        var empty = program
        empty.weeks = empty.weeks.map { Week(id: $0.id, index: $0.index, isDeload: $0.isDeload) }
        empty.days = []
        #expect(ProgramEditing.nextInCycle(after: nil, in: empty) == nil)
        #expect(ProgramEditing.nextInCycle(after: Fixtures.fourDayIDs[0], in: empty) == nil)
        var single = empty
        single.days = [program.days[1]]
        #expect(ProgramEditing.nextInCycle(after: nil, in: single) == program.days[1].id)
        #expect(ProgramEditing.nextInCycle(after: program.days[1].id, in: single) == nil)
    }

    @Test("A weekday is set to a day, and only that cell changes; set again, nothing more changes")
    func setSchedule_toADay_changesThatCellOnce() {
        let lowerB = Fixtures.fourDayIDs[3]
        let once = ProgramEditing.setSchedule(program, week: 2, weekday: .tuesday, day: lowerB)
        #expect(ProgramEditingTests.strip(once, week: 2) == ["UA", "LB", "LA", "REST", "UB", "LB", "REST"])
        #expect(ProgramEditingTests.strip(once, week: 1) == ProgramEditingTests.trainingWeek)
        #expect(ProgramEditingTests.strip(once, week: 3) == ProgramEditingTests.trainingWeek)
        #expect(once.weeks.map(\.isDeload) == program.weeks.map(\.isDeload))
        let twice = ProgramEditing.setSchedule(once, week: 2, weekday: .tuesday, day: lowerB)
        #expect(Support.difference(twice, once).isEmpty)
        #expect(Support.faults(in: once).isEmpty)
    }

    @Test("A weekday set to rest loses its entry: rest is the absence of a key")
    func setSchedule_toRest_removesTheEntry() {
        let rested = ProgramEditing.setSchedule(program, week: 0, weekday: .monday, day: nil)
        #expect(ProgramEditingTests.strip(rested, week: 0) == ["REST", "REST", "LA", "REST", "UB", "LB", "REST"])
        #expect(rested.weeks[0].schedule.count == 3)
        #expect(rested.weeks[0].schedule.keys.contains(.monday) == false)
        // A weekday already at rest stays as it is.
        let again = ProgramEditing.setSchedule(rested, week: 0, weekday: .monday, day: nil)
        #expect(Support.difference(again, rested).isEmpty)
    }

    @Test("A day the program does not hold changes nothing, and neither does a week the block does not have")
    func setSchedule_unknownDayOrWeek_changesNothing() {
        let missing = DayTemplateID(Fixtures.uuid(999))
        let results = [
            ProgramEditing.setSchedule(program, week: 0, weekday: .tuesday, day: missing),
            ProgramEditing.setSchedule(program, week: -1, weekday: .tuesday, day: Fixtures.fourDayIDs[0]),
            ProgramEditing.setSchedule(program, week: 8, weekday: .tuesday, day: Fixtures.fourDayIDs[0]),
            ProgramEditing.setSchedule(program, week: Int.max, weekday: .monday, day: nil),
            ProgramEditing.setSchedule(program, week: Int.min, weekday: .monday, day: nil)
        ]
        #expect(results.map { Support.difference($0, program) } == ["", "", "", "", ""])
    }

    @Test("Setting a weekday to the next value of its cycle is what cycling it does, for every cell of the block")
    func setSchedule_toTheNextInCycle_isCycleSchedule() {
        var differences: [String] = []
        for week in program.weeks.indices {
            for weekday in Weekday.allCases {
                let next = ProgramEditing.nextInCycle(after: program.weeks[week].schedule[weekday], in: program)
                let set = ProgramEditing.setSchedule(program, week: week, weekday: weekday, day: next)
                let cycled = ProgramEditing.cycleSchedule(program, week: week, weekday: weekday)
                differences.append(Support.difference(set, cycled))
            }
        }
        #expect(differences.count == 56)
        #expect(Set(differences) == [""])
    }

    @Test("A deload is set on or off for one week, and set again it stays")
    func setDeload_setsOneWeek_andStays() {
        let deloaded = ProgramEditing.setDeload(program, true, week: 2)
        #expect(deloaded.weeks.filter(\.isDeload).map(\.index) == [2, 7])
        #expect(ProgramEditingTests.strip(deloaded, week: 2) == ProgramEditingTests.trainingWeek)
        #expect(Support.difference(ProgramEditing.setDeload(deloaded, true, week: 2), deloaded).isEmpty)
        let cleared = ProgramEditing.setDeload(deloaded, false, week: 7)
        #expect(cleared.weeks.filter(\.isDeload).map(\.index) == [2])
        #expect(Support.difference(ProgramEditing.setDeload(cleared, false, week: 7), cleared).isEmpty)
        // The state a week already has changes nothing; toggling is setting the other state.
        #expect(Support.difference(ProgramEditing.setDeload(program, true, week: 7), program).isEmpty)
        #expect(Support.difference(
            ProgramEditing.setDeload(program, true, week: 2),
            ProgramEditing.toggleDeload(program, week: 2)
        ).isEmpty)
    }

    @Test("A week the block does not have leaves the deload flags as they are", arguments: [-1, 8, Int.max, Int.min])
    func setDeload_weekOutsideTheBlock_changesNothing(week: Int) {
        #expect(Support.difference(ProgramEditing.setDeload(program, true, week: week), program).isEmpty)
        #expect(Support.difference(ProgramEditing.setDeload(program, false, week: week), program).isEmpty)
    }
}
