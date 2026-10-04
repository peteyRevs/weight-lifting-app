import Foundation
@testable import LedgerDomain
import Testing

@Suite("DaysPerWeek", .tags(.domain))
struct DaysPerWeekTests {
    @Test("The cases are three to six days, and the raw value is the number of days")
    func cases_areThreeToSix() {
        #expect(DaysPerWeek.allCases == [.three, .four, .five, .six])
        #expect(DaysPerWeek.allCases.map(\.rawValue) == [3, 4, 5, 6])
        #expect(DaysPerWeek(rawValue: 2) == nil)
        #expect(DaysPerWeek(rawValue: 7) == nil)
    }

    @Test("It encodes as the bare number of days, and decodes back", arguments: DaysPerWeek.allCases)
    func codable_roundTripsAsANumber(days: DaysPerWeek) throws {
        let json = try Fixtures.json(days)
        #expect(json == String(days.rawValue))
        #expect(try JSONDecoder().decode(DaysPerWeek.self, from: Data(json.utf8)) == days)
    }
}
