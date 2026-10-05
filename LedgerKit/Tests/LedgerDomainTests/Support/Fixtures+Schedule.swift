import Foundation
@testable import LedgerDomain
import Testing

// MARK: - Schedules (spec §6.4), for `WeekCalendar.nextScheduledDay(after:in:)` (F09 S2)

extension Fixtures {
    static let upperADay = DayTemplateID(uuid(501))
    static let lowerADay = DayTemplateID(uuid(502))
    static let upperBDay = DayTemplateID(uuid(503))
    static let lowerBDay = DayTemplateID(uuid(504))

    /// Spec §6.4's four training days. They carry no slots: a schedule only names a day.
    static let scheduleDays = [
        DayTemplate(id: upperADay, name: "Upper A — Push focus", tag: "UA"),
        DayTemplate(id: lowerADay, name: "Lower A — Squat focus", tag: "LA"),
        DayTemplate(id: upperBDay, name: "Upper B — Pull focus", tag: "UB"),
        DayTemplate(id: lowerBDay, name: "Lower B — Hinge focus", tag: "LB")
    ]

    /// Spec §6.4's seed schedule as an 8-week block: weeks 1–7 run Upper A on Monday, Lower A on
    /// Wednesday, Upper B on Friday and Lower B on Saturday; week 8 is a deload without the Saturday.
    static func fourDayProgram(startDate: CivilDate = civil(2026, 9, 14)) throws -> Program {
        let full: [Weekday: DayTemplateID] = [
            .monday: upperADay, .wednesday: lowerADay, .friday: upperBDay, .saturday: lowerBDay
        ]
        let deload = full.filter { $0.key != .saturday }
        let weeks = (0 ..< 8).map { week($0, deload: $0 == 7, schedule: $0 == 7 ? deload : full) }
        return try Program(
            id: programID,
            name: "Upper / Lower",
            startDate: startDate,
            weeks: weeks,
            days: scheduleDays
        )
    }

    /// A block that trains every day, each weekday of each week on a template of its own. The day after
    /// any day in it is a scheduled one, and its template tells which week and which weekday were read.
    static func everyDayProgram(startDate: CivilDate, weekCount: Int) throws -> Program {
        var weeks: [Week] = []
        var days: [DayTemplate] = []
        for index in 0 ..< weekCount {
            var schedule: [Weekday: DayTemplateID] = [:]
            for weekday in Weekday.allCases {
                let template = everyDayTemplate(week: index, on: weekday)
                schedule[weekday] = template
                days.append(DayTemplate(id: template, name: "Week \(index + 1), \(weekday)", tag: "D\(days.count + 1)"))
            }
            weeks.append(week(index, schedule: schedule))
        }
        return try Program(id: programID, name: "Every day", startDate: startDate, weeks: weeks, days: days)
    }

    /// The template `everyDayProgram` trains on `weekday` of the week with `index`.
    static func everyDayTemplate(week index: Int, on weekday: Weekday) -> DayTemplateID {
        DayTemplateID(uuid(40000 + 7 * index + weekday.rawValue))
    }
}
