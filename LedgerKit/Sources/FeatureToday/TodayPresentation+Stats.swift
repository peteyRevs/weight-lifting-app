import Foundation
import LedgerDomain

/// The two tiles (decision #15): sessions done over sessions planned, and the volume moved, both for the strip's
/// seven days.
nonisolated extension TodayPresentation {
    static func stats(_ context: Context) -> TodayModel.Stats {
        let days = Set(context.stripDays)
        // A workout belongs to the day it started (decision #26); off-schedule ones count, so "5/4" can happen.
        let sessions = context.finished.filter { context.startDay(of: $0).map(days.contains) ?? false }
        let planned = context.stripDays.count(where: context.isPlanned)
        let volume = sessions.reduce(Volume.zero) { $0 + $1.volume }
        return TodayModel.Stats(
            sessions: sessionsTile(done: sessions.count, planned: planned, context),
            volume: volumeTile(volume, context)
        )
    }

    /// "2" "/4" "sessions this week".
    static func sessionsTile(done: Int, planned: Int, _ context: Context) -> TodayModel.Tile {
        let locale = context.input.locale
        return TodayModel.Tile(
            value: context.number(done),
            unit: TodayCopy.sessionsPlanned(planned, locale: locale),
            caption: TodayCopy.sessionsThisWeek,
            delta: nil,
            accessibilitySummary: TodayCopy.sessionsSummary(
                done: context.number(done),
                planned: planned,
                locale: locale
            )
        )
    }

    /// "24.2" "k" "lb moved", and "+8%" against the previous week. VoiceOver reads the whole number and says
    /// what the change is against: "24,180 lb moved this week, +8% from last week".
    static func volumeTile(_ volume: Volume, _ context: Context) -> TodayModel.Tile {
        let input = context.input
        let units = input.settings.units
        let delta = input.previousWeekVolume
            .flatMap { volume.percentChange(from: $0) }
            .map { change($0, input.locale) }
        let whole = volume.formatted(in: units)
        return TodayModel.Tile(
            value: volume.thousands(in: units),
            unit: TodayCopy.thousands,
            caption: TodayCopy.movedCaption(units),
            delta: delta,
            accessibilitySummary: delta
                .map { TodayCopy.movedThisWeek(whole, change: $0, units: units, locale: input.locale) }
                ?? TodayCopy.movedThisWeek(whole, units: units, locale: input.locale)
        )
    }

    /// "+8%", "−3%", and "0%" for a change within half a percent. The size is clamped, so the largest fall
    /// `percentChange` can give does not overflow when its sign is dropped.
    static func change(_ percent: Int, _ locale: Locale) -> String {
        let size = Int(clamping: percent.magnitude)
        if percent > 0 {
            return TodayCopy.increase(size, locale: locale)
        }
        return percent < 0 ? TodayCopy.decrease(size, locale: locale) : TodayCopy.unchanged(size, locale: locale)
    }
}
