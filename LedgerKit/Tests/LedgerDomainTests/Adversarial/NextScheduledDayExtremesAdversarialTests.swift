import Foundation
@testable import LedgerDomain
import Testing

/// F09 S2 criterion 1 at the edges of time: moments far outside any block, blocks at the ends of
/// `CivilDate`'s range (0001-01-01 … 9999-12-31), and a block decades long. "A moment before the
/// block begins gives the block's first session"; after the block there is none; nothing traps.
@Suite("WeekCalendar.nextScheduledDay at the edges of time (adversarial, F09 S2)", .tags(.domain))
struct NextScheduledDayExtremesAdversarialTests {
    typealias Support = ScheduleAdversarial

    static let firstSession = ScheduledDay(date: Support.seedStart, weekIndex: 0, dayTemplateID: Support.upperA.id)

    /// Seconds from 1970 that are before any block: from last year back to before year 1.
    static let farPast: [TimeInterval] = [1.7e9, 0, -1, -1e9, -6.2e10, -6.3e10, -1e11, -1e12, -1e13, -1e15]
    /// Seconds from 1970 that are after the seed block: from 2027 on to past year 9999.
    static let farFuture: [TimeInterval] = [1.8e9, 4e9, 2.5e11, 2.6e11, 1e12, 1e13, 1e15]
}

extension NextScheduledDayExtremesAdversarialTests {
    @Test("Any moment before the block gives its first session, however far back.", arguments: farPast)
    func nextScheduledDay_momentFarBeforeTheBlock_givesTheFirstSession(seconds: TimeInterval) throws {
        let program = try Support.seedProgram()
        for identifier in ["UTC", "Pacific/Kiritimati", "America/Los_Angeles"] {
            let weeks = try Support.weeks(zone: Fixtures.zone(identifier))
            let next = weeks.nextScheduledDay(after: Date(timeIntervalSince1970: seconds), in: program)
            #expect(next == Self.firstSession, "\(identifier)")
        }
    }

    @Test("Date.distantPast is before the block, in a zone where it has no CivilDate too.")
    func nextScheduledDay_distantPast_givesTheFirstSession() throws {
        let program = try Support.seedProgram()
        for identifier in ["UTC", "America/Los_Angeles", "Pacific/Kiritimati"] {
            let weeks = try Support.weeks(zone: Fixtures.zone(identifier))
            #expect(weeks.nextScheduledDay(after: .distantPast, in: program) == Self.firstSession, "\(identifier)")
        }
    }

    @Test("Any moment after the block gives nil, however far ahead.", arguments: farFuture)
    func nextScheduledDay_momentFarAfterTheBlock_isNil(seconds: TimeInterval) throws {
        let program = try Support.seedProgram()
        for identifier in ["UTC", "Pacific/Kiritimati", "America/Los_Angeles"] {
            let weeks = try Support.weeks(zone: Fixtures.zone(identifier))
            #expect(weeks.nextScheduledDay(after: Date(timeIntervalSince1970: seconds), in: program) == nil)
            #expect(weeks.nextScheduledDay(after: .distantFuture, in: program) == nil)
        }
    }

