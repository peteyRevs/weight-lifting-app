/// Elapsed time as text: the one formatter Today's Resume button, the workout header and the receipt's TIME
/// tile share. Locale-independent, like every domain string (`NumberText`).
public enum ClockText {
    /// Whole seconds, rounded down: "m:ss" under an hour ("0:00", "24:22"), "h:mm:ss" from sixty minutes
    /// ("1:01:05"). A negative duration reads "0:00".
    ///
    /// No duration traps: the seconds are counted in 128 bits, so the 2^63 s that
    /// `WorkoutState.elapsed(at:)` saturates at prints like any other value.
    public static func minutesSeconds(_ duration: Duration) -> String {
        let attosecondsPerSecond: Int128 = 1_000_000_000_000_000_000
        let seconds = max(0, duration.attoseconds / attosecondsPerSecond)
        let (minutes, second) = seconds.quotientAndRemainder(dividingBy: 60)
        guard minutes >= 60 else {
            return "\(minutes):\(twoDigits(second))"
        }
        let (hours, minute) = minutes.quotientAndRemainder(dividingBy: 60)
        return "\(hours):\(twoDigits(minute)):\(twoDigits(second))"
    }

    private static func twoDigits(_ value: Int128) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
