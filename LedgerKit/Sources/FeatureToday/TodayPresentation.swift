import Foundation
import LedgerDomain

/// Today's logic and its words: one pure function from a `TodayInput` to the `TodayModel` the views draw.
///
/// It reads its input and nothing else. Every day is a calendar date in the input calendar's time zone, found
/// with `LedgerDomain`'s calendar functions (`WeekCalendar`, `CivilDate`), never by adding seconds, so a 23- or
/// 25-hour day is one day like any other. Weights and volumes are printed as `LedgerDomain` formats them and
/// never pass through `Double`. Every text comes from `TodayCopy`.
///
/// Which card is shown is decided in `+Card`, one small function per rule; the week strip, the tiles, the recent
/// list and the off-schedule list are in the other extension files.
nonisolated enum TodayPresentation {
    /// What joins the fragments of a line: "Week 1 of 8 · ~38 min" (M1 convention).
    static let separator = " · "

    static func make(_ input: TodayInput) -> TodayModel {
        let context = Context(input)
        let day = day(context)
        return TodayModel(
            header: header(day, context),
            weekStrip: weekStrip(context),
            card: card(day, context),
            stats: stats(context),
            recent: recent(context)
        )
    }

    static func header(_ day: Day, _ context: Context) -> TodayModel.Header {
        let title = switch day {
        case .noProgram, .blockComplete: TodayCopy.today
        case let .session(_, session): session.day.shortTitle
        case .rest: TodayCopy.restDay
        }
        return TodayModel.Header(
            date: context.fullDate(context.input.now),
            title: title,
            settings: TodayModel.Action(title: TodayCopy.settings, route: .settings)
        )
    }
}

// MARK: - What the program says about today

nonisolated extension TodayPresentation {
    /// The active program on the calendar.
    struct Block {
        let program: Program
        /// The program's weeks, counted from its start date in the input calendar's time zone.
        let weeks: WeekCalendar
        /// The program week of the input's moment, 0 for the block's first; negative before the block begins.
        let weekIndex: Int
    }

    /// One session of a program: a day template in a program week.
    struct Session {
        let program: Program
        let weekIndex: Int
        let week: Week
        let day: DayTemplate

        /// What a workout built for this session carries.
        var source: WorkoutSource {
            WorkoutSource(programID: program.id, weekIndex: weekIndex, dayTemplateID: day.id)
        }
    }

    /// What the program says about today. With the two rules of `+Card` it decides the card, and alone it
    /// decides the header's title.
    enum Day {
        case noProgram
        /// The moment is past the block's last week.
        case blockComplete(Block)
        /// The program schedules a session today.
        case session(Block, Session)
        /// Nothing is scheduled today: a rest day, or a day before the block begins.
        case rest(Block)
    }

    static func day(_ context: Context) -> Day {
        guard let block = context.block else {
            return .noProgram
        }
        guard !block.weeks.isBlockComplete(block.program, on: context.input.now) else {
            return .blockComplete(block)
        }
        let scheduled = block.weeks.scheduledDay(on: context.input.now, in: block.program)
        guard let session = session(of: block.program, weekIndex: block.weekIndex, day: scheduled) else {
            return .rest(block)
        }
        return .session(block, session)
    }

    /// The session `program` holds for day `day` in week `weekIndex`; nil when it has no such week or no such
    /// day, and for a nil `day`.
    static func session(of program: Program, weekIndex: Int, day: DayTemplateID?) -> Session? {
        guard let week = program.week(at: weekIndex), let template = program.days.first(where: { $0.id == day }) else {
            return nil
        }
        return Session(program: program, weekIndex: weekIndex, week: week, day: template)
    }
}

// MARK: - The input, resolved once

