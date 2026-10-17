import Foundation
@testable import LedgerDomain
import Testing

// `WeekCalendar.nextScheduledDay(after:in:)` over blocks of every shape (F09 S2, criterion 1): the search
// reads each day's own program week, stops at the block's last week and ends for any program.

extension WeekCalendarTests {
    @Test("A block begun midweek reads each day's own program week, whatever the stats week start is")
    func nextScheduledDay_blockBegunMidweek_readsEachDaysOwnProgramWeek() throws {
        // Begun on Wednesday 2026-09-16, so the block's weeks run Wednesday to Tuesday: Sep 16–22 trains
        // a Monday, Sep 23–29 a Friday and Sep 30 – Oct 6 a Tuesday.
        let program = try Program(
            id: Fixtures.programID,
            name: "Midweek",
            startDate: Fixtures.civil(2026, 9, 16),
            weeks: [
                Fixtures.week(0, schedule: [.monday: Fixtures.upperADay]),
                Fixtures.week(1, schedule: [.friday: Fixtures.upperBDay]),
                Fixtures.week(2, schedule: [.tuesday: Fixtures.lowerADay])
            ],
            days: Fixtures.scheduleDays
        )
        let sessions: [(after: Date, next: ScheduledDay?)] = [
            // Monday Sep 21 is in the next calendar week and still in the block's first week.
            (Fixtures.date(2026, 9, 16), Self.session(9, 21, week: 0, Fixtures.upperADay)),
            (Fixtures.date(2026, 9, 21), Self.session(9, 25, week: 1, Fixtures.upperBDay)),
            // Monday Sep 28 is in the block's second week, which trains no Monday.
            (Fixtures.date(2026, 9, 25), Self.session(10, 6, week: 2, Fixtures.lowerADay)),
            (Fixtures.date(2026, 10, 6), nil)
        ]
        for weekStart in Weekday.allCases {
            let weeks = Self.weeks(for: program, weekStart: weekStart)
            for (after, next) in sessions {
                #expect(weeks.nextScheduledDay(after: after, in: program) == next, "week start \(weekStart)")
            }
        }
    }

