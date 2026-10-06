import Foundation
@testable import LedgerDomain
import Testing

/// The brief's criteria 2 to 6 as the plan restates them ("Inputs the implementer needs › S1", "The criteria
/// as input → output"), value for value, on the spec's seed schedule built here.
@Suite("ProgramEditing worked examples (adversarial)", .tags(.domain))
struct ProgramEditingExamplesAdversarialTests {
    let program: Program
    let ids = EditAdv.fourDayIDs

    init() throws {
        program = try EditAdv.fourDayProgram()
    }

    /// How many weekdays each week trains.
    static func counts(_ program: Program) -> [Int] {
        program.weeks.map(\.schedule.count)
    }

    static func deloads(_ program: Program) -> [Bool] {
        program.weeks.map(\.isDeload)
    }
}

// MARK: - Criteria 2 and 3: the schedule

extension ProgramEditingExamplesAdversarialTests {
    @Test("Criterion 2: Tuesday of week 1 goes UA, LA, UB, LB, then rest; the week trains 5, 5, 5, 5, 4 days.")
    func cycleSchedule_fiveTaps_visitsEveryDayThenRest() {
        var current = program
        var seen: [DayTemplateID?] = []
        var trained: [Int] = []
        for _ in 1 ... 5 {
            current = ProgramEditing.cycleSchedule(current, week: 0, weekday: .tuesday)
            seen.append(current.weeks[0].schedule[.tuesday])
            trained.append(current.weeks[0].schedule.count)
        }
        #expect(seen == [ids[0], ids[1], ids[2], ids[3], nil])
        #expect(trained == [5, 5, 5, 5, 4])
        let backWhereItStarted = current == program
        #expect(backWhereItStarted)
    }

    @Test("Criterion 2: a tap changes that weekday of that week and nothing else.")
    func cycleSchedule_oneTap_touchesOneCell() {
        let tapped = ProgramEditing.cycleSchedule(program, week: 3, weekday: .sunday)
        var expected = program
        expected.weeks[3].schedule[.sunday] = ids[0]
        let onlyThatCell = tapped == expected
        #expect(onlyThatCell)
    }

    @Test("Criterion 2: a weekday that trains the last day goes to rest, and one that trains the first to the second.")
    func cycleSchedule_fromAnAssignedDay_goesToTheNext() {
        let saturday = ProgramEditing.cycleSchedule(program, week: 0, weekday: .saturday)
        #expect(saturday.weeks[0].schedule[.saturday] == nil)
        #expect(saturday.weeks[0].schedule.count == 3)
        let monday = ProgramEditing.cycleSchedule(program, week: 0, weekday: .monday)
        #expect(monday.weeks[0].schedule[.monday] == ids[1])
    }

    @Test("Criterion 3: week 3 takes week 2's schedule, keeps its flag, and no other week changes.")
    func copyPreviousWeek_takesTheWeekBefore() {
        let edited = ProgramEditing.cycleSchedule(program, week: 1, weekday: .tuesday)
        let copied = ProgramEditing.copyPreviousWeek(edited, week: 2)
        #expect(copied.weeks[2].schedule == edited.weeks[1].schedule)
        #expect(copied.weeks[2].schedule[.tuesday] == ids[0])
        var expected = edited
        expected.weeks[2].schedule = edited.weeks[1].schedule
        let onlyWeekThree = copied == expected
        #expect(onlyWeekThree)
    }

    @Test("Criterion 3: the deload week copies week 7's four days and stays the deload.")
    func copyPreviousWeek_ontoTheDeloadWeek_keepsTheFlag() {
        let copied = ProgramEditing.copyPreviousWeek(program, week: 7)
        #expect(copied.weeks[7].schedule == program.weeks[6].schedule)
        #expect(copied.weeks[7].schedule.count == 4)
        #expect(Self.deloads(copied) == Self.deloads(program))
    }

    @Test("Behaviour 3: \"Copy week n − 1\" on the first week changes nothing.")
    func copyPreviousWeek_onTheFirstWeek_changesNothing() {
        let edited = ProgramEditing.cycleSchedule(program, week: 0, weekday: .sunday)
        let unchanged = ProgramEditing.copyPreviousWeek(edited, week: 0) == edited
        #expect(unchanged)
    }

