import Foundation
@testable import LedgerDomain
import Testing

@Suite("LastPerformance line", .tags(.domain))
struct LastPerformanceLineTests {
    @Test("The line reads \"Aug 12 · 5×5 @ 180 lb\" (spec §6.3)")
    func line_specSample() {
        let last = LastPerformance(date: Fixtures.date(2026, 8, 12, hour: 18), sets: 5, reps: 5, load: .pounds(180))
        #expect(last.line(units: .lb, calendar: Fixtures.calendar) == "Aug 12 · 5×5 @ 180 lb")
        #expect(last.line(units: .kg, calendar: Fixtures.calendar) == "Aug 12 · 5×5 @ 81.6 kg")
    }

    @Test("Fractional loads print exactly")
    func line_fractionalLoad() {
        let last = LastPerformance(date: Fixtures.date(2026, 1, 3), sets: 3, reps: 15, load: .pounds(12.5))
        #expect(last.line(units: .lb, calendar: Fixtures.calendar) == "Jan 3 · 3×15 @ 12.5 lb")
    }

    @Test("The calendar's time zone decides the day; the month name ignores its locale")
    func line_usesCalendarTimeZone() throws {
        var tokyo = Calendar(identifier: .japanese)
        tokyo.timeZone = try Fixtures.zone("Asia/Tokyo")
        tokyo.locale = Locale(identifier: "fr_FR")
        let lateUTC = Fixtures.date(2026, 12, 31, hour: 20)
        let last = LastPerformance(date: lateUTC, sets: 4, reps: 8, load: .pounds(65))
        #expect(last.line(units: .lb, calendar: Fixtures.calendar) == "Dec 31 · 4×8 @ 65 lb")
        #expect(last.line(units: .lb, calendar: tokyo) == "Jan 1 · 4×8 @ 65 lb")
    }
}
