import Foundation
@testable import LedgerDomain
import Testing

/// F13 review S2-R1-4: the time spoken and the day a workout started, as the receipt and the past workout's detail
/// share them.
@Suite("ClockText's spoken forms", .tags(.domain))
struct ClockTextSpokenTests {
    @Test("The time spoken is by the whole second, and a saturated time does not trap")
    func clockText_spokenElapsed() {
        let english = Locale(identifier: "en_US")
        #expect(ClockText.spokenElapsed(.seconds(3665), locale: english) == "1 hour, 1 minute, 5 seconds")
        #expect(ClockText.spokenElapsed(.milliseconds(59900), locale: english) == "59 seconds")
        #expect(!ClockText.spokenElapsed(.seconds(Int64.max) + .seconds(1), locale: english).isEmpty)
    }

    @Test("The day is in the calendar's time zone, and a start that is no date is empty")
    func clockText_startDay() throws {
        let english = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 23)))
        #expect(ClockText.startDay(of: start, calendar: calendar, locale: english) == "Wednesday, September 16")
        var tokyo = calendar
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(ClockText.startDay(of: start, calendar: tokyo, locale: english) == "Thursday, September 17")
        let nowhere = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(ClockText.startDay(of: nowhere, calendar: calendar, locale: english).isEmpty)
    }
}
