@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: program weeks against stats weeks (S3 criteria 2, 3, 6, 7, 8 and 12). The block's first and
/// last day, a block begun on another weekday than the week starts on (the strip then straddles two program
/// weeks), a week with no sessions, a block of one week and a block that has not begun. Expectations are worked
/// out by hand from the seed schedule: Mon UA · Wed LA · Fri UB · Sat LB, and Mon · Wed · Fri in week 8.
@Suite("Adversarial F09 S3 · program weeks and stats weeks", .tags(.feature))
nonisolated struct TodayWeeksAdversarialTests {
    typealias Support = TodayAdversarial

    /// One day of 2026, and what Today shows on it. `marks` spells the strip from `first`: T today, P planned,
    /// D done, a dot for rest. `line` is the Up-next meta, the rest-day body or the block-complete body.
    struct Row: Sendable, CustomStringConvertible {
        let month: Int
        let day: Int
        let title: String
        let first: Int
        let marks: String
        let planned: String
        let line: String

        init(
            _ month: Int,
            _ day: Int,
            _ title: String,
            _ first: Int,
            _ marks: String,
            _ planned: String,
            _ line: String
        ) {
            self.month = month
            self.day = day
            self.title = title
            self.first = first
            self.marks = marks
            self.planned = planned
            self.line = line
        }

        var description: String {
            "2026-\(month)-\(day): \(title), \(marks) \(planned)"
        }
    }

    static func letter(_ mark: WeekStrip.Mark) -> Character {
        switch mark {
        case .today: "T"
        case .planned: "P"
        case .done: "D"
        case .rest: "."
        }
    }

    static func shownLine(_ card: TodayModel.Card) -> String {
        switch card {
        case let .upNext(shown): shown.meta ?? "no meta"
        case let .restDay(shown): shown.body
        case let .blockComplete(shown): shown.body
        case .logged, .noProgram: "another card"
        }
    }

    static func check(_ row: Row, _ program: Program, hour: Int = 12, week: [WorkoutState] = []) throws {
        let today = try Support.civil(2026, row.month, row.day)
        let model = try TodayPresentation.make(Support.input(program, now: Support.moment(today, hour), week: week))
        let monday = try #require(today.adding(days: 1 - today.weekday.rawValue))
        #expect(model.header.title == row.title)
        #expect(model.weekStrip.first?.date == String(row.first))
        #expect(model.weekStrip.map(\.date) == (0 ..< 7).compactMap { monday.adding(days: $0) }.map { String($0.day) })
        #expect(String(model.weekStrip.map { letter($0.mark) }) == row.marks)
        #expect(model.stats.sessions.unit == row.planned)
        #expect(shownLine(model.card) == row.line)
    }

    static let lastWeek = "This is the last week of the block."
    static let blockDone = "8 weeks done. Start the next block from Program."
    static let edges = [
        Row(9, 14, "Upper A", 14, "T.P.PP.", "/4", "Week 1 of 8 · ~39 min"),
        Row(11, 7, "Rest day", 2, "P.P.PT.", "/3", "Nothing scheduled for Saturday in week 8. \(lastWeek)"),
        Row(11, 8, "Rest day", 2, "P.P.P.T", "/3", "Nothing scheduled for Sunday in week 8. \(lastWeek)"),
        Row(11, 9, "Today", 9, "T......", "/0", blockDone)
    ]

    @Test("The block's first day, its last two days and the day after read as their own weeks", arguments: edges)
    func edgesOfTheBlock_readTheirOwnWeek(_ row: Row) throws {
        try Self.check(row, Support.seed(), hour: row.day == 14 ? 0 : 23)
    }

    /// The block begun on Wednesday 2026-09-16 with the week starting on Monday: program week n runs from a
    /// Wednesday to the next Tuesday, so every strip but the first holds two program weeks.
    /// - Monday 09-21 is still program week 1; Wednesday 09-23 opens week 2.
    /// - Tuesday 11-03 closes week 7; week 8 (deload, no Saturday) opens on Wednesday 11-04.
    /// - Monday 11-09 is week 8's Upper A, a deload; the block ends on Tuesday 11-10.
    static let straddling = [
        Row(9, 16, "Lower A", 14, "..T.PP.", "/3", "Week 1 of 8 · ~38 min"),
        Row(9, 21, "Upper A", 21, "T.P.PP.", "/4", "Week 1 of 8 · ~39 min"),
        Row(
            11,
            3,
            "Rest day",
            2,
            "PTP.P..",
            "/3",
            "Nothing scheduled for Tuesday in week 7. Next up is Wednesday."
        ),
        Row(11, 9, "Upper A", 9, "T......", "/1", "Week 8 of 8 · Deload · ~29 min"),
        Row(11, 10, "Rest day", 9, "PT.....", "/1", "Nothing scheduled for Tuesday in week 8. \(lastWeek)"),
        Row(11, 11, "Today", 9, "P.T....", "/1", blockDone)
    ]

    @Test(
        "A block begun on a Wednesday: each day of a straddling strip has its own program week",
        arguments: straddling
    )
    func blockBegunOnWednesday_usesEachDaysOwnWeek(_ row: Row) throws {
        try Self.check(row, Support.seed(start: Support.civil(2026, 9, 16)))
    }

    @Test("A block begun on a Wednesday: the routes and the sheet name the program week, not the strip's")
    func blockBegunOnWednesday_routesNameTheProgramWeek() throws {
        let program = try Support.seed(start: Support.civil(2026, 9, 16))
        let upperA = try Support.day("UA", in: program)
        let monday = try TodayPresentation.make(Support.input(program, now: Support.moment(Support.civil(2026, 9, 21))))
        #expect(try Support.upNext(monday).action.action.route
            == .startWorkout(program: program.id, weekIndex: 0, day: upperA.id))
        // Week 1's loads, not week 2's: bench 180, incline 50 × 10, row 65, pulldown 100 × 12, raise 12.5 × 15.
        let schemes = ["5 × 5 @ 180", "3 × 10 @ 50", "4 × 8 @ 65", "3 × 12 @ 100", "3 × 15 @ 12.5"]
        #expect(try Support.upNext(monday).rows.map(\.scheme) == schemes)
        let tuesday = try TodayPresentation.make(Support.input(
            program,
            now: Support.moment(Support.civil(2026, 11, 3))
        ))
        let rest = try Support.rest(tuesday)
        #expect(rest.editWeek.route == .editWeek(program: program.id, weekIndex: 6))
        #expect(rest.offSchedule.subtitle == "Pick a day from week 7.")
        #expect(rest.offSchedule.days.first?.route == .startWorkout(program: program.id, weekIndex: 6, day: upperA.id))
    }
}
