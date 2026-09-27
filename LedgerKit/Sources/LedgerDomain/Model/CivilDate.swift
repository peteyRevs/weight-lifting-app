import Foundation

/// A calendar day with no time and no time zone, in the proleptic Gregorian calendar
/// (ADR-007). A program block starts on a `CivilDate` (decision #18), so its weeks follow the
/// lifter's wall calendar wherever they are, and every week boundary is the start of a real day.
///
/// Day arithmetic is pure integer maths (days since 1970-01-01), never instant arithmetic, so a
/// day that starts at 01:00 (DST at midnight) or a trip across time zones cannot shift it.
/// Every value lies in 0001-01-01 … 9999-12-31: the producers that could leave that range
/// (`adding(days:)`, `init(_:in:)`) return `nil` instead, so every value encodes as
/// `"YYYY-MM-DD"` and decodes back (decoding validates the date).
public struct CivilDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// A valid Gregorian date in years 1…9999; `nil` otherwise (Feb 30, month 13, year 0).
    public init?(year: Int, month: Int, day: Int) {
        guard (1 ... 9999).contains(year), (1 ... 12).contains(month),
              (1 ... Self.daysIn(month: month, year: year)).contains(day)
        else {
            return nil
        }
        self.init(validYear: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar`'s time zone (Gregorian; only the zone is used), or
    /// `nil` when that day is outside 0001…9999. Foundation's Gregorian calendar is Julian before
    /// 1582-10-15, so older instants map to Julian days; every date a lifter logs is far after that.
    public init?(_ date: Date, in calendar: Calendar) {
        self.init(daysSinceEpoch: Self.dayNumber(of: date, in: calendar))
    }

    /// The date `daysSinceEpoch` days after 1970-01-01, or `nil` outside 0001…9999.
    init?(daysSinceEpoch days: Int) {
        guard Self.validDayNumbers.contains(days) else {
            return nil
        }
        let civil = Self.civil(fromDayNumber: days)
        self.init(validYear: civil.year, month: civil.month, day: civil.day)
    }

    private init(validYear: Int, month: Int, day: Int) {
        year = validYear
        self.month = month
        self.day = day
    }

    /// 1970-01-01, the origin of `daysSinceEpoch`.
    static let unixEpoch = CivilDate(validYear: 1970, month: 1, day: 1)

    /// Days since 1970-01-01 (negative before it). Internal: callers use `days(since:)`.
    var daysSinceEpoch: Int {
        Self.dayNumber(year: year, month: month, day: day)
    }

    /// The date `count` days later (earlier when negative), or `nil` when that leaves
    /// 0001-01-01 … 9999-12-31 (including `Int` overflow).
    public func adding(days count: Int) -> CivilDate? {
        let (target, overflow) = daysSinceEpoch.addingReportingOverflow(count)
        return overflow ? nil : CivilDate(daysSinceEpoch: target)
    }

    /// Whole days from `other` to `self`.
    public func days(since other: CivilDate) -> Int {
        daysSinceEpoch - other.daysSinceEpoch
    }

    /// The ISO weekday (1970-01-01 was a Thursday).
    public var weekday: Weekday {
        Self.weekday(ofDayNumber: daysSinceEpoch)
    }

    /// The first instant of this day in `calendar`'s time zone: midnight, or 01:00 on a day whose
    /// midnight is skipped by DST (Africa/Cairo, America/Santiago, America/Havana …).
    public func startOfDay(in calendar: Calendar) -> Date {
        Self.startOfDay(dayNumber: daysSinceEpoch, in: calendar)
    }

    // MARK: - Day numbers (internal; unbounded, for WeekCalendar)

    /// Day numbers of 0001-01-01 … 9999-12-31.
    static let validDayNumbers = dayNumber(year: 1, month: 1, day: 1) ... dayNumber(year: 9999, month: 12, day: 31)

    /// The day number of the civil day `date` falls on in `calendar`'s time zone (any year).
    static func dayNumber(of date: Date, in calendar: Calendar) -> Int {
        let parts = gregorian(in: calendar).dateComponents([.era, .year, .month, .day], from: date)
        // Foundation always fills these components; the fallbacks are unreachable. Era 0 (BC)
        // year n is astronomical year 1 − n, so 1 BC is year 0 and falls outside 0001…9999.
        let astronomicalYear = parts.era == 0 ? 1 - (parts.year ?? 1) : parts.year ?? 1970
        return dayNumber(year: astronomicalYear, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The day numbers `startOfDay(dayNumber:in:)` resolves: 0001-01-01 through a week past
    /// 9999-12-31, so the last valid week still has an end.
    static let resolvableDayNumbers = validDayNumbers.lowerBound ... validDayNumbers.upperBound + 7

    /// The first instant of day `dayNumber` in `calendar`'s time zone. Day numbers outside
    /// `resolvableDayNumbers` are clamped to its ends: monotonic, never trapping, and far outside any
    /// training date.
    static func startOfDay(dayNumber unclamped: Int, in calendar: Calendar) -> Date {
        let dayNumber = min(max(unclamped, resolvableDayNumbers.lowerBound), resolvableDayNumbers.upperBound)
        let zoned = gregorian(in: calendar)
        let civil = civil(fromDayNumber: dayNumber)
        let noon = DateComponents(year: civil.year, month: civil.month, day: civil.day, hour: 12)
        // Noon exists on every civil day; the fallback (UTC noon) is unreachable in practice.
        let instant = zoned.date(from: noon) ?? Date(timeIntervalSince1970: Double(dayNumber) * 86400 + 43200)
        return zoned.startOfDay(for: instant)
    }

    /// The ISO weekday of day `dayNumber`.
    static func weekday(ofDayNumber dayNumber: Int) -> Weekday {
        let isoIndex = (dayNumber % 7 + 7 + 3) % 7
        return Weekday(rawValue: isoIndex + 1) ?? .monday
    }

    private static func gregorian(in calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    /// "2026-08-17".
    public var description: String {
        func padded(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))"
    }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: - Codable ("YYYY-MM-DD")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = Self(iso8601: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a YYYY-MM-DD date, got \"\(text)\""
            )
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// Parses exactly "YYYY-MM-DD" (four, two and two ASCII digits) into a valid date.
    public init?(iso8601 text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        let widths = parts.map(\.count)
        guard widths == [4, 2, 2], parts.allSatisfy({ $0.allSatisfy { ("0" ... "9").contains($0) } }),
              let parsedYear = Int(parts[0]), let parsedMonth = Int(parts[1]), let parsedDay = Int(parts[2])
        else {
            return nil
        }
        self.init(year: parsedYear, month: parsedMonth, day: parsedDay)
    }

    // MARK: - Gregorian arithmetic

    private struct Parts {
        let year: Int
        let month: Int
        let day: Int
    }

    /// Howard Hinnant's civil_from_days.
    private static func civil(fromDayNumber days: Int) -> Parts {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let calendarMonth = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        return Parts(
            year: yearOfEra + era * 400 + (calendarMonth <= 2 ? 1 : 0),
            month: calendarMonth,
            day: dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        )
    }

    private static func isLeap(_ year: Int) -> Bool {
        year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Howard Hinnant's days_from_civil (any year).
    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
