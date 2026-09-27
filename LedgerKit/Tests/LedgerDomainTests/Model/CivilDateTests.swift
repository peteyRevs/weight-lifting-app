import Foundation
@testable import LedgerDomain
import Testing

@Suite("CivilDate", .tags(.domain))
struct CivilDateTests {
    @Test("Only real Gregorian dates in years 1…9999 construct")
    func init_validatesGregorianDates() {
        #expect(CivilDate(year: 2024, month: 2, day: 29) != nil)
        #expect(CivilDate(year: 2000, month: 2, day: 29) != nil)
        #expect(CivilDate(year: 1900, month: 2, day: 29) == nil)
        #expect(CivilDate(year: 2026, month: 2, day: 29) == nil)
        #expect(CivilDate(year: 2026, month: 4, day: 31) == nil)
        #expect(CivilDate(year: 2026, month: 12, day: 31) != nil)
        #expect(CivilDate(year: 2026, month: 13, day: 1) == nil)
        #expect(CivilDate(year: 2026, month: 0, day: 1) == nil)
        #expect(CivilDate(year: 2026, month: 1, day: 0) == nil)
        #expect(CivilDate(year: 0, month: 1, day: 1) == nil)
        #expect(CivilDate(year: 10000, month: 1, day: 1) == nil)
    }

    @Test("Day arithmetic crosses months, leap days and years; weekdays follow")
    func adding_daysAndWeekdays() throws {
        let start = try #require(CivilDate(year: 2026, month: 8, day: 17))
        #expect(start.weekday == .monday)
        #expect(start.adding(days: 28) == Fixtures.civil(2026, 9, 14))
        #expect(start.adding(days: -17) == Fixtures.civil(2026, 7, 31))
        #expect(Fixtures.civil(2024, 2, 28).adding(days: 1) == Fixtures.civil(2024, 2, 29))
        #expect(Fixtures.civil(2025, 12, 29).adding(days: 367) == Fixtures.civil(2026, 12, 31))
        #expect(Fixtures.civil(2026, 9, 14).days(since: start) == 28)
        #expect(Fixtures.civil(1970, 1, 1).daysSinceEpoch == 0)
        #expect(Fixtures.civil(1970, 1, 1).weekday == .thursday)
        #expect(Fixtures.civil(1969, 12, 28).weekday == .sunday)
        #expect(Fixtures.civil(2000, 2, 29).weekday == .tuesday)
        #expect(Fixtures.civil(2026, 8, 16) < start)
        #expect(Fixtures.civil(2025, 12, 31) < Fixtures.civil(2026, 1, 1))
    }

    @Test("A civil date encodes as \"YYYY-MM-DD\" and decoding rejects anything else")
    func codable_isoDateText() throws {
        #expect(try Fixtures.json(Fixtures.civil(2026, 8, 17)) == #""2026-08-17""#)
        #expect(Fixtures.civil(987, 3, 4).description == "0987-03-04")
        #expect(try JSONDecoder().decode(CivilDate.self, from: Data(#""2024-02-29""#.utf8)) == Fixtures.civil(
            2024,
            2,
            29
        ))
        for bad in [
            #""2026-8-17""#,
            #""2026-02-30""#,
            #""20260817""#,
            #""2026-08-17T00:00""#,
            #""abcd-ef-gh""#,
            "20260817"
        ] {
            #expect(throws: DecodingError.self, "\(bad)") {
                try JSONDecoder().decode(CivilDate.self, from: Data(bad.utf8))
            }
        }
        #expect(CivilDate(iso8601: "2026-08-17") == Fixtures.civil(2026, 8, 17))
        #expect(CivilDate(iso8601: "+026-08-17") == nil)
    }

    @Test("An instant maps to the day of the calendar's time zone")
    func init_fromInstant_usesZone() throws {
        let instant = Fixtures.date(2026, 8, 17, hour: 5)
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try Fixtures.zone("America/Los_Angeles")
        var tokyo = Calendar(identifier: .japanese)
        tokyo.timeZone = try Fixtures.zone("Asia/Tokyo")
        #expect(CivilDate(instant, in: Fixtures.calendar) == Fixtures.civil(2026, 8, 17))
        #expect(CivilDate(instant, in: losAngeles) == Fixtures.civil(2026, 8, 16))
        #expect(CivilDate(instant, in: tokyo) == Fixtures.civil(2026, 8, 17))
    }

    @Test("The start of a day is its midnight, or 01:00 when DST skips midnight (Cairo, 2026-04-24)")
    func startOfDay_handlesMissingMidnight() throws {
        var cairo = Calendar(identifier: .gregorian)
        cairo.timeZone = try Fixtures.zone("Africa/Cairo")
        #expect(Fixtures.civil(2026, 4, 23).startOfDay(in: cairo) == Fixtures.date(2026, 4, 23, in: cairo.timeZone))
        #expect(Fixtures.civil(2026, 4, 24).startOfDay(in: cairo) == Fixtures.date(
            2026,
            4,
            24,
            hour: 1,
            in: cairo.timeZone
        ))
        #expect(Fixtures.civil(2026, 8, 17).startOfDay(in: Fixtures.calendar) == Fixtures.date(2026, 8, 17))
    }

    @Test(
        "Day numbers and weekdays agree with Foundation's Gregorian calendar",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func dayArithmetic_matchesFoundation(seed: PropertySeed) throws {
        var generator = seed.generator
        let offset = Int
            .random(in: -141_000 ... 2_900_000, using: &generator) // 1584 … 9909; Foundation is Julian before 1582
        let date = Fixtures.civil(1970, 1, 1).adding(days: offset)
        let instant = Date(timeIntervalSince1970: Double(offset) * 86400 + 43200)
        #expect(date == CivilDate(instant, in: Fixtures.calendar), "\(offset)")
        #expect(date.daysSinceEpoch == offset)
        #expect(date.weekday == Weekday(calendarWeekday: Fixtures.calendar.component(.weekday, from: instant)))
        let reparsed = try #require(CivilDate(iso8601: date.description), "\(date)")
        #expect(reparsed == date)
    }
}
