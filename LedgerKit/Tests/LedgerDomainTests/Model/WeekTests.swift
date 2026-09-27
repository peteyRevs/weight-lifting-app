import Foundation
@testable import LedgerDomain
import Testing

@Suite("Week", .tags(.domain))
struct WeekTests {
    @Test("Weekdays map to and from Foundation's Sunday-first numbering")
    func weekday_calendarMapping() {
        #expect(Weekday(calendarWeekday: 1) == .sunday)
        #expect(Weekday(calendarWeekday: 2) == .monday)
        #expect(Weekday(calendarWeekday: 7) == .saturday)
        #expect(Weekday(calendarWeekday: 0) == nil)
        #expect(Weekday(calendarWeekday: 8) == nil)
        #expect(Weekday.allCases.allSatisfy { Weekday(calendarWeekday: $0.calendarWeekday) == $0 })
        #expect(Weekday.monday < .sunday)
    }

    @Test("A week's schedule encodes as an object keyed by weekday number")
    func week_scheduleEncodesAsObject() throws {
        let day = DayTemplateID(Fixtures.uuid(5))
        let json = try Fixtures.json(Fixtures.week(0, schedule: [.monday: day]))
        #expect(json.contains(#""schedule":{"1":"00000000-0000-0000-0000-000000000005"}"#))
    }
}
