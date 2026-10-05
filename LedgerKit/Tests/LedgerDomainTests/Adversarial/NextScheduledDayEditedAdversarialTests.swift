import Foundation
@testable import LedgerDomain
import Testing

/// F09 S2 criterion 1 on programs a validated `Program` cannot be built as but can be edited into
/// (`weeks` and `days` are `var`s): no weeks, one week, repeated or scattered week indices, a
/// schedule naming a template that is gone. "Each candidate day is judged … as
/// `scheduledDay(on:in:)` judges it", and the block is `weeks.count` weeks long as
/// `isBlockComplete` counts it, so the expected answer is the walking reference's.
@Suite("WeekCalendar.nextScheduledDay on edited programs (adversarial, F09 S2)", .tags(.domain))
struct NextScheduledDayEditedAdversarialTests {
    typealias Support = ScheduleAdversarial

    /// Asserts the product against the day-by-day walk for noon of every day around the block.
    static func expectWalk(_ program: Program, start: CivilDate = Support.seedStart, span: Int = 80) throws {
        let weeks = Support.weeks(start: start)
        let reference = try SessionReference(walking: program, with: weeks, in: Fixtures.utc)
        for offset in -10 ..< span {
            let moment = try Support.moment(#require(start.adding(days: offset)))
            let next = weeks.nextScheduledDay(after: moment, in: program)
            #expect(try next == reference.next(after: moment), "after \(moment)")
        }
    }
}

extension NextScheduledDayEditedAdversarialTests {
    @Test("A program with no weeks has no next session, before, on or after its start day.")
    func nextScheduledDay_programWithNoWeeks_isNil() throws {
        var program = try Support.seedProgram()
        program.weeks = []
        let weeks = Support.weeks()
        for offset in [-400, -1, 0, 1, 6, 7, 400] {
            let moment = try Support.moment(#require(Support.seedStart.adding(days: offset)))
            #expect(weeks.nextScheduledDay(after: moment, in: program) == nil)
        }
    }

    @Test("A program cut to one week answers inside that week and has nothing after its Saturday.")
    func nextScheduledDay_programCutToOneWeek_stopsAfterThatWeek() throws {
        var program = try Support.seedProgram()
        program.weeks = [program.weeks[0]]
        let weeks = Support.weeks()
        let friday = ScheduledDay(date: Fixtures.civil(2026, 9, 18), weekIndex: 0, dayTemplateID: Support.upperB.id)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 16)), in: program) == friday)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 19)), in: program) == nil)
        try Self.expectWalk(program)
    }

    @Test("Weeks with an empty schedule are passed over, and a block of only empty weeks has no next session.")
    func nextScheduledDay_emptyWeeks_arePassedOver() throws {
        var program = try Support.seedProgram()
        for index in [0, 2, 3, 6, 7] {
            program.weeks[index].schedule = [:]
        }
        let weeks = Support.weeks()
        // Weeks 1, 2 and 5, 6 (indices 0, 2, 3, 6, 7) are empty; week 2 starts Monday 2026-09-21.
        let first = ScheduledDay(date: Fixtures.civil(2026, 9, 21), weekIndex: 1, dayTemplateID: Support.upperA.id)
        let afterGap = ScheduledDay(date: Fixtures.civil(2026, 10, 12), weekIndex: 4, dayTemplateID: Support.upperA.id)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 1)), in: program) == first)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 14)), in: program) == first)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 26)), in: program) == afterGap)
        // The last session is Saturday 2026-10-24 (week index 5).
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 10, 24)), in: program) == nil)
        try Self.expectWalk(program)
        for index in program.weeks.indices {
            program.weeks[index].schedule = [:]
        }
        try Self.expectWalk(program)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 1)), in: program) == nil)
    }

    @Test("A schedule that names a template the program no longer has is answered as scheduledDay(on:in:) answers it.")
    func nextScheduledDay_danglingTemplate_isJudgedAsScheduledDayJudgesIt() throws {
        var program = try Support.seedProgram()
        program.days.removeAll { $0.id == Support.upperB.id }
        let weeks = Support.weeks()
        let wednesday = try Support.moment(Fixtures.civil(2026, 9, 16))
        let friday = try Support.moment(Fixtures.civil(2026, 9, 18))
        try #require(weeks.scheduledDay(on: friday, in: program) == Support.upperB.id)
        let expected = ScheduledDay(date: Fixtures.civil(2026, 9, 18), weekIndex: 0, dayTemplateID: Support.upperB.id)
        #expect(weeks.nextScheduledDay(after: wednesday, in: program) == expected)
        program.days = []
        try Self.expectWalk(program)
    }

    @Test("Weeks stored out of order are found by their index, as Program.week(at:) finds them.")
    func nextScheduledDay_weeksStoredOutOfOrder_areReadByIndex() throws {
        var program = try Support.seedProgram()
        let sorted = program
        program.weeks.reverse()
        let weeks = Support.weeks()
        for offset in -10 ..< 70 {
            let moment = try Support.moment(#require(Support.seedStart.adding(days: offset)))
            let next = weeks.nextScheduledDay(after: moment, in: program)
            #expect(next == weeks.nextScheduledDay(after: moment, in: sorted))
        }
        try Self.expectWalk(program)
    }

    @Test("Scattered week indices: a week whose index is past the block's length is outside the block.")
    func nextScheduledDay_scatteredWeekIndices_followTheWalk() throws {
        var program = try Support.seedProgram()
        program.weeks = [program.weeks[0], program.weeks[1], program.weeks[2]]
        program.weeks[1].index = 5
        program.weeks[2].index = -1
        try Self.expectWalk(program)
        // Three weeks long: week index 1 has no week, and index 5 is past the block's last week.
        let weeks = Support.weeks()
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 19)), in: program) == nil)
        #expect(try weeks.isBlockComplete(program, on: Support.moment(Fixtures.civil(2026, 10, 5))))
    }

    @Test("A week whose index equals the block's length is past the block, as isBlockComplete counts it.")
    func nextScheduledDay_weekIndexAtTheBlocksLength_isOutsideTheBlock() throws {
        var program = try Support.seedProgram()
        // Without its first week the block is seven weeks long and its weeks carry indices 1…7.
        program.weeks.removeFirst()
        let weeks = Support.weeks()
        let monday = ScheduledDay(date: Fixtures.civil(2026, 9, 21), weekIndex: 1, dayTemplateID: Support.upperA.id)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 1)), in: program) == monday)
        // The seventh week ends on Sunday 2026-11-01 and trains last on Saturday; index 7's Monday is past it.
        let saturday = ScheduledDay(date: Fixtures.civil(2026, 10, 31), weekIndex: 6, dayTemplateID: Support.lowerB.id)
        #expect(try weeks
            .nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 10, 30)), in: program) == saturday)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 10, 31)), in: program) == nil)
        let lastSecond = try Support.moment(Fixtures.civil(2026, 11, 1), 23, 59, 59)
        #expect(weeks.nextScheduledDay(after: lastSecond, in: program) == nil)
        #expect(try weeks.isBlockComplete(program, on: Support.moment(Fixtures.civil(2026, 11, 2))))
        try Self.expectWalk(program)
    }

    @Test("Two weeks with the same index: the first is read, as Program.week(at:) reads it.")
    func nextScheduledDay_repeatedWeekIndex_readsTheFirst() throws {
        var program = try Support.seedProgram()
        program.weeks[1].index = 0
        program.weeks[1].schedule = [.tuesday: Support.lowerB.id]
        let weeks = Support.weeks()
        // Tuesday 2026-09-15 stays a rest day, and the block's second week (index 1) has no week at all.
        let wednesday = ScheduledDay(date: Fixtures.civil(2026, 9, 16), weekIndex: 0, dayTemplateID: Support.lowerA.id)
        let thirdWeek = ScheduledDay(date: Fixtures.civil(2026, 9, 28), weekIndex: 2, dayTemplateID: Support.upperA.id)
        #expect(try weeks
            .nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 14)), in: program) == wednesday)
        #expect(try weeks
            .nextScheduledDay(after: Support.moment(Fixtures.civil(2026, 9, 19)), in: program) == thirdWeek)
        try Self.expectWalk(program)
    }

    @Test("Extreme week indices in an edited program do not trap.", arguments: [Int.max, Int.min, Int.max / 7 + 1])
    func nextScheduledDay_extremeWeekIndices_followTheWalk(index: Int) throws {
        var program = try Support.seedProgram()
        program.weeks[3].index = index
        try Self.expectWalk(program)
    }
}

#if os(macOS)
    extension NextScheduledDayEditedAdversarialTests {
        @Test("Two weeks with the same index do not trap, and the answers are the walk's.")
        func nextScheduledDay_repeatedWeekIndex_readsTheFirstAndDoesNotTrap() async {
            await #expect(processExitsWith: .success) {
                var program = try ScheduleAdversarial.seedProgram()
                program.weeks[1].index = 0
                program.weeks[1].schedule = [.tuesday: ScheduleAdversarial.lowerB.id]
                let weeks = ScheduleAdversarial.weeks()
                let reference = try SessionReference(walking: program, with: weeks, in: Fixtures.utc)
                for offset in -10 ..< 70 {
                    guard let day = ScheduleAdversarial.seedStart.adding(days: offset) else {
                        exit(2)
                    }
                    let moment = try ScheduleAdversarial.moment(day)
                    if try weeks.nextScheduledDay(after: moment, in: program) != reference.next(after: moment) {
                        exit(1)
                    }
                }
            }
        }
    }
#endif
