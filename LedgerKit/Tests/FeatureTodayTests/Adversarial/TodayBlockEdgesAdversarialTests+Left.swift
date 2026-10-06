@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Criterion 17 at its boundary: the last week, the week before it, a block of one session, a block of two
/// weeks, and a block begun on a Wednesday, whose last week is not the strip's.
nonisolated extension TodayBlockEdgesAdversarialTests {
    typealias Row = TodayWeeksAdversarialTests.Row

    static let noneLeft = "No sessions are left in this block."
    static let lastWeek = "This is the last week of the block."

    /// The seed with week 8 emptied: Saturday 10-31 is the block's last session.
    static let emptyLastWeek = [
        Row(11, 1, "Rest day", 26, "P.P.PPT", "/4", "Nothing scheduled for Sunday in week 7. \(noneLeft)"),
        Row(11, 2, "Rest day", 2, "T......", "/0", "Nothing scheduled for Monday in week 8. \(lastWeek)"),
        Row(11, 8, "Rest day", 2, "......T", "/0", "Nothing scheduled for Sunday in week 8. \(lastWeek)"),
        Row(11, 9, "Today", 9, "T......", "/0", "8 weeks done. Start the next block from Program.")
    ]

    @Test(
        "With the last week emptied, the week before says no sessions are left and the last week says it is the last",
        arguments: emptyLastWeek
    )
    func lastWeekEmptied_tellsTheTwoWeeksApart(_ row: Row) throws {
        var program = try Support.seed()
        program.weeks[7].schedule = [:]
        try Weeks.check(row, program)
    }

    /// Eight weeks that train once, on Monday 09-14.
    static let oneSession = [
        Row(9, 14, "Upper A", 14, "T......", "/1", "Week 1 of 8 · ~39 min"),
        Row(9, 15, "Rest day", 14, "PT.....", "/1", "Nothing scheduled for Tuesday in week 1. \(noneLeft)"),
        Row(10, 14, "Rest day", 12, "..T....", "/0", "Nothing scheduled for Wednesday in week 5. \(noneLeft)"),
        Row(11, 1, "Rest day", 26, "......T", "/0", "Nothing scheduled for Sunday in week 7. \(noneLeft)"),
        Row(11, 2, "Rest day", 2, "T......", "/0", "Nothing scheduled for Monday in week 8. \(lastWeek)")
    ]

    @Test(
        "A block of one session has none left from its second day, and a last week all the same",
        arguments: oneSession
    )
    func blockOfOneSession_hasNoneLeftFromItsSecondDay(_ row: Row) throws {
        var program = try Support.seed()
        for index in program.weeks.indices {
            program.weeks[index].schedule = index == 0 ? [.monday: program.days[0].id] : [:]
        }
        try Weeks.check(row, program)
    }

    @Test("A block of two weeks whose second trains nothing: none left in week 1, the last week in week 2")
    func twoWeeksSecondEmpty_tellsThemApart() throws {
        var program = try Support.seed()
        program.weeks = Array(program.weeks.prefix(2))
        program.weeks[1].schedule = [:]
        let sunday = Row(
            9,
            20,
            "Rest day",
            14,
            "P.P.PPT",
            "/4",
            "Nothing scheduled for Sunday in week 1. \(Self.noneLeft)"
        )
        let monday = Row(
            9,
            21,
            "Rest day",
            21,
            "T......",
            "/0",
            "Nothing scheduled for Monday in week 2. \(Self.lastWeek)"
        )
        try Weeks.check(sunday, program)
        try Weeks.check(monday, program)
        // The block's only remaining session, logged: the card has no Next line.
        let start = try Support.moment(Support.civil(2026, 9, 19), 6)
        let done = try Support.finished(Support.live(program, week: 0, tag: "LB", number: 9, start: start))
        let input = try Support.input(program, now: start.addingTimeInterval(3600 * 4), week: [done])
        #expect(try Support.logged(TodayPresentation.make(input)).next == nil)
    }

    /// The block begun on Wednesday 09-16 with week 8 emptied: week 7 ends on Tuesday 11-03 and week 8 begins
    /// on Wednesday 11-04, inside one Monday strip.
    static let shifted = [
        Row(11, 3, "Rest day", 2, "PT.....", "/1", "Nothing scheduled for Tuesday in week 7. \(noneLeft)"),
        Row(11, 4, "Rest day", 2, "P.T....", "/1", "Nothing scheduled for Wednesday in week 8. \(lastWeek)"),
        Row(11, 10, "Rest day", 9, ".T.....", "/0", "Nothing scheduled for Tuesday in week 8. \(lastWeek)")
    ]

    @Test("The last week is the program's, not the strip's: a block begun on a Wednesday", arguments: shifted)
    func lastWeek_isTheProgramsWeek(_ row: Row) throws {
        var program = try Support.seed(start: Support.civil(2026, 9, 16))
        program.weeks[7].schedule = [:]
        try Weeks.check(row, program)
    }

    @Test("The two endings change at the first instant of the last week, in a zone far from UTC", arguments: [
        "Pacific/Kiritimati", "Etc/GMT+12", "America/Santiago"
    ])
    func endings_changeAtTheFirstInstantOfTheLastWeek(_ identifier: String) throws {
        let zone = try Support.zone(identifier)
        var program = try Support.seed()
        program.weeks[7].schedule = [:]
        let monday = try Support.civil(2026, 11, 2).startOfDay(in: Support.calendar(zone))
        let before = try Support.rest(TodayPresentation.make(Support.input(
            program,
            now: monday.addingTimeInterval(-1),
            zone: zone
        )))
        #expect(before.body == "Nothing scheduled for Sunday in week 7. \(Self.noneLeft)")
        let after = try Support.rest(TodayPresentation.make(Support.input(program, now: monday, zone: zone)))
        #expect(after.body == "Nothing scheduled for Monday in week 8. \(Self.lastWeek)")
    }
}
