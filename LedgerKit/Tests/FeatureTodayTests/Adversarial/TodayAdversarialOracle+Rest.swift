@testable import FeatureToday
import Foundation
import LedgerDomain

/// The rulings after round 1 (the brief's criteria 15 to 17), as the tester reads them: the rest-day body and
/// the Logged card's "Next:" line, written from the brief's wording before the changed bodies were read.
nonisolated extension TodayOracle {
    /// A session the program schedules: its calendar day, its program week and its day template.
    struct Coming {
        let date: CivilDate
        let week: Int
        let day: DayTemplateID
    }

    /// The first day after `today` on which the program schedules a session, each day judged by its own
    /// program week, no further than the block's last week (`weeks.count` weeks from its start).
    static func nextSession(after today: CivilDate, in program: Program) -> Coming? {
        var offset = max(today.days(since: program.startDate) + 1, 0)
        while offset < 7 * program.weeks.count {
            if let date = program.startDate.adding(days: offset), let found = session(on: date, in: program) {
                return Coming(date: date, week: found.week, day: found.day)
            }
            offset += 1
        }
        return nil
    }

    /// The rest-day body; nil without a program.
    /// - Criterion 16: before the block, "Your block starts on {date}.", the date as the header writes one.
    /// - Criterion 15: "Next up is {weekday}." when the next session's date is one of the strip's seven days,
    ///   "Next up is next {weekday}." when it is not; the first sentence names the program week.
    /// - Criterion 17: with no session left, "This is the last week of the block." in the block's last week
    ///   and "No sessions are left in this block." in any earlier one.
    func restBody(for input: TodayInput) -> String? {
        guard let program = input.program else {
            return nil
        }
        let index = Self.weekIndex(of: today, in: program)
        guard index >= 0 else {
            return "Your block starts on \(Support.fullDate(program.startDate))."
        }
        let first = "Nothing scheduled for \(Support.weekdayName(today.weekday)) in week \(index + 1)."
        guard let next = Self.nextSession(after: today, in: program) else {
            let isLastWeek = index == program.weeks.count - 1
            return first +
                (isLastWeek ? " This is the last week of the block." : " No sessions are left in this block.")
        }
        let weekday = Support.weekdayName(next.date.weekday)
        return first + (days.contains(next.date) ? " Next up is \(weekday)." : " Next up is next \(weekday).")
    }

    /// What the Logged card's "Next:" line may read (criterion 5, and 15's "must never name the week the lifter
    /// is in"): the next session's weekday and tag while it is in today's program week; a later week's number,
    /// which the brief writes as the week after this one and which is the next session's own week when weeks
    /// between are empty; nothing when the block has no later session.
    func nextLines(for input: TodayInput) -> [String?] {
        guard let program = input.program, let next = Self.nextSession(after: today, in: program) else {
            return [nil]
        }
        let index = Self.weekIndex(of: today, in: program)
        guard next.week == index else {
            return ["Next: week \(next.week + 1)", "Next: week \(index + 2)"]
        }
        let tag = program.days.first { $0.id == next.day }?.tag ?? ""
        return ["Next: \(Support.weekdayName(next.date.weekday)) · \(tag)"]
    }
}
