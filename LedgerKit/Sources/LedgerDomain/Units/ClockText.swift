import Foundation

/// Elapsed time as text: the one formatter Today's Resume button, the workout header and the receipt's TIME
/// tile share. Locale-independent, like every domain string (`NumberText`); the spoken and dated forms at its foot hold
/// no catalog key and take the caller's locale (F13 review S2-R1-4).
public enum ClockText {
    /// Whole seconds, rounded down: "m:ss" under an hour ("0:00", "24:22"), "h:mm:ss" from sixty minutes
    /// ("1:01:05"). A negative duration reads "0:00".
    ///
    /// No duration traps: the seconds are counted in 128 bits, so the 2^63 s that
    /// `WorkoutState.elapsed(at:)` saturates at prints like any other value.
    public static func elapsed(_ duration: Duration) -> String {
        let attosecondsPerSecond: Int128 = 1_000_000_000_000_000_000
        let seconds = max(0, duration.attoseconds / attosecondsPerSecond)
        let (minutes, second) = seconds.quotientAndRemainder(dividingBy: 60)
        guard minutes >= 60 else {
            return "\(minutes):\(twoDigits(second))"
        }
        let (hours, minute) = minutes.quotientAndRemainder(dividingBy: 60)
        return "\(hours):\(twoDigits(minute)):\(twoDigits(second))"
    }

    /// Time left, as a countdown writes it: whole seconds, rounded up, so "1:30" stands for the whole first
    /// second of a 90 s rest and "0:00" is read only when nothing is left. Otherwise as `elapsed(_:)`.
    public static func remaining(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return elapsed(.seconds(attoseconds > 0 && seconds < .max ? seconds + 1 : seconds))
    }

    /// "24 minutes, 22 seconds", "1 hour, 1 minute, 5 seconds": the time as VoiceOver reads it, by the whole second,
    /// rounded down as `elapsed(_:)` is, in `locale`. The format style traps on more seconds than an `Int64` holds,
    /// which a saturated time (2^63 s, `WorkoutState.elapsed(at:)`) is, so the time is held under that first.
    public static func spokenElapsed(_ elapsed: Duration, locale: Locale) -> String {
        Duration.UnitsFormatStyle(
            allowedUnits: [.hours, .minutes, .seconds],
            width: .wide,
            zeroValueUnits: .hide,
            fractionalPart: .hide(rounded: .down)
        )
        .locale(locale)
        .format(min(elapsed, .seconds(Int64.max)))
    }

    /// "Wednesday, September 16": the day `start` falls on in `calendar`'s time zone, in `locale`; empty for a start
    /// that is not a date.
    public static func startDay(of start: Date, calendar: Calendar, locale: Locale) -> String {
        guard start.timeIntervalSinceReferenceDate.isFinite else {
            return ""
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return style.weekday(.wide).month(.wide).day().format(start)
    }

    private static func twoDigits(_ value: Int128) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
