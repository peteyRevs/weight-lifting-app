import Foundation
@testable import LedgerDomain
import Testing

/// F13 S1 adversarial (G2): `HistoryWeeks.group` over every first day of the week, in zones whose clocks jump at
/// midnight (so a day can start at 01:00) or move by half an hour or 45 minutes from UTC, through
/// year ends. Every workout lands in the week that holds its start; weeks come newest first and never overlap; a week
/// starts on the lifter's first day, and its `lastDay` is six civil days after its first and inside it.
@Suite("Adversarial F13 S1 · history weeks across zones", .tags(.domain))
struct HistoryWeeksAdversarialTests {
    /// A zone, and an instant near its oddest clock change.
    struct Case: Sendable, CustomStringConvertible {
        let zone: String
        let around: Date
        var description: String {
            zone
        }
    }

    static func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    static let cases = [
        // The clocks jumped from 00:00 to 01:00: 2018-11-04 began at 01:00.
        Case(zone: "America/Sao_Paulo", around: utc(2018, 11, 4)),
        // Not Pacific/Apia's 2011-12-30, a day that never happened: a Friday-start week then begins on the
        // Saturday, and a Saturday-start week's `lastDay` is the next week's first instant (G2, informational).
        // Half-hour daylight saving.
        Case(zone: "Australia/Lord_Howe", around: utc(2026, 10, 4)),
        // A midnight change, in spring.
        Case(zone: "America/Havana", around: utc(2026, 3, 8)),
        // A year end, with a 45-minute offset.
        Case(zone: "Pacific/Chatham", around: utc(2026, 1, 1)),
        Case(zone: "America/New_York", around: utc(2026, 3, 8))
    ]

    /// Starts every 5 h 17 min over five weeks around the case's instant, newest first.
    static func starts(around date: Date) -> [Date] {
        stride(from: 17.5 * 86400, through: -17.5 * 86400, by: -(5 * 3600 + 17 * 60)).map {
            date.addingTimeInterval($0)
        }
    }

    static func entry(_ number: Int, _ startedAt: Date) -> HistoryEntry {
        HistoryEntry(
            id: WorkoutID(UUID(uuid: (
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                UInt8(number / 256),
                UInt8(number % 256)
            ))),
            name: "W\(number)",
            tag: "W",
            isDeload: false,
            startedAt: startedAt,
            elapsed: .seconds(3600),
            volume: .zero,
            doneSets: 0,
            totalSets: 0,
            prCount: 0
        )
    }

    /// What is wrong with the weeks of `case` for `weekStart`, or nil.
    static func firstIssue(_ case: Case, weekStart: Weekday) throws -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: `case`.zone))
        let entries = starts(around: `case`.around).enumerated().map { entry($0.offset, $0.element) }
        let weeks = HistoryWeeks.group(entries, weekStart: weekStart, calendar: calendar)
        guard weeks.flatMap(\.entries) == entries else {
            return "the entries changed order or count"
        }
        for (index, week) in weeks.enumerated() {
            if let outside = week.entries.first(where: { !week.bounds.contains($0.startedAt) }) {
                return "\(outside.startedAt) is outside its week \(week.bounds)"
            }
            if index > 0, weeks[index - 1].bounds.lowerBound < week.bounds.upperBound {
                return "week \(index) overlaps or follows the one before"
            }
            let weekday = calendar.component(.weekday, from: week.bounds.lowerBound)
            if Weekday(calendarWeekday: weekday) != weekStart {
                return "the week \(week.bounds) starts on weekday \(weekday)"
            }
            let days = CivilDate.dayNumber(of: week.lastDay, in: calendar)
                - CivilDate.dayNumber(of: week.bounds.lowerBound, in: calendar)
            if days != 6 || !week.bounds.contains(week.lastDay) {
                return "the week \(week.bounds) ends on \(week.lastDay), \(days) days on"
            }
        }
        return nil
    }

    @Test(
        "Every first day of the week, in zones with odd clocks: each workout in the week of its start",
        arguments: cases
    )
    func everyWeekStart_holdsItsWorkouts(_ case: Case) throws {
        for weekStart in Weekday.allCases {
            let issue = try Self.firstIssue(`case`, weekStart: weekStart)
            #expect(issue == nil, "\(weekStart): \(issue ?? "")")
        }
    }
}
