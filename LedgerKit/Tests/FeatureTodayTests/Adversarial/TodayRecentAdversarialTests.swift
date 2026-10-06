@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: the recent list (S3 criterion 9; the body's criterion 10). Order, the limit of five, "Today"
/// against a weekday, minutes against the clock form, volumes with their separators, a workout that crossed
/// midnight and two that started together. "Now" is Wednesday 2026-09-16, 12:00 UTC.
@Suite("Adversarial F09 S3 · the recent list", .tags(.feature))
nonisolated struct TodayRecentAdversarialTests {
    typealias Support = TodayAdversarial

    static func now() throws -> Date {
        try Support.moment(Support.civil(2026, 9, 16))
    }

    /// One finished workout of September 2026 that moved `weight` × `reps` pounds.
    struct Past: Sendable {
        let day: Int
        let hour: Int
        let seconds: Int
        let weight: Decimal
        let reps: Int
        let name: String

        init(_ day: Int, _ hour: Int, _ seconds: Int, _ weight: Decimal, _ reps: Int, _ name: String) {
            self.day = day
            self.hour = hour
            self.seconds = seconds
            self.weight = weight
            self.reps = reps
            self.name = name
        }
    }

    /// The brief's rows (spec §3.5) with a workout of today and three older ones: seven in all, newest first.
    static let history = [
        Past(16, 5, 24 * 60 + 22, 203, 40, "Lower A — Squat focus"),
        Past(14, 7, 58 * 60, 403, 60, "Lower A — Squat focus"),
        Past(13, 7, 49 * 60, 851, 20, "Upper B — Pull focus"),
        Past(11, 7, 61 * 60, 440, 60, "Lower B — Hinge focus"),
        Past(9, 7, 60 * 60, 100, 10, "Upper A — Push focus"),
        Past(8, 7, 60 * 60, 100, 10, "Too old to show"),
        Past(7, 7, 60 * 60, 100, 10, "Too old to show")
    ]

    static func workouts(_ rows: [Past]) throws -> [WorkoutState] {
        try rows.enumerated().map { index, row in
            try Support.lifted(
                number: 200 + index,
                start: Support.moment(Support.civil(2026, 9, row.day), row.hour),
                seconds: row.seconds,
                lifts: [.pounds(row.weight, row.reps)],
                name: row.name
            )
        }
    }

    @Test(
        "Criterion 10: of seven finished workouts the five newest are listed, text for text",
        arguments: Units.allCases
    )
    func sevenFinishedWorkouts_listTheFiveNewest(_ units: Units) throws {
        let recent = try Self.workouts(Self.history)
        let input = try Support.input(
            Support.seed(),
            now: Self.now(),
            settings: Support.settings(units),
            recent: recent
        )
        let list = TodayPresentation.make(input).recent
        // 8,120 lb = 3,683.2 kg; 24,180 = 10,967.9; 17,020 = 7,720.1; 26,400 = 11,974.8; 1,000 = 453.6.
        let pounds = [
            "Today · 24:22 · 8,120 lb", "Mon · 58 min · 24,180 lb", "Sun · 49 min · 17,020 lb",
            "Fri · 61 min · 26,400 lb",
            "Wed · 60 min · 1,000 lb"
        ]
        let kilograms = [
            "Today · 24:22 · 3,683 kg", "Mon · 58 min · 10,968 kg", "Sun · 49 min · 7,720 kg",
            "Fri · 61 min · 11,975 kg",
            "Wed · 60 min · 454 kg"
        ]
        #expect(list.eyebrow == "RECENT")
        #expect(list.rows.map(\.meta) == (units == .lb ? pounds : kilograms))
        #expect(list.rows.map(\.name) == Self.history.prefix(5).map(\.name))
        #expect(list.rows.map(\.route) == recent.prefix(5).map { .openWorkout($0.id) })
        #expect(list.emptyMessage == nil)
    }

    @Test("The list holds what it is given, up to five", arguments: [0, 1, 4, 5, 6, 7])
    func list_holdsAtMostFive(_ count: Int) throws {
        let recent = try Array(Self.workouts(Self.history).prefix(count))
        let list = try TodayPresentation.make(Support.input(Support.seed(), now: Self.now(), recent: recent)).recent
        #expect(list.rows.count == min(count, 5))
        #expect(list.emptyMessage == (count == 0 ? "No sessions yet. Your first workout lands here." : nil))
    }

    /// A workout by its start (day, hour, minute of September 2026, UTC) and its length, and the row's first two
    /// fragments. Its volume is always 1,000 lb.
    struct Timing: Sendable, CustomStringConvertible {
        let day: Int
        let hour: Int
        let minute: Int
        let seconds: Int
        let meta: String

        init(_ day: Int, _ hour: Int, _ minute: Int, _ seconds: Int, _ meta: String) {
            self.day = day
            self.hour = hour
            self.minute = minute
            self.seconds = seconds
            self.meta = meta
        }

        var description: String {
            "09-\(day) \(hour):\(minute) for \(seconds) s → \(meta)"
        }
    }

    static let timings = [
        // Today reads as the clock does; an hour and more gains the hours.
        Timing(16, 0, 0, 0, "Today · 0:00"),
        Timing(16, 0, 0, 59, "Today · 0:59"),
        Timing(16, 9, 0, 3599, "Today · 59:59"),
        Timing(16, 9, 0, 3600, "Today · 1:00:00"),
        Timing(16, 1, 0, 37325, "Today · 10:22:05"),
        // Another day reads its weekday and whole minutes, sixty and more included.
        Timing(15, 23, 59, 60, "Tue · 1 min"),
        Timing(15, 7, 0, 3600, "Tue · 60 min"),
        Timing(15, 7, 0, 7200, "Tue · 120 min"),
        // Decision #26: a workout is the day's on which it started, also when it ended today.
        Timing(15, 23, 30, 70 * 60, "Tue · 70 min"),
        Timing(9, 12, 0, 1800, "Wed · 30 min"),
        Timing(12, 7, 0, 1800, "Sat · 30 min"),
        Timing(10, 7, 0, 1800, "Thu · 30 min")
    ]

    @Test("A row reads Today and the clock, or the weekday it started and whole minutes", arguments: timings)
    func row_readsTodayOrTheWeekdayItStarted(_ row: Timing) throws {
        let start = try Support.moment(Support.civil(2026, 9, row.day), row.hour, row.minute)
        let workout = try Support.lifted(number: 300, start: start, seconds: row.seconds, lifts: [.pounds(100, 10)])
        let list = try TodayPresentation.make(Support.input(Support.seed(), now: Self.now(), recent: [workout])).recent
        #expect(list.rows.map(\.meta) == ["\(row.meta) · 1,000 lb"])
    }
}