nonisolated extension TodayPresentation {
    /// The input, with what several parts of the model need from it: today's calendar date, the strip's days,
    /// the active program on the calendar and the finished workouts. Built once per `make`, so the strip, the
    /// tiles and the card read the same facts and cannot disagree.
    struct Context {
        let input: TodayInput
        /// The calendar day of the input's moment; nil outside the years 1 to 9999, which no `CivilDate` holds.
        let today: CivilDate?
        /// The days of the stats week of the moment, from the settings' week start: seven, but for the days
        /// that have no calendar date at the two ends of the years 1 to 9999.
        let stripDays: [CivilDate]
        let block: Block?
        /// The week's finished workouts, with the session's own workout the moment it is finished.
        let finished: [WorkoutState]

        init(_ input: TodayInput) {
            self.input = input
            today = CivilDate(input.now, in: input.calendar)
            // Without a program the weeks are counted from today: only the stats week is read from them.
            let weeks = (input.program?.startDate ?? today).map {
                WeekCalendar(startDate: $0, weekStart: input.settings.weekStart, calendar: input.calendar)
            }
            stripDays = weeks?.firstDayOfWeek(containing: input.now)
                .map { first in (0 ..< 7).compactMap { first.adding(days: $0) } } ?? []
            block = input.program.flatMap { program in
                weeks.map { Block(program: program, weeks: $0, weekIndex: $0.weekIndex(for: input.now)) }
            }
            finished = TodayPresentation.withFinishedSession(input.weekWorkouts, input.session)
        }

        /// The calendar day `workout` started on, which is the day it belongs to (product decision #26).
        func startDay(of workout: WorkoutState) -> CivilDate? {
            CivilDate(workout.startedAt, in: input.calendar)
        }

        func startedToday(_ workout: WorkoutState) -> Bool {
            today.map { $0 == startDay(of: workout) } ?? false
        }

        /// Whether the program schedules a session on `day`, judged by that day's own program week, so a strip
        /// that straddles two program weeks reads each half from its own. Never before or after the block.
        func isPlanned(_ day: CivilDate) -> Bool {
            block.map { $0.weeks.scheduledDay(on: start(of: day), in: $0.program) != nil } ?? false
        }

        /// The first moment of `day` in the input calendar's time zone: what a date style prints the day from.
        func start(of day: CivilDate) -> Date {
            day.startOfDay(in: input.calendar)
        }
    }

    /// `stored` (newest first) without anything that is not finished, and with the session's own workout the
    /// moment it is finished, placed by its start. History reports that workout too, an update earlier or
    /// later; it is counted once, by its id.
    static func withFinishedSession(_ stored: [WorkoutState], _ session: WorkoutState?) -> [WorkoutState] {
        var workouts = stored.filter { $0.phase == .finished }
        if let session, session.phase == .finished, !workouts.contains(where: { $0.id == session.id }) {
            let place = workouts.firstIndex { $0.startedAt <= session.startedAt } ?? workouts.endIndex
            workouts.insert(session, at: place)
        }
        return workouts
    }
}

// MARK: - Dates and numbers as text

nonisolated extension TodayPresentation.Context {
    /// A date style in the injected locale, calendar and time zone, with no field chosen yet.
    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: input.locale,
            calendar: input.calendar,
            timeZone: input.calendar.timeZone
        )
    }

    /// "Wednesday, September 16".
    func fullDate(_ date: Date) -> String {
        date.formatted(dateStyle.weekday(.wide).month(.wide).day())
    }

    /// "Wednesday".
    func weekdayName(_ date: Date) -> String {
        date.formatted(dateStyle.weekday(.wide))
    }

    /// "Wed".
    func shortWeekday(_ date: Date) -> String {
        date.formatted(dateStyle.weekday(.abbreviated))
    }

    /// "W".
    func weekdayLetter(_ date: Date) -> String {
        date.formatted(dateStyle.weekday(.narrow))
    }

    /// "16".
    func dayOfMonth(_ date: Date) -> String {
        date.formatted(dateStyle.day())
    }

    /// A count that stands in a text as its second number: a counted key takes one number, and any other is
    /// formatted first and passed as text (standards §7).
    func number(_ value: Int) -> String {
        value.formatted(.number.locale(input.locale))
    }
}
