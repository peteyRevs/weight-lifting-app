@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2, round 2: criterion 15. "Next up is {weekday}." when the next session's date is one of the
/// strip's seven days, "Next up is next {weekday}." when it is not, whichever program week it falls in; the
/// first sentence still names the program week; the Logged card's "Next:" still follows the program week and
/// never names the week the lifter is in.
@Suite("Adversarial F09 S3 round 2 · next, by the seven days on screen", .tags(.feature))
nonisolated struct TodayNextAdversarialTests {
    typealias Support = TodayAdversarial

    /// One rest day by hand: the week start, the day the block began (September 2026), today, and the body.
    struct Row: Sendable, CustomStringConvertible {
        let weekStart: Weekday
        let blockStart: Int
        let today: Int
        let body: String

        init(_ weekStart: Weekday, block blockStart: Int, today: Int, _ body: String) {
            self.weekStart = weekStart
            self.blockStart = blockStart
            self.today = today
            self.body = body
        }

        var description: String {
            "week from \(weekStart), block from 09-\(blockStart), today 09-\(today)"
        }
    }

    /// The seed schedule: Mon UA · Wed LA · Fri UB · Sat LB, keyed by weekday in every program week.
    static let rows = [
        // Sunday 09-20 is the strip's last day from Monday, its first from Sunday, and inside it from Tuesday.
        Row(.monday, block: 14, today: 20, "Nothing scheduled for Sunday in week 1. Next up is next Monday."),
        Row(.sunday, block: 14, today: 20, "Nothing scheduled for Sunday in week 1. Next up is Monday."),
        Row(.tuesday, block: 14, today: 20, "Nothing scheduled for Sunday in week 1. Next up is Monday."),
        // Tuesday 09-15 is the strip's last day from Wednesday: tomorrow's session is next Wednesday's.
        Row(.wednesday, block: 14, today: 15, "Nothing scheduled for Tuesday in week 1. Next up is next Wednesday."),
        Row(.tuesday, block: 14, today: 15, "Nothing scheduled for Tuesday in week 1. Next up is Wednesday."),
        Row(.monday, block: 14, today: 17, "Nothing scheduled for Thursday in week 1. Next up is Friday."),
        Row(.friday, block: 14, today: 17, "Nothing scheduled for Thursday in week 1. Next up is next Friday."),
        // The block begun on Wednesday 09-16: Tuesday 09-22 is week 1, Wednesday 09-23 is week 2 and on screen.
        Row(.monday, block: 16, today: 22, "Nothing scheduled for Tuesday in week 1. Next up is Wednesday."),
        // Sunday 09-20 and Monday 09-21 are both week 1 there, yet Monday is off the Monday strip.
        Row(.monday, block: 16, today: 20, "Nothing scheduled for Sunday in week 1. Next up is next Monday."),
        Row(.sunday, block: 16, today: 20, "Nothing scheduled for Sunday in week 1. Next up is Monday.")
    ]

    @Test(
        "The rest-day body says next only for a session off the strip, whichever program week it is in",
        arguments: rows
    )
    func restBody_saysNextOnlyOffTheStrip(_ row: Row) throws {
        let program = try Support.seed(start: Support.civil(2026, 9, row.blockStart))
        let input = try Support.input(
            program,
            now: Support.moment(Support.civil(2026, 9, row.today)),
            settings: Support.settings(weekStart: row.weekStart)
        )
        #expect(try Support.rest(TodayPresentation.make(input)).body == row.body)
    }

    @Test(
        "A next session exactly seven days away is next Monday whatever the week starts on",
        arguments: Weekday.allCases
    )
    func sevenDaysAway_isNextWeekday(_ weekStart: Weekday) throws {
        var program = try Support.seed()
        program.weeks[0].schedule = [:]
        let settings = Support.settings(weekStart: weekStart)
        let monday = try Support.input(program, now: Support.moment(Support.civil(2026, 9, 14)), settings: settings)
        let body = try Support.rest(TodayPresentation.make(monday)).body
        #expect(body == "Nothing scheduled for Monday in week 1. Next up is next Monday.")
        // Six days away, on Sunday 09-20: on screen only when the strip begins today.
        program.weeks[0].schedule = [.sunday: program.days[3].id]
        let again = try Support.input(program, now: Support.moment(Support.civil(2026, 9, 14)), settings: settings)
        let next = weekStart == .monday ? "Sunday" : "next Sunday"
        #expect(try Support.rest(TodayPresentation.make(again)).body
            == "Nothing scheduled for Monday in week 1. Next up is \(next).")
    }

    /// A block that trains once a week, on a weekday that moves from week to week, with two weeks empty.
    static func sparse(start: CivilDate) throws -> Program {
        var program = try Support.seed(start: start)
        for index in program.weeks.indices {
            let weekday = Weekday(rawValue: (index * 3) % 7 + 1) ?? .monday
            program.weeks[index].schedule = index == 2 || index == 5 ? [:] : [weekday: program.days[index % 4].id]
        }
        return program
    }

    @Test(
        "Every rest day of two blocks, begun on every weekday, reads the body of criteria 15 to 17",
        arguments: Weekday.allCases
    )
    func everyRestDay_readsTheRuledBody(_ weekStart: Weekday) throws {
        var lines: [String] = []
        var checked = 0
        for shift in 0 ..< 7 {
            let start = try #require(Support.civil(2026, 9, 14).adding(days: shift))
            for program in try [Support.seed(start: start), Self.sparse(start: start)] {
                for offset in -3 ..< 56 {
                    let today = try #require(start.adding(days: offset))
                    let input = try Support.input(
                        program,
                        now: Support.moment(today),
                        settings: Support.settings(weekStart: weekStart)
                    )
                    guard case let .restDay(card) = TodayPresentation.make(input).card else {
                        continue
                    }
                    checked += 1
                    let expected = try #require(TodayOracle(input)?.restBody(for: input))
                    if card.body != expected {
                        lines.append("block from \(start), \(today): \"\(card.body)\", expected \"\(expected)\"")
                    }
                }
            }
        }
        let holds = lines.isEmpty
        #expect(holds, "\(lines.count) of \(checked) rest days:\n\(lines.prefix(5).joined(separator: "\n"))")
        #expect(checked > 400)
        print("TodayNextAdversarialTests week from \(weekStart): \(checked) rest days")
    }
}
