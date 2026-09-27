import Foundation
@testable import LedgerDomain
import Testing

@Suite("WeekCalendar", .tags(.domain))
struct WeekCalendarTests {
    // A block starting at local midnight on `start` in `zone`, and a local wall-clock `date`.

    private func calendar(_ zone: TimeZone = Fixtures.utc) -> Calendar {
        var calendar = Fixtures.calendar
        calendar.timeZone = zone
        return calendar
    }

    private var block: WeekCalendar {
        WeekCalendar(startDate: Fixtures.date(2026, 8, 17), weekStart: .monday, calendar: Fixtures.calendar)
    }

    @Test("Week index counts calendar weeks from the start date, DST included (decision #18)", arguments: IndexRow.all)
    func weekIndex_fromStartDate(row: IndexRow) throws {
        let zone = try Fixtures.zone(row.zone)
        let start = Fixtures.date(row.start[0], row.start[1], row.start[2], in: zone)
        let date = Fixtures.date(
            row.date[0],
            row.date[1],
            row.date[2],
            hour: row.date[3],
            minute: row.date[4],
            in: zone
        )
        let weeks = WeekCalendar(startDate: start, weekStart: .monday, calendar: calendar(zone))
        #expect(weeks.weekIndex(for: date) == row.expected)
    }

    @Test("Criterion 10: Aug 19 is week 0 and a Wednesday; the last complete week before Sep 16 is Sep 7–14")
    func criterion10_weekdayAndPreviousCompleteWeek() {
        #expect(block.weekday(of: Fixtures.date(2026, 8, 19, hour: 12)) == .wednesday)
        #expect(block.previousCompleteWeek(before: Fixtures.date(2026, 9, 16)) == Fixtures.date(2026, 9, 7) ..< Fixtures
            .date(
                2026,
                9,
                14
            ))
        #expect(block.previousCompleteWeek(before: Fixtures.date(2026, 9, 14)) == Fixtures.date(2026, 9, 7) ..< Fixtures
            .date(
                2026,
                9,
                14
            ))
        #expect(block.startDate == Fixtures.date(2026, 8, 17))
    }

    @Test("Week bounds are local midnights, so a DST week lasts 167 hours")
    func bounds_dstWeekIs167Hours() throws {
        let berlin = try Fixtures.zone("Europe/Berlin")
        let weeks = WeekCalendar(
            startDate: Fixtures.date(2026, 3, 23, hour: 15, in: berlin),
            weekStart: .monday,
            calendar: calendar(berlin)
        )
        let first = weeks.bounds(ofWeek: 0)
        #expect(first.lowerBound == Fixtures.date(2026, 3, 23, in: berlin))
        #expect(first.upperBound == Fixtures.date(2026, 3, 30, in: berlin))
        #expect(first.upperBound.timeIntervalSince(first.lowerBound) == 167 * 3600)
        #expect(weeks.bounds(ofWeek: 2).lowerBound == Fixtures.date(2026, 4, 6, in: berlin))
        #expect(block.bounds(ofWeek: 4) == Fixtures.date(2026, 9, 14) ..< Fixtures.date(2026, 9, 21))
    }

    @Test("The default week start is the locale's first weekday (decision #15)")
    func weekStart_respectsLocaleFirstWeekday() {
        let expectations: [(String, Weekday)] = [("en_US", .sunday), ("de_DE", .monday), ("en_GB", .monday)]
        for (identifier, expected) in expectations {
            var localized = Calendar(identifier: .gregorian)
            localized.locale = Locale(identifier: identifier)
            #expect(Weekday.first(of: localized) == expected, "\(identifier)")
        }
        let american = Fixtures.calendar
        let weeks = WeekCalendar(
            startDate: Fixtures.date(2026, 8, 16),
            weekStart: Weekday.first(of: american),
            calendar: american
        )
        #expect(weeks.week(containing: Fixtures.date(2026, 9, 16)) == Fixtures.date(2026, 9, 13) ..< Fixtures.date(
            2026,
            9,
            20
        ))
    }

    @Test("A Settings week start overrides the calendar's first weekday (decision #15)")
    func weekStart_settingsOverrideWins() {
        #expect(Fixtures.calendar.firstWeekday == 1)
        #expect(block.week(containing: Fixtures.date(2026, 9, 13, hour: 22)) == Fixtures.date(2026, 9, 7) ..< Fixtures
            .date(
                2026,
                9,
                14
            ))
        #expect(block.week(containing: Fixtures.date(2026, 9, 16)).lowerBound == Fixtures.date(2026, 9, 14))
        #expect(block.isoWeekKey(for: Fixtures.date(2026, 9, 13)) < block.isoWeekKey(for: Fixtures.date(2026, 9, 14)))
    }

    @Test("A Sunday week start moves stats weeks and week keys to Sunday")
    func weekStart_sunday() {
        let weeks = WeekCalendar(startDate: Fixtures.date(2026, 8, 16), weekStart: .sunday, calendar: Fixtures.calendar)
        #expect(weeks.previousCompleteWeek(before: Fixtures.date(2026, 9, 16)) == Fixtures.date(2026, 9, 6) ..< Fixtures
            .date(
                2026,
                9,
                13
            ))
        #expect(weeks.weekday(of: Fixtures.date(2026, 9, 13)) == .sunday)
        #expect(weeks.weekIndex(for: Fixtures.date(2026, 9, 13)) == 4)
        #expect(weeks.isoWeekKey(for: Fixtures.date(2026, 9, 13)) == weeks.isoWeekKey(for: Fixtures.date(2026, 9, 19)))
        #expect(weeks.isoWeekKey(for: Fixtures.date(2026, 9, 12)) < weeks.isoWeekKey(for: Fixtures.date(2026, 9, 13)))
    }
}

