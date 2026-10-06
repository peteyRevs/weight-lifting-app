@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: which calendar day a moment is (S3 criteria 1 and 2). The far ends of the time zones, the
/// second before and after midnight, days whose clocks change (at midnight in several zones), leap day and the
/// turn of the year. The seed program begins on Monday 2026-09-14 unless a test says otherwise.
@Suite("Adversarial F09 S3 · the day a moment falls on", .tags(.feature))
nonisolated struct TodayDatesAdversarialTests {
    typealias Support = TodayAdversarial

    /// A UTC instant and what a clock `offset` seconds from UTC shows for it, worked out by hand.
    struct Row: Sendable, CustomStringConvertible {
        let offset: Int
        let day: Int
        let hour: Int
        var minute = 0
        var second = 0
        let date: String
        let title: String

        var description: String {
            "UTC\(offset >= 0 ? "+" : "")\(offset / 3600) at 09-\(day) \(hour):\(minute):\(second)Z → \(date)"
        }
    }

    static let wednesday = "Wednesday, September 16"
    static let rows = [
        // UTC+14 (Kiritimati): Wednesday runs from Tuesday 10:00Z to Wednesday 10:00Z.
        Row(
            offset: 14 * 3600,
            day: 15,
            hour: 9,
            minute: 59,
            second: 59,
            date: "Tuesday, September 15",
            title: "Rest day"
        ),
        Row(offset: 14 * 3600, day: 15, hour: 10, date: wednesday, title: "Lower A"),
        Row(offset: 14 * 3600, day: 16, hour: 9, minute: 59, second: 59, date: wednesday, title: "Lower A"),
        Row(offset: 14 * 3600, day: 16, hour: 10, date: "Thursday, September 17", title: "Rest day"),
        // UTC−12: Wednesday runs from Wednesday 12:00Z to Thursday 12:00Z.
        Row(
            offset: -12 * 3600,
            day: 16,
            hour: 11,
            minute: 59,
            second: 59,
            date: "Tuesday, September 15",
            title: "Rest day"
        ),
        Row(offset: -12 * 3600, day: 16, hour: 12, date: wednesday, title: "Lower A"),
        Row(offset: -12 * 3600, day: 17, hour: 11, minute: 59, second: 59, date: wednesday, title: "Lower A"),
        Row(offset: -12 * 3600, day: 17, hour: 12, date: "Thursday, September 17", title: "Rest day"),
        // UTC+5:45 (Kathmandu): Wednesday begins on Tuesday at 18:15Z.
        Row(offset: 20700, day: 15, hour: 18, minute: 14, second: 59, date: "Tuesday, September 15", title: "Rest day"),
        Row(offset: 20700, day: 15, hour: 18, minute: 15, date: wednesday, title: "Lower A"),
        // UTC: the second before midnight and midnight itself.
        Row(offset: 0, day: 15, hour: 23, minute: 59, second: 59, date: "Tuesday, September 15", title: "Rest day"),
        Row(offset: 0, day: 16, hour: 0, date: wednesday, title: "Lower A")
    ]

    @Test("A moment is the day the injected zone's clock shows, to the second", arguments: rows)
    func moment_isTheDayOfTheInjectedZone(_ row: Row) throws {
        let zone = try #require(TimeZone(secondsFromGMT: row.offset))
        let now = try Support.moment(Support.civil(2026, 9, row.day), row.hour, row.minute, row.second)
        let model = try TodayPresentation.make(Support.input(Support.seed(), now: now, zone: zone))
        #expect(model.header.date == row.date)
        #expect(model.header.title == row.title)
        #expect(model.weekStrip.map(\.date) == ["14", "15", "16", "17", "18", "19", "20"])
        let today = model.weekStrip.firstIndex { $0.mark == .today }
        #expect(today == ["Tuesday": 1, "Wednesday": 2, "Thursday": 3][String(row.date.prefix { $0 != "," })])
    }

    /// Every weekday trains, so every day of the block has a session and a wrong day shows as a wrong title.
    static func dailyProgram(start: CivilDate) throws -> Program {
        var program = try Support.seed(start: start)
        for index in program.weeks.indices {
            for weekday in Weekday.allCases {
                program.weeks[index].schedule[weekday] = program.days[(weekday.rawValue - 1) % 4].id
            }
        }
        return program
    }

    /// The civil day a clock in `zone` shows at `date`, by adding the zone's offset: no calendar in `zone`.
    static func civilByOffset(_ date: Date, _ zone: TimeZone) throws -> CivilDate {
        let shifted = date.addingTimeInterval(TimeInterval(zone.secondsFromGMT(for: date)))
        let parts = Support.calendar().dateComponents([.year, .month, .day], from: shifted)
        return try Support.civil(#require(parts.year), #require(parts.month), #require(parts.day))
    }

    static let changingZones = [
        "America/Santiago", "Africa/Cairo", "America/Havana", "Asia/Beirut", "Australia/Lord_Howe", "Pacific/Chatham",
        "America/St_Johns", "Europe/London", "America/New_York", "Europe/Lisbon", "America/Sao_Paulo"
    ]

    @Test(
        "Around every clock change of 2026 the day, the title and the strip follow the zone's clock",
        arguments: changingZones
    )
    func aroundAClockChange_theDayFollowsTheClock(_ identifier: String) throws {
        let zone = try Support.zone(identifier)
        var cursor = try Support.moment(Support.civil(2026, 1, 1), 0)
        let end = try Support.moment(Support.civil(2027, 1, 1), 0)
        var lines: [String] = []
        var checked = 0
        while let change = zone.nextDaylightSavingTimeTransition(after: cursor), change < end {
            cursor = change
            for shift in [-86400.0, -3601, -1, 0, 1, 3599, 3600, 86399] {
                let now = change.addingTimeInterval(shift)
                let today = try Self.civilByOffset(now, zone)
                let program = try Self.dailyProgram(start: #require(today.adding(days: -10)))
                let input = try Support.input(program, now: now, zone: zone)
                let model = TodayPresentation.make(input)
                let title = program.days[(today.weekday.rawValue - 1) % 4].shortTitle
                let monday = try #require(today.adding(days: 1 - today.weekday.rawValue))
                let numbers = (0 ..< 7).compactMap { monday.adding(days: $0) }.map { String($0.day) }
                let shown = [model.header.date, model.header.title] + model.weekStrip.map(\.date)
                if shown != [Support.fullDate(today), title] + numbers {
                    lines.append("\(identifier) \(now): \(model.header.date) / \(model.header.title)")
                }
                lines += try #require(TodayOracle(input)).problems(in: model, for: input).prefix(2)
                checked += 1
            }
        }
        let holds = lines.isEmpty
        print("TodayDatesAdversarialTests \(identifier): \(checked) moments around the clock changes of 2026")
        #expect(holds, "\(lines.count) problem(s) in \(checked) moments:\n\(lines.prefix(6).joined(separator: "\n"))")
    }

    @Test("Leap day is a day of its own in the header and the strip")
    func leapDay_isADay() throws {
        let program = try Support.seed(start: Support.civil(2028, 2, 28))
        let now = try Support.moment(Support.civil(2028, 2, 29), 23, 59, 59)
        let model = try TodayPresentation.make(Support.input(program, now: now))
        #expect(model.header.date == "Tuesday, February 29")
        #expect(model.header.title == "Rest day")
        #expect(model.weekStrip.map(\.date) == ["28", "29", "1", "2", "3", "4", "5"])
        #expect(model.weekStrip.map(\.mark) == [.planned, .today, .planned, .rest, .planned, .planned, .rest])
        #expect(try Support.rest(model).body == "Nothing scheduled for Tuesday in week 1. Next up is Wednesday.")
        #expect(model.weekStrip[2].accessibilitySummary == "Wednesday, March 1")
    }

    @Test("A week that crosses the turn of the year keeps its seven days and its program week")
    func turnOfTheYear_keepsTheWeek() throws {
        let program = try Support.seed(start: Support.civil(2026, 12, 28))
        let now = try Support.moment(Support.civil(2027, 1, 1), 0, 0, 1)
        let model = try TodayPresentation.make(Support.input(program, now: now))
        #expect(model.header.date == "Friday, January 1")
        #expect(model.header.title == "Upper B")
        #expect(model.weekStrip.map(\.date) == ["28", "29", "30", "31", "1", "2", "3"])
        #expect(model.weekStrip.map(\.mark) == [.planned, .rest, .planned, .rest, .today, .planned, .rest])
        // Pull-up 4×(42+150) + press 4×(42+120) + row 3×(42+90) + curl (3+1)×42 + 4 rounds×60 = 2220 s → 37.
        #expect(try Support.upNext(model).meta == "Week 1 of 8 · ~37 min")
        #expect(model.weekStrip[0].accessibilitySummary == "Monday, December 28")
    }
}