    @Test("A block that runs past 9999-12-31 answers up to that day and then has none left.")
    func nextScheduledDay_blockRunningPastYear9999_stopsAtTheLastCivilDate() throws {
        let start = Fixtures.civil(9999, 12, 20)
        let program = try Support.everyDayProgram(start: start)
        let weeks = Support.weeks(start: start)
        let eve = ScheduledDay(
            date: Fixtures.civil(9999, 12, 31),
            weekIndex: 1,
            dayTemplateID: Support.everyDayTemplate(week: 1, Fixtures.civil(9999, 12, 31).weekday)
        )
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(9999, 12, 30)), in: program) == eve)
        #expect(try weeks.nextScheduledDay(after: Support.moment(Fixtures.civil(9999, 12, 31)), in: program) == nil)
        #expect(weeks.nextScheduledDay(after: .distantFuture, in: program)?.date == start)
        #expect(weeks.nextScheduledDay(after: Date(timeIntervalSince1970: 2.6e11), in: program) == nil)
        try NextScheduledDayEditedAdversarialTests.expectWalk(program, start: start, span: 12)
    }

    @Test("A block that begins on 0001-01-01 is answered from its first day.")
    func nextScheduledDay_blockAtYearOne_answersFromItsFirstDay() throws {
        let start = Fixtures.civil(1, 1, 1)
        let program = try Support.everyDayProgram(start: start)
        let weeks = Support.weeks(start: start)
        let first = ScheduledDay(
            date: start, weekIndex: 0, dayTemplateID: Support.everyDayTemplate(week: 0, start.weekday)
        )
        #expect(weeks.nextScheduledDay(after: Date(timeIntervalSince1970: -1e12), in: program) == first)
        let second = try #require(start.adding(days: 1))
        let after = try #require(weeks.nextScheduledDay(after: start.startOfDay(in: Support.calendar()), in: program))
        #expect(after.date == second)
        #expect(after.weekIndex == 0)
        #expect(after.dayTemplateID == Support.everyDayTemplate(week: 0, second.weekday))
    }

    @Test("A block 96 years long whose only session is on its last day is answered, from before it and inside it.")
    func nextScheduledDay_blockOfFiveThousandWeeks_findsItsLastDay() throws {
        let count = 5000
        var weeks = (0 ..< count).map { Support.week($0, [:]) }
        weeks[count - 1].schedule = [.sunday: Support.lowerB.id]
        let program = try Support.program(start: Support.seedStart, weeks: weeks, days: [Support.lowerB])
        let calendar = Support.weeks()
        let lastDay = try #require(Support.seedStart.adding(days: 7 * count - 1))
        let last = ScheduledDay(date: lastDay, weekIndex: count - 1, dayTemplateID: Support.lowerB.id)
        #expect(lastDay.weekday == .sunday)
        for offset in [-400_000, -1, 0, 1, 17500, 34998] {
            let moment = try Support.moment(#require(Support.seedStart.adding(days: offset)))
            #expect(calendar.nextScheduledDay(after: moment, in: program) == last, "\(offset) days from the start")
        }
        #expect(try calendar.nextScheduledDay(after: Support.moment(lastDay), in: program) == nil)
        #expect(calendar.nextScheduledDay(after: .distantPast, in: program) == last)
    }
}

#if os(macOS)
    extension NextScheduledDayExtremesAdversarialTests {
        @Test("Moments that are not on any calendar (±infinity, NaN, the largest Double) do not trap.")
        func nextScheduledDay_momentsOffTheCalendar_doNotTrap() async {
            await #expect(processExitsWith: .success) {
                let program = try ScheduleAdversarial.seedProgram()
                let weeks = ScheduleAdversarial.weeks()
                let offCalendar: [TimeInterval] = [
                    .infinity, -.infinity, .nan, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1e300, -1e300,
                    1e19
                ]
                for seconds in offCalendar {
                    _ = weeks.nextScheduledDay(after: Date(timeIntervalSince1970: seconds), in: program)
                }
            }
        }

        @Test("The far future has no session left and the far past has the first one, without trapping.")
        func nextScheduledDay_infinitelyFarMoments_areAfterAndBeforeTheBlock() async {
            await #expect(processExitsWith: .success) {
                let program = try ScheduleAdversarial.seedProgram()
                let weeks = ScheduleAdversarial.weeks()
                let first = ScheduledDay(
                    date: ScheduleAdversarial.seedStart, weekIndex: 0, dayTemplateID: ScheduleAdversarial.upperA.id
                )
                if weeks.nextScheduledDay(after: Date(timeIntervalSince1970: 1e19), in: program) != nil {
                    exit(1)
                }
                if weeks.nextScheduledDay(after: Date(timeIntervalSince1970: -1e19), in: program) != first {
                    exit(2)
                }
            }
        }
    }
#endif