    @Test("Criterion 3: weeks 4 to 8 take week 3's schedule; week 8 is still the only deload and trains five days.")
    func applyToLaterWeeks_copiesForwardAndLeavesTheFlags() {
        let third = ProgramEditing.cycleSchedule(program, week: 2, weekday: .tuesday)
        let applied = ProgramEditing.applyToLaterWeeks(third, week: 2)
        let schedule = third.weeks[2].schedule
        #expect(schedule.count == 5)
        #expect(applied.weeks[3...].allSatisfy { $0.schedule == schedule })
        #expect(applied.weeks[7].schedule[.saturday] == ids[3])
        #expect(applied.weeks[7].schedule[.tuesday] == ids[0])
        #expect(Self.deloads(applied) == [false, false, false, false, false, false, false, true])
        #expect(Self.counts(applied) == [4, 4, 5, 5, 5, 5, 5, 5])
        #expect(applied.weeks.map(\.id) == program.weeks.map(\.id))
    }

    @Test("\"Apply to later weeks\" on the last week changes nothing, and on the first week reaches every week.")
    func applyToLaterWeeks_atTheEnds() {
        let unchanged = ProgramEditing.applyToLaterWeeks(program, week: 7) == program
        #expect(unchanged)
        let first = ProgramEditing.cycleSchedule(program, week: 0, weekday: .sunday)
        let applied = ProgramEditing.applyToLaterWeeks(first, week: 0)
        #expect(applied.weeks.allSatisfy { $0.schedule == first.weeks[0].schedule })
        #expect(Self.deloads(applied) == Self.deloads(program))
    }

    @Test("Criterion 3: \"Deload\" flips week 3 alone, and a second tap flips it back.")
    func toggleDeload_flipsOneWeek() {
        let toggled = ProgramEditing.toggleDeload(program, week: 2)
        #expect(Self.deloads(toggled) == [false, false, true, false, false, false, false, true])
        let schedulesKept = toggled.weeks.map(\.schedule) == program.weeks.map(\.schedule)
        #expect(schedulesKept)
        let back = ProgramEditing.toggleDeload(toggled, week: 2) == program
        #expect(back)
        #expect(Self.deloads(ProgramEditing.toggleDeload(program, week: 7)).allSatisfy { !$0 })
    }
}

// MARK: - Criterion 4: weeks

