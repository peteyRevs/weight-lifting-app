import Foundation
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F12 S2 adversarial round 1 (G2), N9 where the implementer's differential is silent: it runs in UTC from Monday
/// only. Here the fold the history screen uses (`ExerciseHistory.make(…weekStart:calendar:)`, weeks from the Unix
/// epoch) is checked against GRDB's `e1RMByWeek` with a program's `WeekCalendar` (started 2026-08-17), in time
/// zones with a change of clocks (New York, Santiago, whose midnight is skipped, Lord Howe's half hour) and weeks
/// from Monday, Sunday and Saturday, with sessions at the first and last minute of the days around each change and
/// `now` on either side of it.
@Suite("Adversarial F12 S2 · the fold's weeks against e1RMByWeek", .tags(.persistence))
struct ExerciseHistoryWeeksAdversarialTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let zone: String
        let weekStart: Weekday
        /// The local day of the change of clocks.
        let change: DateComponents

        var testDescription: String {
            "\(zone) from \(weekStart), change \(change.year ?? 0)-\(change.month ?? 0)-\(change.day ?? 0)"
        }
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day, hour: 12)
    }

    static let cases: [Case] = ["America/New_York", "America/Santiago", "Australia/Lord_Howe", "UTC"].flatMap { zone in
        [Weekday.monday, .sunday, .saturday].flatMap { start in
            let changes: [DateComponents] = switch zone {
            case "America/New_York": [day(2026, 3, 8), day(2026, 11, 1)]
            case "America/Santiago": [day(2026, 9, 6), day(2026, 4, 5)]
            case "Australia/Lord_Howe": [day(2026, 10, 4), day(2026, 4, 5)]
            default: [day(2026, 12, 31)]
            }
            return changes.map { Case(zone: zone, weekStart: start, change: $0) }
        }
    }

    /// The first minute (or the first that exists) and the last minute of each day from 10 days before `change`
    /// to 10 after.
    static func starts(around change: Date, in gregorian: Calendar) throws -> [Date] {
        try (-10 ... 10).flatMap { offset in
            let noon = try #require(gregorian.date(byAdding: .day, value: offset, to: change))
            let midnight = gregorian.startOfDay(for: noon)
            let next = try #require(gregorian.date(byAdding: .day, value: 1, to: midnight))
            return [midnight, gregorian.startOfDay(for: next).addingTimeInterval(-60)]
        }
    }

    /// What the fold says of the weeks at `now` that `e1RMByWeek` does not, or that `WeekCalendar` does not.
    static func mismatches(_ test: Case, _ stack: S3Kit.Stack, now: Date, zone: Calendar) async throws -> [String] {
        let gregorian = zone
        let stats = stack.stats(now: now)
        let calendar = S3Kit.calendar(test.zone, weekStart: test.weekStart)
        let history = try await ExerciseHistory.make(
            sessions: stats.exerciseSessions(exerciseID: S3Kit.bench),
            records: [],
            now: now,
            weekStart: test.weekStart,
            calendar: gregorian
        )
        var found: [String] = []
        let folded = Dictionary(history.weeks.compactMap { week in
            week.e1RM.map { (calendar.isoWeekKey(for: week.start), $0) }
        }) { first, _ in first }
        let queried = try await stats.e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: 8, calendar: calendar)
        if folded != queried {
            found.append("now \(now): fold \(folded.sorted { $0.key < $1.key }), "
                + "query \(queried.sorted { $0.key < $1.key })")
        }
        // Each week starts at the start of its own first day, on the Settings' day, and they are contiguous.
        for (week, next) in zip(history.weeks, history.weeks.dropFirst()) {
            let range = calendar.week(containing: week.start)
            if range.lowerBound != week.start || range.upperBound != next.start {
                found.append("now \(now): week \(week.start) is not \(range)")
            }
        }
        return found
    }

    @Test("The fold's eight weeks are e1RMByWeek's, around a change of clocks", arguments: cases)
    func foldWeeks_matchE1RMByWeek_aroundAChangeOfClocks(_ test: Case) async throws {
        let zone = try #require(TimeZone(identifier: test.zone))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = zone
        let change = try #require(gregorian.date(from: test.change))
        let stack = try await S3Kit.stack()
        // Each session heavier by 1 lb than the one before.
        for (number, start) in try Self.starts(around: change, in: gregorian).enumerated() {
            try await stack.materialize(S3Kit.workout(number, endedAt: start.addingTimeInterval(45 * 60), [
                S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(Decimal(150 + number), 5)])
            ]))
        }
        var found: [String] = []
        // `now` a week before the change, on its day, and two and five weeks after.
        for weeksAfter in [-1, 0, 2, 5] {
            let now = change.addingTimeInterval(Double(weeksAfter) * 7 * 86400)
            found += try await Self.mismatches(test, stack, now: now, zone: gregorian)
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }
}
