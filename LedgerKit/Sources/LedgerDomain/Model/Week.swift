import Foundation

/// ISO weekday numbering: Monday = 1 … Sunday = 7 (spec §6.1 `sched[7]` runs Mon…Sun).
///
/// Foundation's `Calendar` numbers weekdays Sunday = 1 … Saturday = 7; use
/// `init(calendarWeekday:)` / `calendarWeekday` to cross between the two.
public enum Weekday: Int, Codable, Sendable, CaseIterable, Comparable, CodingKeyRepresentable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    /// Maps a Foundation weekday (1 = Sunday … 7 = Saturday); `nil` outside 1…7.
    public init?(calendarWeekday: Int) {
        guard (1 ... 7).contains(calendarWeekday) else {
            return nil
        }
        self.init(rawValue: (calendarWeekday + 5) % 7 + 1)
    }

    /// The Foundation weekday number (1 = Sunday … 7 = Saturday).
    public var calendarWeekday: Int {
        rawValue % 7 + 1
    }

    /// Decision #15: the default week start is the locale's first weekday (en_US → Sunday,
    /// de_DE → Monday). Settings may override it (`Settings.weekStart`).
    public static func first(of calendar: Calendar) -> Weekday {
        Weekday(calendarWeekday: calendar.firstWeekday) ?? .monday
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One week of a block (spec §6.1 "Week"): which day template runs on which weekday, and
/// whether it is a deload week. A weekday missing from `schedule` is a rest day.
public struct Week: Identifiable, Hashable, Codable, Sendable {
    public let id: WeekID
    public var index: Int
    public var isDeload: Bool
    public var schedule: [Weekday: DayTemplateID]

    public init(id: WeekID, index: Int, isDeload: Bool = false, schedule: [Weekday: DayTemplateID] = [:]) {
        self.id = id
        self.index = index
        self.isDeload = isDeload
        self.schedule = schedule
    }
}
