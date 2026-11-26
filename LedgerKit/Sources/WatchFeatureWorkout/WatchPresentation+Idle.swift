import Foundation
import LedgerDomain

/// Everything the screen before a workout reads. The store fills it; the presentation reaches for nothing else.
nonisolated struct WatchIdleInput: Sendable {
    /// The program the watch holds (F19 sends it), or nil when it has none.
    var program: Program?
    /// The stored exercises by id: a slot holds only its exercise's id.
    var exercises: [ExerciseID: Exercise] = [:]
    /// The session's last workout. A finished one of today's session, started today, makes the day "Logged" with
    /// its sets and volume.
    var workout: WorkoutState?
    /// Whether the watch's history holds a finished workout of today's session that started today: "Logged earlier
    /// today", for a workout this session did not see end.
    var isTodayLogged = false
    var settings: Settings
    var now: Date
    /// Its time zone decides which calendar day `now` falls on; weekdays are written with it.
    var calendar: Calendar
    var locale: Locale
    /// The app's display name (`CFBundleDisplayName`), for "Open %@ on iPhone".
    var appName: String
}

/// What the screen before a workout draws (spec §4.3 "Watch — before workout", §9's "no program" state).
nonisolated enum WatchIdleModel: Equatable, Sendable {
    /// "No program on watch", and the outlined "Open Ledger on iPhone".
    case noProgram(title: String, open: String)
    case plan(Plan)

    struct Plan: Equatable, Sendable {
        /// "WEEK 1 OF 8", "WEEK 8 OF 8 · DELOAD"; nil outside the block's weeks.
        let weekLabel: String?
        /// Today's day name, or "Rest day".
        let dayName: String
        let planLine: String
        /// "Start" while a session is scheduled today and not yet logged; nil otherwise.
        let start: String?
        /// "Next: Friday · UB" or "Next: week 2" when there is no "Start"; nil with no session left in the block.
        let next: String?
    }
}

nonisolated extension WatchPresentation {
    /// Today's plan, by the phone's calendar rules (`WeekCalendar`, decision #18): the program week of `now` from the
    /// program's start date and the settings' week start, the day that week schedules on `now`'s weekday, and the
    /// next scheduled day after it. A day past the block's last week, or before its first, is a rest day.
    static func idle(_ input: WatchIdleInput) -> WatchIdleModel {
        guard let program = input.program else {
            return .noProgram(
                title: WatchWorkoutCopy.noProgram,
                open: WatchWorkoutCopy.openOnIPhone(input.appName, locale: input.locale)
            )
        }
        let weeks = WeekCalendar(
            startDate: program.startDate,
            weekStart: input.settings.weekStart,
            calendar: input.calendar
        )
        let weekIndex = weeks.weekIndex(for: input.now)
        let week = program.week(at: weekIndex)
        let day = weeks.scheduledDay(on: input.now, in: program).flatMap { id in program.days.first { $0.id == id } }
        let logged = day.flatMap { day in
            loggedLine(input, source: WorkoutSource(programID: program.id, weekIndex: weekIndex, dayTemplateID: day.id))
        }
        let planLine = switch (day, week) {
        case let (day?, week?): logged ?? sessionLine(day, week: week, weekIndex: weekIndex, input)
        default: WatchWorkoutCopy.nothingScheduled
        }
        let hasPlan = day != nil && logged == nil
        return .plan(WatchIdleModel.Plan(
            weekLabel: week.map { week in
                week.isDeload
                    ? WatchWorkoutCopy.deloadWeek(weekIndex + 1, of: program.weeks.count, locale: input.locale)
                    : WatchWorkoutCopy.week(weekIndex + 1, of: program.weeks.count, locale: input.locale)
            },
            dayName: day?.name ?? WatchWorkoutCopy.restDay,
            planLine: planLine,
            start: hasPlan ? WatchWorkoutCopy.start : nil,
            next: hasPlan ? nil : nextSessionLine(program, weeks: weeks, weekIndex: weekIndex, input)
        ))
    }

    /// "Logged · 18 sets · 24,180 lb" for the session's finished workout of `source` that started today (the
    /// phone's Logged card's rule, FeatureToday), "Logged earlier today" when only the history knows of one, else nil.
    static func loggedLine(_ input: WatchIdleInput, source: WorkoutSource) -> String? {
        let startedToday = { (workout: WorkoutState) in
            CivilDate(workout.startedAt, in: input.calendar) == CivilDate(input.now, in: input.calendar)
        }
        if let workout = input.workout, workout.phase == .finished, workout.source == source, startedToday(workout) {
            let units = input.settings.units
            return [
                WatchWorkoutCopy.logged,
                WatchWorkoutCopy.sets(workout.doneSets, locale: input.locale),
                WatchWorkoutCopy.weight(workout.volume.formatted(in: units), units: units, locale: input.locale)
            ].joined(separator: separator)
        }
        return input.isTodayLogged ? WatchWorkoutCopy.loggedEarlierToday : nil
    }

    /// "5 exercises · 21 sets · Bench Press first", or "… · empty day": the slots whose exercise is stored, as the
    /// phone's card lists them, and the day's sets as that week prescribes them, drop sets included, as the phone's
    /// estimate counts them (`TimeEstimate.setCount`).
    static func sessionLine(_ day: DayTemplate, week: Week, weekIndex: Int, _ input: WatchIdleInput) -> String {
        let planned = day.slots.compactMap { slot in input.exercises[slot.exerciseID].map { (slot, $0) } }
        let prescriptions = Dictionary(planned.map { slot, exercise in
            (slot.id, ProgressionRules.prescribe(
                week: week, weekIndex: weekIndex, slot: slot, exercise: exercise, units: input.settings.units
            ))
        }) { first, _ in first }
        return [
            WatchWorkoutCopy.exercises(planned.count, locale: input.locale),
            WatchWorkoutCopy.sets(TimeEstimate.setCount(day: day, prescriptions: prescriptions), locale: input.locale),
            planned.first.map { WatchWorkoutCopy.first($0.1.name, locale: input.locale) } ?? WatchWorkoutCopy.emptyDay
        ].joined(separator: separator)
    }

    /// "Next: Friday · UB" while the next session is in the program week of `now`, "Next: week 2" when it is in a
    /// later one, nil when none is left: the phone's "Next:" line (FeatureToday), which never names the week the
    /// lifter is in.
    static func nextSessionLine(
        _ program: Program,
        weeks: WeekCalendar,
        weekIndex: Int,
        _ input: WatchIdleInput
    ) -> String? {
        guard let next = weeks.nextScheduledDay(after: input.now, in: program) else {
            return nil
        }
        guard next.weekIndex == weekIndex else {
            return WatchWorkoutCopy.nextWeek(next.weekIndex + 1, locale: input.locale)
        }
        guard let day = program.days.first(where: { $0.id == next.dayTemplateID }) else {
            return nil
        }
        let style = Date.FormatStyle(
            date: .omitted, time: .omitted, locale: input.locale, calendar: input.calendar,
            timeZone: input.calendar.timeZone
        )
        let weekday = next.date.startOfDay(in: input.calendar).formatted(style.weekday(.wide))
        return WatchWorkoutCopy.next(weekday, tag: day.tag, locale: input.locale)
    }
}
