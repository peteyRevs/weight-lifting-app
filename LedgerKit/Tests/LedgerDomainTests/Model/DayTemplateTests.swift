import Foundation
@testable import LedgerDomain
import Testing

@Suite("DayTemplate", .tags(.domain))
struct DayTemplateTests {
    @Test("A day's short title is the name before \" — \" (rule 45)")
    func dayTemplate_shortTitle() throws {
        #expect(try Fixtures.upperA().shortTitle == "Upper A")
        #expect(DayTemplate(id: DayTemplateID(Fixtures.uuid(1)), name: "New day", tag: "D5").shortTitle == "New day")
        #expect(DayTemplate(id: DayTemplateID(Fixtures.uuid(2)), name: "A — B — C", tag: "X").shortTitle == "A")
    }
}
