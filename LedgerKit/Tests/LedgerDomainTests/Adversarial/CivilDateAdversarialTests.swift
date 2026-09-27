import Foundation
@testable import LedgerDomain
import Testing

/// ADR-007: a program starts on a `CivilDate` — a proleptic Gregorian day with no time or zone,
/// valid in years 1…9999, encoded as `"YYYY-MM-DD"`. Day numbers are checked against Python's
/// proleptic `datetime.date` (e.g. 2026-08-17 is day 20,682 since 1970-01-01, a Monday).
@Suite("CivilDate (adversarial, ADR-007)", .tags(.domain))
struct CivilDateAdversarialTests {
    static func civil(_ year: Int, _ month: Int, _ day: Int) throws -> CivilDate {
        try #require(CivilDate(year: year, month: month, day: day))
    }

    static let badText = [
        "2026-02-30", "2026-8-17", "26-08-17", "2026/08/17", "2026-08-17T00:00:00Z", " 2026-08-17", "2026-08-17 ",
        "２０２６-08-17", "+2026-08-17", "2026-13-01", "0000-01-01", "10000-01-01", "", "2026-08-1a", "2026-08",
        "20260817", "-2026-08-17", "2026-08-17\n", "2026–08–17", "2026-00-10", "2023-02-29", "1900-02-29"
    ]
}

extension CivilDateAdversarialTests {
    @Test(
        "Impossible dates are rejected: Feb 30, non-leap Feb 29, month 0/13, day 0/32, years outside 1…9999.",
        arguments: [
            (2026, 2, 30), (2023, 2, 29), (1900, 2, 29), (2100, 2, 29), (2026, 4, 31), (2026, 6, 31), (2026, 0, 1),
            (2026, 13, 1), (2026, 1, 0), (2026, 1, 32), (0, 1, 1), (10000, 1, 1), (-1, 1, 1), (2026, -1, 1),
            (2026, 1, -5)
        ]
    )
    func init_impossibleDate_isNil(year: Int, month: Int, day: Int) {
        #expect(CivilDate(year: year, month: month, day: day) == nil)
    }

    @Test(
        "Real dates are accepted, leap days and the range ends included.",
        arguments: [
            (2024, 2, 29),
            (2000, 2, 29),
            (1600, 2, 29),
            (1, 1, 1),
            (9999, 12, 31),
            (2026, 12, 31),
            (1582, 10, 10)
        ]
    )
    func init_realDate_keepsFields(year: Int, month: Int, day: Int) throws {
        let date = try Self.civil(year, month, day)
        #expect(date.year == year)
        #expect(date.month == month)
        #expect(date.day == day)
    }

    @Test(
        "Day numbers and weekdays are proleptic Gregorian.",
        arguments: [
            (1970, 1, 1, 0, Weekday.thursday), (1969, 12, 31, -1, .wednesday), (2000, 3, 1, 11017, .wednesday),
            (2026, 8, 17, 20682, .monday), (1, 1, 1, -719_162, .monday), (9999, 12, 31, 2_932_896, .friday),
            (2024, 2, 29, 19782, .thursday), (1582, 10, 15, -141_427, .friday), (1582, 10, 4, -141_438, .monday),
            (2000, 1, 1, 10957, .saturday)
        ]
    )
    func daysSinceEpoch_andWeekday(year: Int, month: Int, day: Int, number: Int, weekday: Weekday) throws {
        let date = try Self.civil(year, month, day)
        #expect(date.daysSinceEpoch == number)
        #expect(date.weekday == weekday)
    }

    @Test("Adding days crosses leap days, month ends and years exactly.")
    func adding_acrossLeapDaysAndYears() throws {
        #expect(try Self.civil(2024, 2, 28).adding(days: 1) == Self.civil(2024, 2, 29))
        #expect(try Self.civil(2024, 2, 28).adding(days: 2) == Self.civil(2024, 3, 1))
        #expect(try Self.civil(2023, 2, 28).adding(days: 1) == Self.civil(2023, 3, 1))
        #expect(try Self.civil(1900, 2, 28).adding(days: 1) == Self.civil(1900, 3, 1))
        #expect(try Self.civil(2000, 2, 28).adding(days: 1) == Self.civil(2000, 2, 29))
        #expect(try Self.civil(2026, 12, 31).adding(days: 1) == Self.civil(2027, 1, 1))
        #expect(try Self.civil(2027, 1, 1).adding(days: -1) == Self.civil(2026, 12, 31))
        #expect(try Self.civil(2024, 2, 29).adding(days: 365) == Self.civil(2025, 2, 28))
        #expect(try Self.civil(2024, 2, 29).adding(days: 366) == Self.civil(2025, 3, 1))
        #expect(try Self.civil(2026, 8, 17).adding(days: 0) == Self.civil(2026, 8, 17))
        #expect(try Self.civil(2026, 9, 14).days(since: Self.civil(2026, 8, 17)) == 28)
        #expect(try Self.civil(2026, 8, 17).days(since: Self.civil(2026, 9, 14)) == -28)
    }

