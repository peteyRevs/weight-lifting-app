@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2, round 2: criteria 16 and 17. Before the block the rest-day body is "Your block starts on
/// {date}." with the block's first day written as the header writes a date; with no session left it ends "This
/// is the last week of the block." in the last week and "No sessions are left in this block." in any earlier one.
@Suite("Adversarial F09 S3 round 2 · before the block and after its last session", .tags(.feature))
nonisolated struct TodayBlockEdgesAdversarialTests {
    typealias Support = TodayAdversarial
    typealias Weeks = TodayWeeksAdversarialTests

    /// A block's first day, a zone, how many days before it today is, and the date the sentence names.
    struct Before: Sendable, CustomStringConvertible {
        let zone: String
        let start: [Int]
        let daysBefore: Int
        let date: String

        init(_ zone: String, _ start: [Int], before daysBefore: Int, _ date: String) {
            self.zone = zone
            self.start = start
            self.daysBefore = daysBefore
            self.date = date
        }

        var description: String {
            "\(zone), \(daysBefore) day(s) before \(start)"
        }
    }

    static let befores = [
        Before("UTC", [2026, 9, 14], before: 1, "Monday, September 14"),
        Before("UTC", [2026, 9, 14], before: 7, "Monday, September 14"),
        Before("UTC", [2026, 9, 14], before: 365, "Monday, September 14"),
        Before("UTC", [2027, 2, 28], before: 366, "Sunday, February 28"),
        Before("Pacific/Kiritimati", [2026, 9, 14], before: 1, "Monday, September 14"),
        Before("Etc/GMT+12", [2026, 9, 14], before: 1, "Monday, September 14"),
        Before("Pacific/Chatham", [2026, 9, 28], before: 2, "Monday, September 28"),
        // Chile's clocks skip midnight on Sunday 2026-09-06: the block's first day begins at 01:00.
        Before("America/Santiago", [2026, 9, 6], before: 1, "Sunday, September 6"),
        Before("America/Santiago", [2026, 9, 6], before: 7, "Sunday, September 6"),
        // New York falls back on Sunday 11-01, Lord Howe springs forward on 10-04: a change lies in between.
        Before("America/New_York", [2026, 11, 2], before: 3, "Monday, November 2"),
        Before("Australia/Lord_Howe", [2026, 10, 5], before: 2, "Monday, October 5"),
        Before("America/Havana", [2026, 11, 1], before: 1, "Sunday, November 1")
    ]

    @Test(
        "Before the block the body is one sentence that names the block's first day, to the last second",
        arguments: befores
    )
    func beforeTheBlock_namesItsFirstDay(_ row: Before) throws {
        let zone = try Support.zone(row.zone)
        let start = try Support.civil(row.start[0], row.start[1], row.start[2])
        let program = try Support.seed(start: start)
        let today = try #require(start.adding(days: -row.daysBefore))
        for now in try [Support.moment(today, 0, 0, 1, in: zone), Support.moment(today, 23, 59, 59, in: zone)] {
            let model = try TodayPresentation.make(Support.input(program, now: now, zone: zone))
            let card = try Support.rest(model)
            #expect(card.body == "Your block starts on \(row.date).")
            #expect(model.header.title == "Rest day")
            #expect(card.editWeek == TodayModel.Action(
                title: "Edit this week",
                route: .editWeek(program: program.id, weekIndex: 0)
            ))
            #expect(card.offSchedule.subtitle == "Pick a day from week 1.")
            #expect(card.offSchedule.days.map(\.route)
                == program.days.map { .startWorkout(program: program.id, weekIndex: 0, day: $0.id) })
        }
        // The block's first instant: the sentence is gone.
        let first = start.startOfDay(in: Support.calendar(zone))
        let begun = try TodayPresentation.make(Support.input(program, now: first, zone: zone))
        let line = Weeks.shownLine(begun.card)
        #expect(!line.hasPrefix("Your block starts"), "\(line)")
        #expect(line.hasPrefix("Week 1 of 8 · ") || line.hasPrefix("Nothing scheduled for "), "\(line)")
    }

    @Test("The sentence names the block's first day, not its first session, and writes it as the header would")
    func beforeTheBlock_namesTheStartNotTheFirstSession() throws {
        var program = try Support.seed(start: Support.civil(2026, 9, 28))
        program.weeks[0].schedule[.monday] = nil
        let now = try Support.moment(Support.civil(2026, 9, 20))
        var input = try Support.input(program, now: now)
        #expect(try Support.rest(TodayPresentation.make(input)).body == "Your block starts on Monday, September 28.")
        // A block that trains nothing at all still begins.
        for index in program.weeks.indices {
            program.weeks[index].schedule = [:]
        }
        input.program = program
        #expect(try Support.rest(TodayPresentation.make(input)).body == "Your block starts on Monday, September 28.")
        // In another locale the date is that locale's, as the header's is.
        input.locale = Locale(identifier: "fr_FR")
        let style = Date.FormatStyle(locale: input.locale, calendar: Support.calendar(), timeZone: Support.utc)
        let first = try Support.moment(Support.civil(2026, 9, 28)).formatted(style.weekday(.wide).month(.wide).day())
        let french = TodayPresentation.make(input)
        #expect(try Support.rest(french).body == "Your block starts on \(first).")
        #expect(french.header.date == now.formatted(style.weekday(.wide).month(.wide).day()))
    }

    @Test("A live workout before the block still takes the card")
    func liveBeforeTheBlock_takesTheCard() throws {
        let program = try Support.seed(start: Support.civil(2026, 9, 28))
        let now = try Support.moment(Support.civil(2026, 9, 20))
        let live = try Support.live(program, week: 0, tag: "UA", number: 5, start: now.addingTimeInterval(-60))
        let model = try TodayPresentation.make(Support.input(program, now: now, session: live))
        #expect(try Support.upNext(model).action.action == TodayModel.Action(
            title: "Resume · 1:00",
            route: .resumeWorkout
        ))
        #expect(model.header.title == "Rest day")
    }
}
