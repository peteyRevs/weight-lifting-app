import Foundation
@testable import LedgerDomain
import Testing

@Suite("Program (adversarial)", .tags(.domain))
struct ProgramAdversarialTests {
    static let day = DayTemplate(id: DayTemplateID(Fixtures.uuid(800)), name: "Upper A — Push focus", tag: "UA")

    static func make(_ weeks: [Week], days: [DayTemplate] = [day]) throws -> Program {
        try Program(id: Fixtures.programID, name: "Block", startDate: Adversarial.startDay, weeks: weeks, days: days)
    }

    static func weeks(_ indices: [Int]) -> [Week] {
        indices.map { Fixtures.week($0, schedule: [.monday: day.id]) }
    }
}

extension ProgramAdversarialTests {
    @Test("Fewer than two weeks is rejected (rule 4).", arguments: [0, 1])
    func init_tooFewWeeks_throws(count: Int) {
        #expect(throws: ProgramValidationError.tooFewWeeks(count: count)) {
            try Self.make(Self.weeks(Array(0 ..< count)))
        }
    }

    @Test(
        "Week indices that are not exactly 0…n − 1 are rejected.",
        arguments: [[0, 2], [1, 2], [0, 0], [0, 1, 1], [-1, 0], [0, 1, 3, 4]]
    )
    func init_nonContiguousWeeks_throws(indices: [Int]) {
        let error = #expect(throws: ProgramValidationError.self) { try Self.make(Self.weeks(indices)) }
        guard case .nonContiguousWeeks = error else {
            Issue.record("expected nonContiguousWeeks, got \(String(describing: error))")
            return
        }
    }

    @Test("Weeks given out of order are accepted and stored sorted by index.")
    func init_unorderedWeeks_areSorted() throws {
        let program = try Self.make(Self.weeks([2, 0, 1]))
        #expect(program.weeks.map(\.index) == [0, 1, 2])
        #expect(program.week(at: 1)?.index == 1)
        #expect(program.week(at: 3) == nil)
        #expect(program.week(at: -1) == nil)
    }

    @Test("A schedule pointing at a day template outside the program is rejected.")
    func init_danglingSchedule_throws() {
        let ghost = DayTemplateID(Fixtures.uuid(899))
        var weeks = Self.weeks([0, 1, 2])
        weeks[2].schedule[.friday] = ghost
        #expect(throws: ProgramValidationError.danglingSchedule(weekIndex: 2, dayTemplateID: ghost)) {
            try Self.make(weeks)
        }
    }

    @Test("Decoding weeks stored out of order yields them sorted by index.")
    func decode_unorderedWeeks_areSorted() throws {
        let program = try Self.make(Self.weeks([0, 1, 2]))
        let data = try Adversarial.tampered(program) { $0["weeks"] = try Adversarial.fragment(Self.weeks([2, 0, 1])) }
        #expect(try JSONDecoder().decode(Program.self, from: data).weeks.map(\.index) == [0, 1, 2])
    }

    @Test("A long block with no maximum is accepted (rule 4: no maximum).")
    func init_longBlock_isAccepted() throws {
        let program = try Self.make(Self.weeks(Array(0 ..< 104)))
        #expect(program.weeks.count == 104)
        #expect(program.isActive == false)
        #expect(program.goal == nil)
    }

    @Test("A valid program survives a Codable round-trip unchanged.")
    func codable_roundTrip_isIdentity() throws {
        var program = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        program.goal = .hypertrophy
        program.daysPerWeek = 3
        program.isActive = true
        #expect(try Adversarial.roundTrip(program) == program)
    }

    @Test("Tampered JSON with one week, a gap or a dangling schedule is rejected on decode.")
    func decode_tampered_throws() throws {
        let program = try Self.make(Self.weeks([0, 1, 2]))
        let oneWeek = try Adversarial.tampered(program) { object in
            let weeks = try #require(object["weeks"] as? [Any])
            object["weeks"] = Array(weeks.prefix(1))
        }
        let gap = try Adversarial.tampered(program) { object in
            object["weeks"] = try Adversarial.fragment(Self.weeks([0, 2, 3]))
        }
        var dangling = Self.weeks([0, 1, 2])
        dangling[0].schedule[.sunday] = DayTemplateID(Fixtures.uuid(898))
        let ghost = try Adversarial.tampered(program) { object in
            object["weeks"] = try Adversarial.fragment(dangling)
        }
        for data in [oneWeek, gap, ghost] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(Program.self, from: data) }
        }
    }
}