// MARK: - Week keys and schedule (decisions #4, #18)

extension WeekCalendarTests {
    @Test("With a Monday start the week key is the ISO 8601 week")
    func isoWeekKey_mondayIsISO8601() {
        #expect(block.isoWeekKey(for: Fixtures.date(2026, 1, 1)) == WeekKey(year: 2026, week: 1))
        #expect(block.isoWeekKey(for: Fixtures.date(2025, 12, 29)) == WeekKey(year: 2026, week: 1))
        #expect(block.isoWeekKey(for: Fixtures.date(2027, 1, 1)) == WeekKey(year: 2026, week: 53))
        #expect(block.isoWeekKey(for: Fixtures.date(2026, 9, 16)) == WeekKey(year: 2026, week: 38))
    }

    @Test("A weekday with no template that week is off-schedule (decision #18)")
    func dayIsOffSchedule_whenNoTemplateForWeekday() throws {
        let upperA = try Fixtures.upperA()
        let upperB = try Fixtures.upperB()
        let program = try Fixtures.program(days: [upperA, upperB])
        #expect(block.scheduledDay(on: Fixtures.date(2026, 8, 17, hour: 7), in: program) == upperA.id)
        #expect(block.scheduledDay(on: Fixtures.date(2026, 8, 19), in: program) == upperB.id)
        #expect(block.scheduledDay(on: Fixtures.date(2026, 8, 18), in: program) == nil)
        #expect(block.scheduledDay(on: Fixtures.date(2026, 8, 21), in: program) == nil)
        #expect(block.scheduledDay(on: Fixtures.date(2026, 8, 10), in: program) == nil)
        #expect(block.scheduledDay(on: Fixtures.date(2026, 10, 12), in: program) == nil)
    }

    @Test("Skipping a whole week is a miss for every slot, so loads hold (decision #18)")
    func skippedWholeWeek_isMissForEverySlot() throws {
        let program = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let skipped = block.skippedWeeks(before: Fixtures.date(2026, 9, 9), trainedWeeks: [0, 2], weekCount: 8)
        #expect(skipped == [1])
        let updated = skipped.reduce(program) { MissTracking.recordSkippedWeek($1, in: $0) }
        #expect(updated.days.flatMap(\.slots).allSatisfy { $0.misses == [1] })
        let bench = updated.days[0].slots[0]
        let weekTwo = ProgressionRules.prescribe(
            week: updated.weeks[2], weekIndex: 2, slot: bench, exercise: Fixtures.bench, units: .lb
        )
        #expect(weekTwo.load == .pounds(185))
        #expect(weekTwo.isHeld)
        #expect(block
            .skippedWeeks(before: Fixtures.date(2026, 10, 20), trainedWeeks: [], weekCount: 8) == Array(0 ..< 8))
        #expect(block.skippedWeeks(before: Fixtures.date(2026, 8, 1), trainedWeeks: [], weekCount: 8).isEmpty)
    }

    @Test("The block ends on the first day of week `weeks.count` (decision #18)")
    func blockEnd_isDetectedOnLastWeekPlusOne() throws {
        let program = try Fixtures.program(days: [Fixtures.upperA()])
        let lastDay = Fixtures.date(2026, 10, 11, hour: 23)
        let nextMonday = Fixtures.date(2026, 10, 12)
        #expect(block.weekIndex(for: lastDay) == 7)
        #expect(!block.isBlockComplete(program, on: lastDay))
        #expect(block.weekIndex(for: nextMonday) == 8)
        #expect(block.isBlockComplete(program, on: nextMonday))
    }
}

