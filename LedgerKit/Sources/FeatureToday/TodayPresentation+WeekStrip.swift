import Foundation
import LedgerDesign
import LedgerDomain

/// The week at a glance: the seven days of the stats week, from the settings' week start. That start may differ
/// from the weekday the block began on, so the strip can straddle two program weeks; each day is looked up by its
/// own date.
nonisolated extension TodayPresentation {
    static func weekStrip(_ context: Context) -> [WeekStrip.Day] {
        let trained = Set(context.finished.compactMap(context.startDay(of:)))
        return context.stripDays.map { day in
            let start = context.start(of: day)
            let mark = mark(of: day, trained: trained, context)
            let date = context.fullDate(start)
            // Once today is trained its mark reads "Done", so the label says which day is today.
            let isTrainedToday = mark == .done && day == context.today
            return WeekStrip.Day(
                weekday: context.weekdayLetter(start),
                date: context.dayOfMonth(start),
                mark: mark,
                accessibilitySummary: isTrainedToday ? TodayCopy.todaySummary(date, locale: context.input.locale) : date
            )
        }
    }

    /// The first that applies of: done (a finished workout started that day), today, planned (the program
    /// schedules a session that day), rest. The prototype's precedence (v1:1431).
    static func mark(of day: CivilDate, trained: Set<CivilDate>, _ context: Context) -> WeekStrip.Mark {
        if trained.contains(day) {
            return .done
        }
        if day == context.today {
            return .today
        }
        return context.isPlanned(day) ? .planned : .rest
    }
}
