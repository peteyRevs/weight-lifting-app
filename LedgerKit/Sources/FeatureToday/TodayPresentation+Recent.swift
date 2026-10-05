import Foundation
import LedgerDomain

/// RECENT: the five finished workouts that started last, newest first.
nonisolated extension TodayPresentation {
    /// How many workouts the list shows.
    static let recentLimit = 5

    static func recent(_ context: Context) -> TodayModel.Recent {
        let workouts = withFinishedSession(context.input.recentWorkouts, context.input.session)
        let rows = workouts.prefix(recentLimit).map { recentRow($0, context) }
        return TodayModel.Recent(
            eyebrow: TodayCopy.recent,
            rows: rows,
            emptyMessage: rows.isEmpty ? TodayCopy.noSessionsYet : nil
        )
    }

    /// "Mon · 58 min · 24,180 lb": the weekday the workout started, its length in whole minutes (rounded down,
    /// as the clock text rounds seconds) and its volume in the lifter's units. One that started today reads
    /// "Today · 24:22 · 8,120 lb", its length as the clock shows it.
    static func recentRow(_ workout: WorkoutState, _ context: Context) -> TodayModel.RecentRow {
        let input = context.input
        let elapsed = workout.elapsed(at: input.now)
        let length = context.startedToday(workout)
            ? [TodayCopy.today, ClockText.elapsed(elapsed)]
            : [
                context.shortWeekday(workout.startedAt),
                TodayCopy.duration(minutes: Int(clamping: elapsed.components.seconds / 60), locale: input.locale)
            ]
        let volume = TodayCopy.volume(
            workout.volume.formatted(in: input.settings.units),
            units: input.settings.units,
            locale: input.locale
        )
        return TodayModel.RecentRow(
            name: workout.name,
            meta: (length + [volume]).joined(separator: separator),
            route: .openWorkout(workout.id)
        )
    }
}
