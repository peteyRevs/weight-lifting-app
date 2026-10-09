import Foundation
import LedgerDomain

/// The part of Today that no store observes: the finished workouts of the week and the volume of the week
/// before. `TodayStore` reads it again whenever the program, the settings or the finished workouts change.
nonisolated struct TodayHistory: Sendable {
    /// How many of the workouts finished last Today lists (`TodayInput.recentWorkouts`).
    static let recentLimit = 5

    /// The finished workouts that started in `Ranges.week`: `TodayInput.weekWorkouts`.
    var weekWorkouts: [WorkoutState] = []
    /// `TodayInput.previousWeekVolume`.
    var previousWeekVolume: Volume?

    /// The two stretches of time the reads cover.
    struct Ranges: Equatable, Sendable {
        /// The stats week of the moment and its program week as one stretch: from the earlier start to the
        /// later end. They are the same seven days unless the block began on another weekday than the week
        /// starts on; then they overlap, and one read over both hands each workout in once (S3 criterion 19).
        var week: Range<Date>
        /// The complete stats week before the one of the moment.
        var previousWeek: Range<Date>
    }

    /// What to read for `now`; nil when the moment has no calendar date (outside the years 1 to 9999), which
    /// leaves the week empty and the change of volume unknown.
    ///
    /// The program week joins the stats week only while the block runs. Before its first day that is week 1,
    /// as the presentation speaks of it; with no program, or after the block, the stats week stands alone. A
    /// stretch wider than the two weeks does no harm: the presentation counts by date and by source.
    static func ranges(program: Program?, settings: Settings, now: Date, calendar: Calendar) -> Ranges? {
        guard let start = program?.startDate ?? CivilDate(now, in: calendar) else {
            return nil
        }
        let weeks = WeekCalendar(startDate: start, weekStart: settings.weekStart, calendar: calendar)
        var week = weeks.week(containing: now)
        if let program, !weeks.isBlockComplete(program, on: now) {
            let programWeek = weeks.bounds(ofWeek: max(0, weeks.weekIndex(for: now)))
            week = min(week.lowerBound, programWeek.lowerBound) ..< max(week.upperBound, programWeek.upperBound)
        }
        return Ranges(week: week, previousWeek: weeks.previousCompleteWeek(before: now))
    }

    /// Reads `ranges`: one read of the workouts, one of the volume.
    static func read(
        _ ranges: Ranges?,
        workouts: any WorkoutRepository,
        stats: any StatsQueries
    ) async throws -> TodayHistory {
        guard let ranges else {
            return TodayHistory()
        }
        return try await TodayHistory(
            weekWorkouts: workouts.workouts(in: ranges.week),
            previousWeekVolume: stats.weeklyVolume(in: ranges.previousWeek)
        )
    }
}
