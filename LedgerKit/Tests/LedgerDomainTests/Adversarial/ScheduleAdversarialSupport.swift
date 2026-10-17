import Foundation
@testable import LedgerDomain
import Testing

// Helpers for the F09 S2 adversarial suites (gate G2). Every expected value comes from the brief
// ("Plan amendments — slice S2") or from the slow references below, never from the code under test.

enum ScheduleAdversarial {
    static let upperA = template(7101, "Upper A — Push focus", "UA")
    static let lowerA = template(7102, "Lower A — Squat focus", "LA")
    static let upperB = template(7103, "Upper B — Pull focus", "UB")
    static let lowerB = template(7104, "Lower B — Hinge focus", "LB")

    /// Monday 2026-09-14, the start the brief's examples use.
    static let seedStart = Fixtures.civil(2026, 9, 14)

    static func template(_ number: Int, _ name: String, _ tag: String) -> DayTemplate {
        DayTemplate(id: DayTemplateID(Fixtures.uuid(number)), name: name, tag: tag)
    }

    static func week(_ index: Int, deload: Bool = false, _ schedule: [Weekday: DayTemplateID]) -> Week {
        Week(id: WeekID(Fixtures.uuid(7200 + index)), index: index, isDeload: deload, schedule: schedule)
    }

    /// Spec §6.4's seed: weeks 1–7 Mon UA · Wed LA · Fri UB · Sat LB; week 8 Mon UA · Wed LA · Fri UB, deload.
    static func seedProgram(start: CivilDate = seedStart) throws -> Program {
        let full: [Weekday: DayTemplateID] = [
            .monday: upperA.id, .wednesday: lowerA.id, .friday: upperB.id, .saturday: lowerB.id
        ]
        let deload: [Weekday: DayTemplateID] = [.monday: upperA.id, .wednesday: lowerA.id, .friday: upperB.id]
        let weeks = (0 ..< 8).map { week($0, deload: $0 == 7, $0 == 7 ? deload : full) }
        return try program(start: start, weeks: weeks, days: [upperA, lowerA, upperB, lowerB])
    }

    /// A block that trains every day, with a template of its own for every (week, weekday): any
    /// answer that is a day, a week or a weekday off names the wrong template.
    static func everyDayProgram(start: CivilDate, weekCount: Int = 8) throws -> Program {
        var days: [DayTemplate] = []
        var weeks: [Week] = []
        for index in 0 ..< weekCount {
            var schedule: [Weekday: DayTemplateID] = [:]
            for weekday in Weekday.allCases {
                let day = DayTemplate(
                    id: everyDayTemplate(week: index, weekday),
                    name: "W\(index) \(weekday)",
                    tag: "D"
                )
                days.append(day)
                schedule[weekday] = day.id
            }
            weeks.append(week(index, schedule))
        }
        return try program(start: start, weeks: weeks, days: days)
    }

    /// The template `everyDayProgram` schedules on `weekday` of week `index`.
    static func everyDayTemplate(week index: Int, _ weekday: Weekday) -> DayTemplateID {
        DayTemplateID(Fixtures.uuid(100_000 + index * 10 + weekday.rawValue))
    }

    /// "2026-09-06T03:59:59Z" as an instant.
    static func instant(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    static func program(start: CivilDate, weeks: [Week], days: [DayTemplate]) throws -> Program {
        try Program(id: Fixtures.programID, name: "Adversarial", startDate: start, weeks: weeks, days: days)
    }

    static func calendar(_ zone: TimeZone = Fixtures.utc) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = zone
        return gregorian
    }

    static func weeks(
        start: CivilDate = seedStart,
        weekStart: Weekday = .monday,
        zone: TimeZone = Fixtures.utc
    ) -> WeekCalendar {
        WeekCalendar(startDate: start, weekStart: weekStart, calendar: calendar(zone))
    }

    /// A wall-clock moment in `zone`, to the second.
    static func moment(
        _ day: CivilDate,
        _ hour: Int = 12,
        _ minute: Int = 0,
        _ second: Int = 0,
        in zone: TimeZone = Fixtures.utc
    ) throws -> Date {
        let parts = DateComponents(
            year: day.year, month: day.month, day: day.day, hour: hour, minute: minute, second: second
        )
        return try #require(calendar(zone).date(from: parts))
    }

    /// The first instant of `day` in `zone`, as Foundation finds it (midnight, or 01:00 when DST skips it).
    static func startOfDay(_ day: CivilDate, in zone: TimeZone) throws -> Date {
        try calendar(zone).startOfDay(for: moment(day, in: zone))
    }

    /// The civil day of `moment` in `zone`, read with Foundation alone.
    static func civilDay(of moment: Date, in zone: TimeZone) throws -> CivilDate {
        let parts = calendar(zone).dateComponents([.year, .month, .day], from: moment)
        return try #require(CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0))
    }
}

/// The slow, obviously-correct reference for `nextScheduledDay(after:in:)`: every session of the
/// block in date order, found by walking the block one day at a time. `next(after:)` is then the
/// first of them on a later day than the moment's.
struct SessionReference {
    let sessions: [ScheduledDay]
    let zone: TimeZone

    /// The walk the brief describes: noon of every day of the block, asked of `scheduledDay(on:in:)`
    /// and `weekIndex(for:)` (both F02's, and both unchanged by this slice).
    init(walking program: Program, with weeks: WeekCalendar, in zone: TimeZone) throws {
        var found: [ScheduledDay] = []
        for offset in 0 ..< 7 * program.weeks.count {
            guard let day = weeks.startDate.adding(days: offset) else {
                break
            }
            let noon = try ScheduleAdversarial.moment(day, in: zone)
            if let template = weeks.scheduledDay(on: noon, in: program) {
                found.append(ScheduledDay(date: day, weekIndex: weeks.weekIndex(for: noon), dayTemplateID: template))
            }
        }
        sessions = found
        self.zone = zone
    }

    /// The same list without `WeekCalendar`: UTC noons a day apart, Foundation's weekday, and the
    /// week whose `index` is the day's offset ÷ 7 (the first such week, as `Program.week(at:)` reads).
    init(arithmeticOf program: Program, start: CivilDate, in zone: TimeZone) throws {
        let utc = ScheduleAdversarial.calendar()
        let first = try ScheduleAdversarial.moment(start)
        var found: [ScheduledDay] = []
        for offset in 0 ..< 7 * program.weeks.count {
            let noon = first.addingTimeInterval(Double(offset) * 86400)
            let parts = utc.dateComponents([.year, .month, .day, .weekday], from: noon)
            guard let day = CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0) else {
                break
            }
            let weekday = try #require(Weekday(calendarWeekday: parts.weekday ?? 0))
            let week = program.weeks.first { $0.index == offset / 7 }
            if let template = week?.schedule[weekday] {
                found.append(ScheduledDay(date: day, weekIndex: offset / 7, dayTemplateID: template))
            }
        }
        sessions = found
        self.zone = zone
    }

    func next(after moment: Date) throws -> ScheduledDay? {
        let day = try ScheduleAdversarial.civilDay(of: moment, in: zone)
        return sessions.first { $0.date > day }
    }
}
