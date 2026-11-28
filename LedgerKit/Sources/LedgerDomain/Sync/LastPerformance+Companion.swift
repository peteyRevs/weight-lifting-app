import Foundation

public extension LastPerformance {
    /// The "Last" line a device shows for an exercise (F19 Q12, criterion 4): the newer by date of `own`, from this
    /// device's history (`StatsQueries.lastPerformance(exerciseID:)`), and `cached`, the phone's line the watch keeps
    /// (`CompanionStore.lastPerformance()`); whichever is present when only one is. Of two with the same date,
    /// `cached`: the phone is the history authority (Q4), so its line of a shared workout holds the sets of both
    /// devices. On the phone the cache is empty, so the line is its own.
    static func newer(own: LastPerformance?, cached: LastPerformance?) -> LastPerformance? {
        guard let own, let cached else {
            return cached ?? own
        }
        return own.date > cached.date ? own : cached
    }
}
