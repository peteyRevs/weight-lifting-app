import Foundation

/// The most recent session of an exercise, shown as the "Last" line (spec §6.3, rule 14).
public struct LastPerformance: Hashable, Codable, Sendable {
    public let date: Date
    public let sets: Int
    public let reps: Int
    public let load: Weight

    public init(date: Date, sets: Int, reps: Int, load: Weight) {
        self.date = date
        self.sets = sets
        self.reps = reps
        self.load = load
    }

    /// Spec §6.3: "Aug 12 · 5×5 @ 180 lb".
    ///
    /// `calendar` supplies the time zone that decides which day `date` falls on; month and day
    /// are Gregorian and the month is the fixed English abbreviation the spec uses, so the
    /// line is identical on every host locale.
    public func line(units: Units, calendar: Calendar) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.month, .day], from: date)
        let month = Self.monthAbbreviations[((parts.month ?? 1) - 1) % 12]
        return "\(month) \(parts.day ?? 1) · \(sets)×\(reps) @ \(load.formatted(in: units)) \(units.rawValue)"
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]
}