extension WeekCalendarTests {
    struct IndexRow: Sendable, CustomStringConvertible {
        let zone: String
        let start: [Int]
        let date: [Int]
        let expected: Int
        let description: String

        static let all: [IndexRow] = [
            IndexRow(
                zone: "UTC",
                start: [2026, 8, 17],
                date: [2026, 8, 19, 12, 0],
                expected: 0,
                description: "Wed of week 0 (criterion 10)"
            ),
            IndexRow(
                zone: "UTC",
                start: [2026, 8, 17],
                date: [2026, 9, 14, 0, 0],
                expected: 4,
                description: "Sep 14 is week 4 (criterion 10)"
            ),
            IndexRow(
                zone: "UTC",
                start: [2026, 8, 17],
                date: [2026, 8, 23, 23, 59],
                expected: 0,
                description: "last minute of week 0"
            ),
            IndexRow(
                zone: "UTC",
                start: [2026, 8, 17],
                date: [2026, 8, 24, 0, 0],
                expected: 1,
                description: "first minute of week 1"
            ),
            IndexRow(
                zone: "UTC",
                start: [2026, 8, 17],
                date: [2026, 8, 16, 12, 0],
                expected: -1,
                description: "the day before the block"
            ),
            IndexRow(
                zone: "UTC",
                start: [2026, 8, 17],
                date: [2026, 8, 9, 23, 0],
                expected: -2,
                description: "eight days before"
            ),
            IndexRow(
                zone: "UTC",
                start: [2026, 12, 28],
                date: [2027, 1, 3, 23, 0],
                expected: 0,
                description: "across year end, week 0"
            ),
            IndexRow(
                zone: "UTC",
                start: [2026, 12, 28],
                date: [2027, 1, 4, 0, 0],
                expected: 1,
                description: "across year end, week 1"
            ),
            IndexRow(
                zone: "Europe/Berlin",
                start: [2026, 3, 23],
                date: [2026, 3, 29, 23, 30],
                expected: 0,
                description: "Berlin spring-forward week, Sunday night"
            ),
            IndexRow(
                zone: "Europe/Berlin",
                start: [2026, 3, 23],
                date: [2026, 3, 30, 0, 30],
                expected: 1,
                description: "Berlin, 167 h after the start"
            ),
            IndexRow(
                zone: "Europe/Berlin",
                start: [2026, 10, 19],
                date: [2026, 10, 25, 23, 59],
                expected: 0,
                description: "Berlin fall-back week, Sunday night"
            ),
            IndexRow(
                zone: "Europe/Berlin",
                start: [2026, 10, 19],
                date: [2026, 10, 26, 0, 0],
                expected: 1,
                description: "Berlin after fall-back"
            ),
            IndexRow(
                zone: "America/New_York",
                start: [2026, 3, 2],
                date: [2026, 3, 8, 23, 0],
                expected: 0,
                description: "New York spring-forward Sunday"
            ),
            IndexRow(
                zone: "America/New_York",
                start: [2026, 3, 2],
                date: [2026, 3, 9, 0, 0],
                expected: 1,
                description: "New York, Monday after spring-forward"
            ),
            IndexRow(
                zone: "America/New_York",
                start: [2026, 10, 26],
                date: [2026, 11, 1, 23, 59],
                expected: 0,
                description: "New York, 168 h 59 min after the start"
            ),
            IndexRow(
                zone: "America/New_York",
                start: [2026, 10, 26],
                date: [2026, 11, 16, 9, 0],
                expected: 3,
                description: "New York, three weeks on"
            )
        ]
    }
}