    @Test("Ordering is by year, then month, then day.")
    func ordering_isChronological() throws {
        let dates = try [Self.civil(2026, 2, 1), Self.civil(2025, 12, 31), Self.civil(2026, 1, 31), Self.civil(1, 1, 1)]
        #expect(try dates.sorted() == [
            Self.civil(1, 1, 1),
            Self.civil(2025, 12, 31),
            Self.civil(2026, 1, 31),
            Self.civil(2026, 2, 1)
        ])
        #expect(try !(Self.civil(2026, 8, 17) < Self.civil(2026, 8, 17)))
        #expect(try Set([Self.civil(2026, 8, 17), Self.civil(2026, 8, 17)]).count == 1)
    }

    @Test("Text is zero-padded YYYY-MM-DD and parses back; malformed text is rejected.", arguments: badText)
    func iso8601_malformed_isNil(text: String) throws {
        #expect(CivilDate(iso8601: text) == nil)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CivilDate.self, from: JSONEncoder().encode(text))
        }
    }

    @Test("Descriptions are zero-padded and round-trip through text and JSON.")
    func description_roundTrips() throws {
        for date in try [
            Self.civil(2026, 8, 17),
            Self.civil(5, 1, 2),
            Self.civil(9999, 12, 31),
            Self.civil(2024, 2, 29)
        ] {
            #expect(CivilDate(iso8601: date.description) == date)
            #expect(try Adversarial.roundTrip(date) == date)
        }
        #expect(try Self.civil(5, 1, 2).description == "0005-01-02")
        #expect(try Fixtures.json(Self.civil(2026, 8, 17)) == "\"2026-08-17\"")
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CivilDate.self, from: Data("20260817".utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CivilDate.self, from: Data("null".utf8)) }
    }

    @Test("An instant's civil day depends only on the zone, not the calendar's identifier.")
    func initFromDate_usesZoneOnly() throws {
        let instant = Fixtures.date(2026, 8, 17, hour: 12)
        let zones = [("UTC", 17), ("America/Los_Angeles", 17), ("Pacific/Kiritimati", 18), ("Pacific/Pago_Pago", 17)]
        for (identifier, day) in zones {
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = try Fixtures.zone(identifier)
            #expect(try CivilDate(instant, in: gregorian) == (Self.civil(2026, 8, day)), "\(identifier)")
        }
        let early = Fixtures.date(2026, 8, 17, hour: 2)
        var angeles = Calendar(identifier: .gregorian)
        angeles.timeZone = try Fixtures.zone("America/Los_Angeles")
        #expect(try CivilDate(early, in: angeles) == (Self.civil(2026, 8, 16)))
        for identifier in [Calendar.Identifier.islamicUmmAlQura, .buddhist, .hebrew, .japanese] {
            var other = Calendar(identifier: identifier)
            other.timeZone = Fixtures.utc
            #expect(try CivilDate(instant, in: other) == (Self.civil(2026, 8, 17)), "\(identifier)")
        }
    }

    @Test("startOfDay is local midnight, or 01:00 on a day whose midnight DST skips, and maps back to the day.")
    func startOfDay_inZones() throws {
        let cairo = try WeekCalendarAdversarialTests.calendar(Fixtures.zone("Africa/Cairo"))
        let friday = try Self.civil(2026, 4, 24)
        let start = friday.startOfDay(in: cairo)
        #expect(start == Fixtures.date(2026, 4, 24, hour: 12, in: cairo.timeZone).addingTimeInterval(-11 * 3600))
        #expect(CivilDate(start, in: cairo) == friday)
        #expect(CivilDate(start.addingTimeInterval(-1), in: cairo) == friday.adding(days: -1))
        let york = try WeekCalendarAdversarialTests.calendar(Fixtures.zone("America/New_York"))
        #expect(try Self.civil(2026, 3, 8).startOfDay(in: york) == Fixtures.date(2026, 3, 8, in: york.timeZone))
    }
}
