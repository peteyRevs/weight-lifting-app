import Foundation
@testable import LedgerDomain
import Testing

/// F13 S1, N3: `HistoryWeeks.group`, the History list's weeks, and `HistoryEntry`'s fields computed from a workout
/// (N1). A workout is in the stats week of its start, on the lifter's first day of the week (decision #15).
@Suite("HistoryWeeks", .tags(.domain))
struct HistoryWeeksTests {
    /// An entry that started at `startedAt`, numbered so that ids differ.
    static func entry(_ number: Int, _ startedAt: Date) -> HistoryEntry {
        HistoryEntry(
            id: WorkoutID(Fixtures.uuid(7000 + number)),
            name: "Workout \(number)",
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

    @Test("Newest first: three weeks with a gap, each workout under the Monday week of its start, in the given order")
    func group_mondayStart_groupsByStatsWeek() {
        let entries = [
            Self.entry(1, Fixtures.date(2026, 9, 16, hour: 7)),
            Self.entry(2, Fixtures.date(2026, 9, 14, hour: 7)),
            Self.entry(3, Fixtures.date(2026, 9, 11, hour: 7)),
            Self.entry(4, Fixtures.date(2026, 9, 7, hour: 7)),
            Self.entry(5, Fixtures.date(2026, 8, 25, hour: 7))
        ]
        let weeks = HistoryWeeks.group(entries, weekStart: .monday, calendar: Fixtures.calendar)
        #expect(weeks.map(\.bounds.lowerBound) == [
            Fixtures.date(2026, 9, 14), Fixtures.date(2026, 9, 7), Fixtures.date(2026, 8, 24)
        ])
        #expect(weeks.map(\.bounds.upperBound) == [
            Fixtures.date(2026, 9, 21), Fixtures.date(2026, 9, 14), Fixtures.date(2026, 8, 31)
        ])
        #expect(weeks.map(\.lastDay) == [
            Fixtures.date(2026, 9, 20), Fixtures.date(2026, 9, 13), Fixtures.date(2026, 8, 30)
        ])
        #expect(weeks.map { $0.entries.map(\.name) } == [
            ["Workout 1", "Workout 2"], ["Workout 3", "Workout 4"], ["Workout 5"]
        ])
    }

    @Test("A Sunday start moves a Sunday workout into the week it begins")
    func group_sundayStart_beginsTheWeekOnSunday() {
        let sunday = Self.entry(1, Fixtures.date(2026, 9, 13, hour: 7))
        let monday = HistoryWeeks.group([sunday], weekStart: .monday, calendar: Fixtures.calendar)
        let sundays = HistoryWeeks.group([sunday], weekStart: .sunday, calendar: Fixtures.calendar)
        #expect(monday.map(\.bounds.lowerBound) == [Fixtures.date(2026, 9, 7)])
        #expect(sundays.map(\.bounds.lowerBound) == [Fixtures.date(2026, 9, 13)])
        #expect(sundays.map(\.lastDay) == [Fixtures.date(2026, 9, 19)])
    }

    @Test("A workout begun at 23:30 on the week's last day stays in that week, though it ends in the next")
    func group_lateOnTheLastDay_staysInItsWeek() {
        let late = Self.entry(1, Fixtures.date(2026, 9, 13, hour: 23, minute: 30))
        let next = Self.entry(2, Fixtures.date(2026, 9, 14, hour: 0, minute: 30))
        let weeks = HistoryWeeks.group([next, late], weekStart: .monday, calendar: Fixtures.calendar)
        #expect(weeks.map(\.bounds.lowerBound) == [Fixtures.date(2026, 9, 14), Fixtures.date(2026, 9, 7)])
        #expect(weeks.map { $0.entries.map(\.name) } == [["Workout 2"], ["Workout 1"]])
    }

    @Test("A week across the end of daylight saving lasts 169 hours and still ends on its seventh day")
    func group_acrossDaylightSaving_endsOnItsSeventhDay() throws {
        let newYork = try Fixtures.zone("America/New_York")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        // New York's clocks go back on Sunday 2026-11-01, the last day of the Monday week from 2026-10-26.
        let entry = Self.entry(1, Fixtures.date(2026, 10, 28, hour: 18, in: newYork))
        let week = try #require(HistoryWeeks.group([entry], weekStart: .monday, calendar: calendar).first)
        #expect(week.bounds.lowerBound == Fixtures.date(2026, 10, 26, in: newYork))
        #expect(week.bounds.upperBound == Fixtures.date(2026, 11, 2, in: newYork))
        #expect(week.bounds.upperBound.timeIntervalSince(week.bounds.lowerBound) == 169 * 3600)
        #expect(week.lastDay == Fixtures.date(2026, 11, 1, in: newYork))
    }

    @Test("No workout gives no week")
    func group_nothing_givesNoWeek() {
        #expect(HistoryWeeks.group([], weekStart: .monday, calendar: Fixtures.calendar).isEmpty)
    }

    @Test("An entry made from a workout has its fields, its totals from its sets and its length to its end")
    func entry_fromAWorkout_computesItsTotals() throws {
        var workout = try Fixtures.workout([
            Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: [
                Fixtures.set(1, pounds: 185, reps: 5),
                Fixtures.set(2, pounds: 185, reps: 4),
                Fixtures.set(3, pounds: 185, reps: 5, done: false)
            ])
        ], isDeload: true)
        let unfinished = HistoryEntry(workout, prCount: 0)
        workout.endedAt = workout.startedAt.addingTimeInterval(3482)
        let entry = HistoryEntry(workout, prCount: 2)
        #expect(entry.id == workout.id)
        #expect(entry.name == "Upper A — Push focus")
        #expect(entry.tag == "UA")
        #expect(entry.isDeload)
        #expect(entry.startedAt == workout.startedAt)
        #expect(entry.elapsed == .seconds(3482))
        #expect(entry.volume == Volume(weight: .pounds(185), reps: Reps(clamping: 9)))
        #expect(entry.doneSets == 2)
        #expect(entry.totalSets == 3)
        #expect(entry.prCount == 2)
        #expect(unfinished.elapsed == .zero, "a workout with no end has no length")
    }
}
