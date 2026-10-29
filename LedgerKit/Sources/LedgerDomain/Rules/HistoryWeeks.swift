import Foundation

/// The History list's weeks (F13 S1, N3; decision #15): workouts grouped under the stats week they started in,
/// weeks starting on the lifter's first day of the week. A workout belongs to the week of its start (product
/// decision #26), so one begun at 23:30 on a week's last day and finished after midnight stays in that week.
public enum HistoryWeeks {
    public struct Week: Hashable, Sendable {
        /// From the start of the week's first day to the start of the next week's (`WeekCalendar.week(containing:)`).
        public let bounds: Range<Date>
        /// The start of the week's seventh day: where a header that names the days ends ("Sep 7 – 13"). Found by
        /// counting days, so a week across a change of clocks still ends on its seventh day.
        public let lastDay: Date
        /// Never empty, in the order given.
        public fileprivate(set) var entries: [HistoryEntry]
    }

    /// `entries`, newest first as `WorkoutRepository.historyEntries()` lists them, as weeks newest first. Each
    /// workout is in the stats week that holds its start, in `calendar`'s time zone; a week with no workout is not
    /// listed. Entries in another order give a week once for each run of it.
    public static func group(_ entries: [HistoryEntry], weekStart: Weekday, calendar: Calendar) -> [Week] {
        // A stats week does not depend on when a program started, so none is asked for (as `ExerciseHistory`).
        let weeks = WeekCalendar(startDate: .unixEpoch, weekStart: weekStart, calendar: calendar)
        var grouped: [Week] = []
        for entry in entries {
            let bounds = weeks.week(containing: entry.startedAt)
            if grouped.last?.bounds == bounds {
                grouped[grouped.count - 1].entries.append(entry)
            } else {
                let firstDay = CivilDate.dayNumber(of: bounds.lowerBound, in: calendar)
                let lastDay = CivilDate.startOfDay(dayNumber: firstDay + 6, in: calendar)
                grouped.append(Week(bounds: bounds, lastDay: lastDay, entries: [entry]))
            }
        }
        return grouped
    }
}
