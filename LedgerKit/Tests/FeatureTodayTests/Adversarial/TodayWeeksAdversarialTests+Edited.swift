@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Edited blocks (S3 criteria 5, 6 and 12): the rest-day copy in each of its three forms and the Logged card's
/// "Next:" line, driven by where the next session really is.
nonisolated extension TodayWeeksAdversarialTests {
    static let restDays = [
        Row(9, 15, "Rest day", 14, "PTP.PP.", "/4", "Nothing scheduled for Tuesday in week 1. Next up is Wednesday."),
        Row(9, 17, "Rest day", 14, "P.PTPP.", "/4", "Nothing scheduled for Thursday in week 1. Next up is Friday."),
        Row(9, 20, "Rest day", 14, "P.P.PPT", "/4", "Nothing scheduled for Sunday in week 1. Next up is next Monday."),
        Row(11, 1, "Rest day", 26, "P.P.PPT", "/4", "Nothing scheduled for Sunday in week 7. Next up is next Monday."),
        Row(11, 3, "Rest day", 2, "PTP.P..", "/3", "Nothing scheduled for Tuesday in week 8. Next up is Wednesday."),
        Row(11, 5, "Rest day", 2, "P.PTP..", "/3", "Nothing scheduled for Thursday in week 8. Next up is Friday.")
    ]

    @Test("A rest day names its weekday, its program week and where the next session is", arguments: restDays)
    func restDay_namesTheNextSession(_ row: Row) throws {
        try Self.check(row, Support.seed())
    }

    /// Week 3 trains nothing: Sunday 09-27 closes week 2 and Monday 10-05 opens week 4.
    static let aroundAnEmptyWeek = [
        Row(9, 27, "Rest day", 21, "P.P.PPT", "/4", "Nothing scheduled for Sunday in week 2. Next up is next Monday."),
        Row(
            9,
            30,
            "Rest day",
            28,
            "..T....",
            "/0",
            "Nothing scheduled for Wednesday in week 3. Next up is next Monday."
        ),
        Row(10, 4, "Rest day", 28, "......T", "/0", "Nothing scheduled for Sunday in week 3. Next up is next Monday."),
        Row(10, 5, "Upper A", 5, "T.P.PP.", "/4", "Week 4 of 8 · ~39 min")
    ]

    @Test(
        "A week with no sessions: no planned marks, 0 planned, and the next session is still next Monday",
        arguments: aroundAnEmptyWeek
    )
    func emptyWeek_isAllRestAndPointsPastItself(_ row: Row) throws {
        var program = try Support.seed()
        program.weeks[2].schedule = [:]
        try Self.check(row, program)
    }

    static let oneWeekBlock = [
        Row(9, 16, "Lower A", 14, "P.T.PP.", "/4", "Week 1 of 1 · ~38 min"),
        Row(9, 20, "Rest day", 14, "P.P.PPT", "/4", "Nothing scheduled for Sunday in week 1. \(lastWeek)"),
        Row(9, 21, "Today", 21, "T......", "/0", "1 week done. Start the next block from Program.")
    ]

    @Test("A block of one week counts itself in the singular and ends after seven days", arguments: oneWeekBlock)
    func blockOfOneWeek_endsAfterSevenDays(_ row: Row) throws {
        var program = try Support.seed()
        program.weeks = [program.weeks[0]]
        try Self.check(row, program)
    }

    @Test("When no session is left before the last week, the rest day says nothing is left")
    func nothingLeftBeforeTheLastWeek_saysSo() throws {
        var program = try Support.seed()
        for index in 1 ..< 8 {
            program.weeks[index].schedule = [:]
        }
        let row = Row(
            9,
            20,
            "Rest day",
            14,
            "P.P.PPT",
            "/4",
            "Nothing scheduled for Sunday in week 1. \(Self.lastWeek)"
        )
        try Self.check(row, program)
    }

    @Test(
        "A day before the block is a rest day that speaks of the block's first week and its first session",
        arguments: [
            2, 12
        ]
    )
    func beforeTheBlock_isARestDayOfWeekOne(_ daysBefore: Int) throws {
        let program = try Support.seed(start: Support.civil(2026, 9, 16 + daysBefore))
        let model = try TodayPresentation.make(Support.input(program, now: Support.moment(Support.civil(2026, 9, 16))))
        let card = try Support.rest(model)
        #expect(model.header.title == "Rest day")
        // The block's first day is a Friday (09-18) or a Monday (09-28); Friday trains Upper B, Monday Upper A.
        let first = daysBefore == 2 ? "Friday" : "Monday"
        #expect(card.body.hasPrefix("Nothing scheduled for Wednesday in week 1. Next up is "), "\(card.body)")
        #expect(card.body.hasSuffix(" \(first).") || card.body.hasSuffix(" next \(first)."), "\(card.body)")
        #expect(card.editWeek.route == .editWeek(program: program.id, weekIndex: 0))
        #expect(card.offSchedule.subtitle == "Pick a day from week 1.")
        #expect(card.offSchedule.days.map(\.route)
            == program.days.map { .startWorkout(program: program.id, weekIndex: 0, day: $0.id) })
        let marks = String(model.weekStrip.map { Self.letter($0.mark) })
        #expect(marks == (daysBefore == 2 ? "..T.PP." : "..T...."))
        #expect(model.stats.sessions.unit == (daysBefore == 2 ? "/2" : "/0"))
        print("TodayWeeksAdversarialTests, \(daysBefore) days before the block: \(card.body)")
    }

    /// A day's session logged that day, and the "Next:" line under it (nil when the block has none left).
    struct Next: Sendable, CustomStringConvertible {
        let month: Int
        let day: Int
        let tag: String
        let week: Int
        let next: String?
        var start = 14

        var description: String {
            "\(tag) logged on 2026-\(month)-\(day) → \(next ?? "nil")"
        }
    }

    static let nextLines = [
        Next(month: 9, day: 14, tag: "UA", week: 0, next: "Next: Wednesday · LA"),
        Next(month: 9, day: 18, tag: "UB", week: 0, next: "Next: Saturday · LB"),
        Next(month: 9, day: 19, tag: "LB", week: 0, next: "Next: week 2"),
        Next(month: 10, day: 31, tag: "LB", week: 6, next: "Next: week 8"),
        Next(month: 11, day: 2, tag: "UA", week: 7, next: "Next: Wednesday · LA"),
        Next(month: 11, day: 6, tag: "UB", week: 7, next: nil),
        // The block begun on Wednesday 09-16: Monday 09-21 is still week 1, Wednesday 09-23 opens week 2.
        Next(month: 9, day: 19, tag: "LB", week: 0, next: "Next: Monday · UA", start: 16),
        Next(month: 9, day: 21, tag: "UA", week: 0, next: "Next: week 2", start: 16)
    ]

    @Test(
        "The Logged card's Next line names the next session's weekday and tag, or the later week",
        arguments: nextLines
    )
    func loggedCard_namesTheNextSession(_ row: Next) throws {
        let program = try Support.seed(start: Support.civil(2026, 9, row.start))
        let start = try Support.moment(Support.civil(2026, row.month, row.day), 6)
        let done = try Support.finished(Support.live(program, week: row.week, tag: row.tag, number: 9, start: start))
        let input = try Support.input(program, now: start.addingTimeInterval(4 * 3600), week: [done])
        let card = try Support.logged(TodayPresentation.make(input))
        #expect(card.next == row.next)
        #expect(card.eyebrow == "LOGGED · WEEK \(row.week + 1)")
    }

    @Test("With an empty week ahead, the Next line still names a later week")
    func loggedBeforeAnEmptyWeek_namesALaterWeek() throws {
        var program = try Support.seed()
        program.weeks[2].schedule = [:]
        let start = try Support.moment(Support.civil(2026, 9, 26), 6)
        let done = try Support.finished(Support.live(program, week: 1, tag: "LB", number: 9, start: start))
        let input = try Support.input(program, now: start.addingTimeInterval(4 * 3600), week: [done])
        let next = try Support.logged(TodayPresentation.make(input)).next
        // The brief says "Next: week {n+1}" (3, which trains nothing); the next session is in week 4.
        #expect(next == "Next: week 3" || next == "Next: week 4", "\(next ?? "nil")")
        print("TodayWeeksAdversarialTests, logged before an empty week: \(next ?? "nil")")
    }
}
