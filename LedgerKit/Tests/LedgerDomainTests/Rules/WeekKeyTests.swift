import Foundation
@testable import LedgerDomain
import Testing

@Suite("WeekKey", .tags(.domain))
struct WeekKeyTests {
    @Test("Week keys order by year, then week")
    func comparable_yearThenWeek() {
        let keys = [WeekKey(year: 2027, week: 1), WeekKey(year: 2026, week: 53), WeekKey(year: 2026, week: 2)]
        #expect(keys.sorted() == [
            WeekKey(year: 2026, week: 2),
            WeekKey(year: 2026, week: 53),
            WeekKey(year: 2027, week: 1)
        ])
    }

    @Test("A week key round-trips through JSON")
    func codable_roundTrips() throws {
        let key = WeekKey(year: 2026, week: 38)
        #expect(try JSONDecoder().decode(WeekKey.self, from: JSONEncoder().encode(key)) == key)
    }
}
