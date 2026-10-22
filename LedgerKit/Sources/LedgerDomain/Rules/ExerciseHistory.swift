import Foundation

/// One exercise's history (F12 S2; spec §3.10, rule 41; decisions #3, #4, #15, #25): its estimated 1RM, best set
/// and session count, its best estimate in each of the chart's weeks, and its sessions tagged, all folded from
/// one read, `StatsQueries.exerciseSessions(exerciseID:)`. The bests count what `PersonalRecords` counts (done
/// working and added sets); the log shows every done set. `StatsQueriesContract` pins the fold to `bestE1RM`,
/// `bestSet`, `e1RMByWeek` and `sessionCount` (N9).
public struct ExerciseHistory: Hashable, Sendable {
    /// Decision #4: how many stats weeks the chart shows, the current one last.
    public static let chartWeeks = 8

    /// The best Brzycki estimate over the sets of at most 12 reps; nil when there is none.
    public let e1RM: Weight?
    /// The heaviest set, and of two as heavy the one with more reps; nil when no set counts.
    public let bestSet: BestSet?
    /// How many workouts hold a done set of the exercise, of any kind.
    public let sessions: Int
    /// `chartWeeks` stats weeks, the oldest first and the one holding now last.
    public let weeks: [Week]
    /// One entry per session, newest first.
    public let log: [Entry]

    public struct Week: Hashable, Sendable {
        /// The week's first instant, on the lifter's first day of the week (decision #15).
        public let start: Date
        /// The best estimate of the week's sessions; nil when none has one.
        public let e1RM: Weight?
    }

    /// Rule 41's tag, as decision #3 corrects it (criterion 7).
    public enum Tag: Hashable, Sendable {
        /// The workout set a personal record of the exercise (`StatsQueries.personalRecords`).
        case record
        /// The heaviest working set is heavier than the session before's by this much.
        case heavier(Weight)
        /// Neither: no heavier, the first session (a baseline), or no working set to compare.
        case same
    }

    public struct Entry: Hashable, Sendable {
        public let workoutID: WorkoutID
        /// When the workout started.
        public let date: Date
        public let tag: Tag
        /// Every done set, warm-ups and drop sets included, in order.
        public let sets: [LoggedSet]
    }
}

public extension ExerciseHistory {
    /// The history of `sessions` (newest first), `records` being the workouts that set a record of the
    /// exercise, with the weeks of `calendar` that end with the one holding `now`.
    static func make(
        sessions: [ExerciseSession],
        records: Set<WorkoutID>,
        now: Date,
        calendar: WeekCalendar
    ) -> ExerciseHistory {
        let counted = sessions.flatMap { $0.sets.filter(PersonalRecords.countsTowardBests) }
        let best = counted.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
        return ExerciseHistory(
            e1RM: estimate(of: counted),
            bestSet: best.map { BestSet(weight: $0.weight, reps: $0.reps) },
            sessions: sessions.count,
            weeks: weeks(of: sessions, now: now, calendar: calendar),
            log: sessions.indices.map { entry(at: $0, of: sessions, records: records) }
        )
    }

    /// `make` over the stats weeks that start on `weekStart` in `calendar`'s time zone (decision #15). A stats week
    /// does not depend on when a program started, so none is asked for.
    static func make(
        sessions: [ExerciseSession],
        records: Set<WorkoutID>,
        now: Date,
        weekStart: Weekday,
        calendar: Calendar
    ) -> ExerciseHistory {
        let weeks = WeekCalendar(startDate: .unixEpoch, weekStart: weekStart, calendar: calendar)
        return make(sessions: sessions, records: records, now: now, calendar: weeks)
    }

    private static func estimate(of sets: [LoggedSet]) -> Weight? {
        sets.compactMap { OneRepMax.brzycki(weight: $0.weight, reps: $0.reps) }.max()
    }

    /// The chart's weeks, walked back from the one holding `now` as ranges of instants, so a week across a change
    /// of clocks is still one week; each with the best estimate of the sessions that started in it.
    private static func weeks(of sessions: [ExerciseSession], now: Date, calendar: WeekCalendar) -> [Week] {
        var ranges = [calendar.week(containing: now)]
        while ranges.count < chartWeeks, let first = ranges.first {
            ranges.insert(calendar.previousCompleteWeek(before: first.lowerBound), at: 0)
        }
        return ranges.map { range in
            let sets = sessions.filter { range.contains($0.startedAt) }.flatMap(\.sets)
            return Week(start: range.lowerBound, e1RM: estimate(of: sets.filter(PersonalRecords.countsTowardBests)))
        }
    }

    /// The session at `index`, tagged against the one before it in time, the next in the list.
    private static func entry(at index: Int, of sessions: [ExerciseSession], records: Set<WorkoutID>) -> Entry {
        let session = sessions[index]
        let earlier = sessions.indices.contains(index + 1) ? topWorkingWeight(of: sessions[index + 1]) : nil
        let tag: Tag =
            if records.contains(session.workoutID) {
                .record
            } else if let top = topWorkingWeight(of: session), let earlier, top > earlier {
                .heavier(top - earlier)
            } else {
                .same
            }
        return Entry(workoutID: session.workoutID, date: session.startedAt, tag: tag, sets: session.sets)
    }

    /// The heaviest working set's weight: what "+{step}" compares.
    private static func topWorkingWeight(of session: ExerciseSession) -> Weight? {
        session.sets.filter { $0.isDone && $0.kind == .working }.map(\.weight).max()
    }
}
