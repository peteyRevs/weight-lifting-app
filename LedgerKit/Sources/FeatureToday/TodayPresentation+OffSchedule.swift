import Foundation
import LedgerDomain

/// "Train off-schedule" (decision #18): the rest-day card's sheet, which offers every day of the program for
/// the card's week.
nonisolated extension TodayPresentation {
    static func offSchedule(_ program: Program, weekIndex: Int, _ context: Context) -> TodayModel.OffSchedule {
        TodayModel.OffSchedule(
            title: TodayCopy.trainOffSchedule,
            subtitle: TodayCopy.pickADay(week: weekIndex + 1, locale: context.input.locale),
            days: offScheduleDays(program, weekIndex: weekIndex, context),
            cancel: TodayCopy.cancel
        )
    }

    /// Every day of the program, in its order, as the session it would be in week `weekIndex`: its exercises
    /// that are stored, that week's estimate, and "Logged" when a finished workout of that program, week and
    /// day is among the week's, whichever day it was done. None when the program holds no such week.
    static func offScheduleDays(
        _ program: Program,
        weekIndex: Int,
        _ context: Context
    ) -> [TodayModel.OffScheduleDay] {
        let input = context.input
        guard let week = program.week(at: weekIndex) else {
            return []
        }
        return program.days.map { day in
            let session = Session(program: program, weekIndex: weekIndex, week: week, day: day)
            let planned = plannedSlots(of: session, input)
            let detail = [
                TodayCopy.exercises(planned.count, locale: input.locale),
                TodayCopy.estimate(minutes: minutes(of: session, planned), locale: input.locale)
            ]
            return TodayModel.OffScheduleDay(
                name: day.name,
                detail: detail.joined(separator: separator),
                logged: context.finished.contains { $0.source == session.source } ? TodayCopy.logged : nil,
                route: .startWorkout(program: program.id, weekIndex: weekIndex, day: day.id)
            )
        }
    }
}