    @Test("An empty week is passed over, and a moment before the block gives its first session wherever it is")
    func nextScheduledDay_emptyWeeks_arePassedOver() throws {
        var program = try Fixtures.datedFourDayProgram()
        program.weeks[1].schedule = [:]
        let weeks = Self.weeks(for: program)
        #expect(weeks.nextScheduledDay(after: Fixtures.date(2026, 9, 19), in: program)
            == Self.session(9, 28, week: 2, Fixtures.upperADay))
        program.weeks[0].schedule = [:]
        #expect(weeks.nextScheduledDay(after: Fixtures.date(2026, 9, 1), in: program)
            == Self.session(9, 28, week: 2, Fixtures.upperADay))
        #expect(weeks.nextScheduledDay(after: Fixtures.date(2026, 9, 16), in: program)
            == Self.session(9, 28, week: 2, Fixtures.upperADay))
    }

    @Test("A block that schedules nothing, or has no weeks, has no next session")
    func nextScheduledDay_nothingScheduled_isNil() throws {
        var program = try Fixtures.datedFourDayProgram()
        for index in program.weeks.indices {
            program.weeks[index].schedule = [:]
        }
        let weeks = Self.weeks(for: program)
        let moments = [Fixtures.date(2026, 8, 1), Fixtures.date(2026, 9, 16), Fixtures.date(2026, 12, 1)]
        for moment in moments {
            #expect(weeks.nextScheduledDay(after: moment, in: program) == nil)
        }
        var noWeeks = try Fixtures.datedFourDayProgram()
        noWeeks.weeks = []
        for moment in moments {
            #expect(weeks.nextScheduledDay(after: moment, in: noWeeks) == nil)
        }
    }

    @Test("Weeks edited after validation resolve as scheduledDay(on:in:) resolves them")
    func nextScheduledDay_editedWeeks_resolveAsScheduledDayDoes() throws {
        let saturday = Fixtures.date(2026, 9, 19, hour: 12)
        var reversed = try Fixtures.datedFourDayProgram()
        reversed.weeks.reverse()
        let weeks = Self.weeks(for: reversed)
        #expect(weeks.nextScheduledDay(after: saturday, in: reversed)
            == Self.session(9, 21, week: 1, Fixtures.upperADay))

        // Two weeks carry index 0 and none carries index 1. `Program.week(at:)` reads the first of the
        // two, so Sunday Sep 20 stays a rest day, and the block's second week has no sessions.
        var repeated = try Fixtures.datedFourDayProgram()
        repeated.weeks[1].index = 0
        repeated.weeks[1].schedule = [.sunday: Fixtures.lowerBDay]
        #expect(weeks.scheduledDay(on: Fixtures.date(2026, 9, 20), in: repeated) == nil)
        #expect(weeks.nextScheduledDay(after: saturday, in: repeated)
            == Self.session(9, 28, week: 2, Fixtures.upperADay))

        // Without its first week the block is seven weeks long (`isBlockComplete`) and no week carries
        // index 0: the first session is the second week's Monday, and week index 7 is past the block.
        var shortened = try Fixtures.datedFourDayProgram()
        shortened.weeks.removeFirst()
        #expect(weeks.nextScheduledDay(after: Fixtures.date(2026, 9, 1), in: shortened)
            == Self.session(9, 21, week: 1, Fixtures.upperADay))
        #expect(weeks.isBlockComplete(shortened, on: Fixtures.date(2026, 11, 2)))
        #expect(weeks.nextScheduledDay(after: Fixtures.date(2026, 11, 1), in: shortened) == nil)
    }

    @Test("A block that runs past 9999-12-31 ends at the last day a CivilDate can hold")
    func nextScheduledDay_blockPastYear9999_endsAtTheLastCivilDate() throws {
        let program = try Fixtures.everyDayProgram(startDate: Fixtures.civil(9999, 12, 20), weekCount: 4)
        let weeks = Self.weeks(for: program)
        // 9999-12-31 is a Friday, in the block's second week.
        #expect(weeks.nextScheduledDay(after: Fixtures.date(9999, 12, 30, hour: 12), in: program) == ScheduledDay(
            date: Fixtures.civil(9999, 12, 31),
            weekIndex: 1,
            dayTemplateID: Fixtures.everyDayTemplate(week: 1, on: .friday)
        ))
        #expect(weeks.nextScheduledDay(after: Fixtures.date(9999, 12, 31, hour: 12), in: program) == nil)
    }

    @Test("The earliest and latest moments give the first session and none; no moment traps")
    func nextScheduledDay_extremeMoments_neverTrap() throws {
        let program = try Fixtures.datedFourDayProgram()
        let weeks = Self.weeks(for: program)
        let first = Self.session(9, 14, week: 0, Fixtures.upperADay)
        #expect(weeks.nextScheduledDay(after: .distantPast, in: program) == first)
        #expect(weeks.nextScheduledDay(after: .distantFuture, in: program) == nil)
        // Foundation decides which day an instant like these falls on; whatever it is, the answer is a
        // day of the block or none.
        for seconds in [Double.infinity, -.infinity, .nan, 1e300, -1e300, .greatestFiniteMagnitude] {
            let next = weeks.nextScheduledDay(after: Date(timeIntervalSince1970: seconds), in: program)
            #expect(next.map { (0 ..< 8).contains($0.weekIndex) } ?? true, "\(seconds)")
        }
    }

    @Test("A block of 5,000 weeks that trains only on its last day finds that day")
    func nextScheduledDay_longBlock_findsItsLastDay() throws {
        let weekCount = 5000
        var weeks = (0 ..< weekCount).map { Fixtures.week($0) }
        weeks[weekCount - 1].schedule = [.sunday: Fixtures.lowerBDay]
        let program = try Program(
            id: Fixtures.programID,
            name: "Long",
            startDate: Fixtures.civil(2026, 9, 14),
            weeks: weeks,
            days: Fixtures.scheduleDays
        )
        let calendar = Self.weeks(for: program)
        let lastDay = try #require(program.startDate.adding(days: 7 * weekCount - 1))
        #expect(lastDay.weekday == .sunday)
        let expected = ScheduledDay(date: lastDay, weekIndex: weekCount - 1, dayTemplateID: Fixtures.lowerBDay)
        #expect(calendar.nextScheduledDay(after: Fixtures.date(2026, 9, 1), in: program) == expected)
        #expect(calendar.nextScheduledDay(after: Fixtures.date(2100, 1, 1), in: program) == expected)
        #expect(calendar.nextScheduledDay(after: lastDay.startOfDay(in: Fixtures.calendar), in: program) == nil)
    }

    @Test("A scheduled day's weekday is its date's, and two are equal when date, week and template are")
    func scheduledDay_weekdayAndEquality() {
        let friday = Self.session(9, 18, week: 0, Fixtures.upperBDay)
        #expect(friday.weekday == .friday)
        #expect(friday.date == Fixtures.civil(2026, 9, 18))
        #expect(friday.weekIndex == 0)
        #expect(friday.dayTemplateID == Fixtures.upperBDay)
        #expect(friday == Self.session(9, 18, week: 0, Fixtures.upperBDay))
        let others = [
            Self.session(9, 19, week: 0, Fixtures.upperBDay),
            Self.session(9, 18, week: 1, Fixtures.upperBDay),
            Self.session(9, 18, week: 0, Fixtures.lowerBDay)
        ]
        #expect(Set(others + [friday]).count == 4)
    }
}