extension ProgramEditingExamplesAdversarialTests {
    @Test(
        "Criterion 4: a two-week block throws minimumTwoWeeks whatever the logged weeks hold.",
        arguments: [[], [0], [1], [0, 1], [2], [-1, 7]] as [Set<Int>]
    )
    func removeLastWeek_twoWeeks_throwsMinimumFirst(logged: Set<Int>) throws {
        let short = try EditAdv.fourDayProgram(weekCount: 2)
        #expect(throws: ProgramEditError.minimumTwoWeeks) {
            try ProgramEditing.removeLastWeek(short, loggedWeeks: logged)
        }
    }

    @Test("Criterion 4: a logged last week throws weekHasLoggedSessions with its one-based number.")
    func removeLastWeek_loggedLastWeek_throwsItsNumber() throws {
        #expect(throws: ProgramEditError.weekHasLoggedSessions(weekNumber: 8)) {
            try ProgramEditing.removeLastWeek(program, loggedWeeks: [7])
        }
        #expect(throws: ProgramEditError.weekHasLoggedSessions(weekNumber: 8)) {
            try ProgramEditing.removeLastWeek(program, loggedWeeks: [0, 7, 8, 99])
        }
        let three = try EditAdv.fourDayProgram(weekCount: 3)
        #expect(throws: ProgramEditError.weekHasLoggedSessions(weekNumber: 3)) {
            try ProgramEditing.removeLastWeek(three, loggedWeeks: [2])
        }
    }

    @Test("Criterion 4: with weeks 1 and 4 logged the last week is dropped, and the first seven are as they were.")
    func removeLastWeek_otherWeeksLogged_dropsTheLast() throws {
        let shorter = try ProgramEditing.removeLastWeek(program, loggedWeeks: [0, 3])
        #expect(shorter.weeks.count == 7)
        var expected = program
        expected.weeks.removeLast()
        let firstSevenKept = shorter == expected
        #expect(firstSevenKept)
        let outside = try ProgramEditing.removeLastWeek(program, loggedWeeks: [8, 9, -1])
        #expect(outside.weeks.count == 7)
    }

    @Test("Criterion 4: three weeks go down to two, and the next \"−\" throws.")
    func removeLastWeek_downToTwo_thenThrows() throws {
        let three = try EditAdv.fourDayProgram(weekCount: 3)
        let two = try ProgramEditing.removeLastWeek(three, loggedWeeks: [])
        #expect(two.weeks.map(\.index) == [0, 1])
        #expect(throws: ProgramEditError.minimumTwoWeeks) {
            try ProgramEditing.removeLastWeek(two, loggedWeeks: [])
        }
    }

    @Test("Criterion 4: \"+\" appends week 9 with week 8's three days, not a deload, under the id given.")
    func addWeek_copiesTheLastWeek_notItsDeload() {
        let longer = ProgramEditing.addWeek(program, id: EditAdv.weekID(208))
        #expect(longer.weeks.count == 9)
        #expect(longer.weeks.map(\.index) == Array(0 ... 8))
        #expect(longer.weeks[8].id == EditAdv.weekID(208))
        #expect(longer.weeks[8].schedule == program.weeks[7].schedule)
        #expect(longer.weeks[8].schedule.count == 3)
        #expect(longer.weeks[8].isDeload == false)
        var expected = longer
        expected.weeks.removeLast()
        let firstEightKept = expected == program
        #expect(firstEightKept)
    }

    @Test("\"+\" with an id a week already has adds nothing, wherever that week is.", arguments: [200, 203, 207])
    func addWeek_idInUse_addsNothing(number: Int) {
        let unchanged = ProgramEditing.addWeek(program, id: EditAdv.weekID(number)) == program
        #expect(unchanged)
    }

    @Test("A week added and then removed leaves the block as it was.")
    func addWeek_thenRemoveLastWeek_restores() throws {
        let longer = ProgramEditing.addWeek(program, id: EditAdv.weekID(208))
        let restored = try ProgramEditing.removeLastWeek(longer, loggedWeeks: [7]) == program
        #expect(restored)
    }
}

// MARK: - Criteria 5 and 6: days

extension ProgramEditingExamplesAdversarialTests {
    @Test("Criterion 5: the added day is \"New day\", tagged D5, with no slots, and no schedule changes.")
    func addDay_appendsD5() {
        let added = ProgramEditing.addDay(program, id: EditAdv.dayID(340), name: "New day")
        #expect(added.days.count == 5)
        #expect(added.days.map(\.id) == ids + [EditAdv.dayID(340)])
        #expect(added.days[4].name == "New day")
        #expect(added.days[4].tag == "D5")
        #expect(added.days[4].slots.isEmpty)
        let weeksKept = added.weeks == program.weeks
        #expect(weeksKept)
        #expect(added.days.prefix(4).map(\.tag) == ["UA", "LA", "UB", "LB"])
    }

    @Test("Criterion 6: Lower B is removed, no week has a Saturday entry, and weeks 1 to 7 train three days.")
    func deleteDay_removesEveryScheduleEntry() {
        let deleted = ProgramEditing.deleteDay(program, day: ids[3])
        #expect(deleted.days.map(\.id) == Array(ids.prefix(3)))
        #expect(deleted.weeks.allSatisfy { $0.schedule[.saturday] == nil })
        #expect(Self.counts(deleted) == [3, 3, 3, 3, 3, 3, 3, 3])
        #expect(Self.deloads(deleted) == Self.deloads(program))
        #expect(EditAdv.rejection(of: deleted) == nil)
    }

    @Test("Criterion 6: a day scheduled on two weekdays of a week leaves both at rest.")
    func deleteDay_scheduledTwiceInAWeek_clearsBoth() {
        let twice = ProgramEditing.cycleSchedule(program, week: 0, weekday: .tuesday)
        let deleted = ProgramEditing.deleteDay(twice, day: ids[0])
        #expect(deleted.weeks[0].schedule[.monday] == nil)
        #expect(deleted.weeks[0].schedule[.tuesday] == nil)
        #expect(deleted.weeks[0].schedule.count == 3)
        #expect(EditAdv.rejection(of: deleted) == nil)
    }
}
