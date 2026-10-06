@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The Logged card's "Next:" line (criterion 15: it follows the program week and never names the week the
/// lifter is in), and both lines for seeded inputs in every zone of `TodayScenario`.
nonisolated extension TodayNextAdversarialTests {
    /// The Logged card of the session scheduled on `today`, finished that day, under `weekStart`; nil on a
    /// day with no session.
    static func logged(_ program: Program, on today: CivilDate, weekStart: Weekday) throws -> TodayModel.Logged? {
        guard let session = TodayOracle.session(on: today, in: program),
              let template = program.days.first(where: { $0.id == session.day })
        else {
            return nil
        }
        let start = try Support.moment(today, 6)
        let source = WorkoutSource(programID: program.id, weekIndex: session.week, dayTemplateID: template.id)
        let done = try Support.lifted(
            number: 77,
            start: start,
            lifts: [.pounds(100, 5)],
            name: template.name,
            source: source
        )
        let input = try Support.input(
            program,
            now: start.addingTimeInterval(4 * 3600),
            settings: Support.settings(weekStart: weekStart),
            week: [done]
        )
        return try Support.logged(TodayPresentation.make(input))
    }

    @Test(
        "Every session of a block begun on any weekday: Next names a day of this program week or a later week",
        arguments: 0 ..< 7
    )
    func nextLine_neverNamesTheWeekTheLifterIsIn(_ shift: Int) throws {
        let start = try #require(Support.civil(2026, 9, 14).adding(days: shift))
        var lines: [String] = []
        var checked = 0
        for program in try [Support.seed(start: start), TodayNextAdversarialTests.sparse(start: start)] {
            for offset in 0 ..< 56 {
                let today = try #require(start.adding(days: offset))
                guard let card = try Self.logged(program, on: today, weekStart: .monday) else {
                    continue
                }
                checked += 1
                let input = try Support.input(program, now: Support.moment(today))
                let allowed = try #require(TodayOracle(input)).nextLines(for: input)
                let other = try Self.logged(program, on: today, weekStart: .thursday)?.next
                if !allowed.contains(card.next) || card.next == "Next: week \(offset / 7 + 1)" || card.next != other {
                    lines.append("\(today), week \(offset / 7 + 1): \(card.next ?? "nil"), allowed \(allowed)")
                }
            }
        }
        let holds = lines.isEmpty
        #expect(holds, "\(lines.count) of \(checked) sessions:\n\(lines.prefix(5).joined(separator: "\n"))")
        #expect(checked >= 36)
    }

    @Test("Logged on the strip's last day with tomorrow's session in the next program week: Next names that week")
    func nextLine_followsTheProgramWeekNotTheStrip() throws {
        // The block from Monday 09-14, the week from Sunday: Saturday 09-19 ends week 1 and the strip (13 … 19).
        let aligned = try Support.seed()
        let saturday = try Support.civil(2026, 9, 19)
        #expect(try Self.logged(aligned, on: saturday, weekStart: .sunday)?.next == "Next: week 2")
        #expect(try Self.logged(aligned, on: saturday, weekStart: .saturday)?.next == "Next: week 2")
        // The block from Wednesday 09-16: Monday 09-21 ends week 1; Wednesday 09-23 is on the same Monday strip.
        let shifted = try Support.seed(start: Support.civil(2026, 9, 16))
        #expect(try Self.logged(shifted, on: Support.civil(2026, 9, 21), weekStart: .monday)?.next == "Next: week 2")
        // Saturday 09-19 there: Monday 09-21 is off the Monday strip and still in week 1.
        #expect(try Self.logged(shifted, on: saturday, weekStart: .monday)?.next == "Next: Monday · UA")
    }

    @Test("Seeded inputs: the rest-day body and the Next line are the rulings', in every zone", arguments: [
        UInt64(0) ... 1999, UInt64(2000) ... 3999
    ])
    func seededInputs_readTheRuledLines(_ seeds: ClosedRange<UInt64>) throws {
        let catalog = try Support.exercises()
        var lines: [String] = []
        var bodies = 0
        var nexts = 0
        for seed in seeds {
            let scenario = try TodayScenario(seed: seed, catalog: catalog)
            let oracle = try #require(TodayOracle(scenario.input))
            switch TodayPresentation.make(scenario.input).card {
            case let .restDay(card):
                bodies += 1
                if card.body != oracle.restBody(for: scenario.input) {
                    lines.append("seed \(seed) [\(scenario.note)]: \"\(card.body)\"")
                }
            case let .logged(card):
                nexts += 1
                if !oracle.nextLines(for: scenario.input).contains(card.next) {
                    lines.append("seed \(seed) [\(scenario.note)]: \(card.next ?? "nil")")
                }
            case .upNext, .noProgram, .blockComplete:
                break
            }
        }
        let holds = lines.isEmpty
        #expect(holds, "\(lines.count) seeds disagree:\n\(lines.prefix(5).joined(separator: "\n"))")
        print("TodayNextAdversarialTests seeds \(seeds): \(bodies) rest-day bodies, \(nexts) Next lines")
    }
}
