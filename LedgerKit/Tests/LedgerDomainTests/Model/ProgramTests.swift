import Foundation
@testable import LedgerDomain
import Testing

@Suite("Program", .tags(.domain))
struct ProgramTests {
    @Test("A block needs at least two weeks (rule 4)")
    func init_oneWeek_throwsTooFewWeeks() throws {
        let day = try Fixtures.upperA()
        #expect(throws: ProgramValidationError.tooFewWeeks(count: 1)) {
            try Program(
                id: Fixtures.programID,
                name: "P",
                startDate: Fixtures.now,
                weeks: [Fixtures.week(0)],
                days: [day]
            )
        }
    }

    @Test("Week indices must be exactly 0 … n − 1")
    func init_gapInWeekIndices_throwsNonContiguous() {
        let weeks = [Fixtures.week(0), Fixtures.week(2)]
        #expect(throws: ProgramValidationError.nonContiguousWeeks(indices: [0, 2])) {
            try Program(id: Fixtures.programID, name: "P", startDate: Fixtures.now, weeks: weeks, days: [])
        }
    }

    @Test("Weeks given out of order are stored sorted by index")
    func init_unsortedWeeks_areSorted() throws {
        let weeks = [Fixtures.week(1), Fixtures.week(0), Fixtures.week(2)]
        let program = try Program(id: Fixtures.programID, name: "P", startDate: Fixtures.now, weeks: weeks, days: [])
        #expect(program.weeks.map(\.index) == [0, 1, 2])
        #expect(program.week(at: 2) == Fixtures.week(2))
        #expect(program.week(at: 3) == nil)
    }

    @Test("A schedule that points at a missing day throws danglingSchedule")
    func init_danglingSchedule_throws() {
        let missing = DayTemplateID(Fixtures.uuid(777))
        let weeks = [Fixtures.week(0), Fixtures.week(1, schedule: [.friday: missing])]
        #expect(throws: ProgramValidationError.danglingSchedule(weekIndex: 1, dayTemplateID: missing)) {
            try Program(id: Fixtures.programID, name: "P", startDate: Fixtures.now, weeks: weeks, days: [])
        }
    }

    @Test("The seed program is valid and round-trips through JSON")
    func codable_roundTrips() throws {
        let program = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let data = try JSONEncoder().encode(program)
        #expect(try JSONDecoder().decode(Program.self, from: data) == program)
        #expect(program.weeks.count == 8)
        #expect(program.weeks[7].isDeload)
    }

    @Test("Decoding re-validates the block")
    func decoding_invalidBlock_throws() throws {
        var program = try Fixtures.program(days: [Fixtures.upperA()])
        program.weeks.removeLast(7)
        let data = try JSONEncoder().encode(program)
        #expect(throws: ProgramValidationError.tooFewWeeks(count: 1)) {
            try JSONDecoder().decode(Program.self, from: data)
        }
    }
}
