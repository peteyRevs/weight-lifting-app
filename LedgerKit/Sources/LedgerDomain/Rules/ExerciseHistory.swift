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
        /// The heaviest set that counts toward bests (decision #25: working or added) is heavier, by this much,
        /// than that of the latest earlier session that has one (N19).
        case heavier(Weight)
        /// Neither: no heavier, the first session with such a set (a baseline), or none to compare.
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
        let heaviest = heaviestAtReps(sessions)
        let best = heaviest.max { ($0.value, $0.key) < ($1.value, $1.key) }
        return ExerciseHistory(
            e1RM: estimate(of: heaviest),
            bestSet: best.map { BestSet(weight: $0.value, reps: $0.key) },
            sessions: sessions.count,
            weeks: weeks(of: sessions, now: now, calendar: calendar),
            log: log(of: sessions, records: records)
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

    /// The heaviest weight at each rep count of the sets of `sessions` that count toward bests, in one walk: the
    /// tally `PersonalRecords` keeps (F12-S2-R1-1). The best set is the heaviest of these, as `Bests.bestSet(of:)`
    /// takes it.
    private static func heaviestAtReps(_ sessions: some Sequence<ExerciseSession>) -> [Reps: Weight] {
        var tally = PersonalRecords.Tally<Weight>()
        for session in sessions {
            for set in session.sets where PersonalRecords.countsTowardBests(set) {
                tally.add(set.weight, reps: set.reps, estimate: nil)
            }
        }
        return tally.atReps
    }

    /// The best Brzycki estimate of the heaviest weights at each rep count. At fixed reps the estimate, rounded to
    /// the gram, rises with the weight, so the best of every set is the best of these: at most 12 estimates.
    private static func estimate(of heaviest: [Reps: Weight]) -> Weight? {
        heaviest.compactMap { OneRepMax.brzycki(weight: $0.value, reps: $0.key) }.max()
    }

    /// The chart's weeks, walked back from the one holding `now` as ranges of instants, so a week across a change
    /// of clocks is still one week; each with the best estimate of the sessions that started in it.
    private static func weeks(of sessions: [ExerciseSession], now: Date, calendar: WeekCalendar) -> [Week] {
        var ranges = [calendar.week(containing: now)]
        while ranges.count < chartWeeks, let first = ranges.first {
            ranges.insert(calendar.previousCompleteWeek(before: first.lowerBound), at: 0)
        }
        return ranges.map { range in
            let heaviest = heaviestAtReps(sessions.lazy.filter { range.contains($0.startedAt) })
            return Week(start: range.lowerBound, e1RM: estimate(of: heaviest))
        }
    }

    /// One entry per session, newest first, each tagged against the latest earlier session that has a set counting
    /// toward bests (N19, as amended for S3): a session of warm-ups or drop sets alone is passed over, so it never
    /// hides a step up, and is itself "—". One walk from the oldest session, carrying the last top weight seen.
    private static func log(of sessions: [ExerciseSession], records: Set<WorkoutID>) -> [Entry] {
        var earlier: Weight?
        var log: [Entry] = []
        log.reserveCapacity(sessions.count)
        for session in sessions.reversed() {
            let top = topCountedWeight(of: session)
            let tag: Tag =
                if records.contains(session.workoutID) {
                    .record
                } else if let top, let earlier, top > earlier {
                    .heavier(top - earlier)
                } else {
                    .same
                }
            log.append(Entry(workoutID: session.workoutID, date: session.startedAt, tag: tag, sets: session.sets))
            earlier = top ?? earlier
        }
        return log.reversed()
    }

    /// The heaviest weight of the sets that count toward bests (`PersonalRecords.countsTowardBests`): what
    /// "+{step}" compares.
    private static func topCountedWeight(of session: ExerciseSession) -> Weight? {
        session.sets.filter(PersonalRecords.countsTowardBests).map(\.weight).max()
    }
}
