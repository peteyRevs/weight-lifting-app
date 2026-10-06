@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain

/// What the specification says Today shows for an input: the tester's own model, written from the brief's S3
/// criteria 1, 2 and 4–8 before any of the feature's bodies was read (gate G2).
///
/// Days are civil dates in the input calendar's time zone, read here with Foundation's own Gregorian calendar.
/// A day's program week is `floor(days since the block's start ÷ 7)`; the strip's first day is the latest
/// `weekStart` on or before today.
nonisolated struct TodayOracle {
    enum Card: Equatable, CustomStringConvertible {
        /// Criterion 4: a live workout takes the card, whatever the calendar says.
        case resume(WorkoutID)
        /// Criterion 3: today's session, not yet logged.
        case start(week: Int, day: DayTemplateID)
        /// Criterion 5: today's session finished today; the newest such workout (several when they tie).
        case logged(Set<WorkoutID>, week: Int)
        /// Criterion 6: no session today, or a day before the block (its first week).
        case rest(week: Int)
        case noProgram
        case blockComplete

        var description: String {
            switch self {
            case .resume: "resume"
            case let .start(week, _): "start(week \(week))"
            case let .logged(ids, week): "logged(\(ids.count) candidate(s), week \(week))"
            case let .rest(week): "rest(week \(week))"
            case .noProgram: "noProgram"
            case .blockComplete: "blockComplete"
            }
        }
    }

    let today: CivilDate
    /// The strip's seven days.
    let days: [CivilDate]
    let card: Card
    let title: String
    let marks: [WeekStrip.Mark]
    /// Finished workouts that started in the strip's days, each counted.
    let done: Int
    /// The strip's days on which the program schedules a session, each by its own program week.
    let planned: Int
    /// Σ of the volumes of the workouts counted in `done`, exactly.
    let volume: Volume

    init?(_ input: TodayInput) {
        guard let current = Self.civil(input.now, input.calendar) else {
            return nil
        }
        let back = (current.weekday.rawValue - input.settings.weekStart.rawValue + 7) % 7
        let strip = (0 ..< 7).compactMap { current.adding(days: $0 - back) }
        guard strip.count == 7 else {
            return nil
        }
        let finished = Self.finished(input)
        let starts = finished.compactMap { Self.civil($0.startedAt, input.calendar) }
        let inStrip = finished.filter { workout in
            Self.civil(workout.startedAt, input.calendar).map(strip.contains) ?? false
        }
        today = current
        days = strip
        card = Self.card(input, today: current, finished: finished)
        title = Self.title(input.program, today: current)
        marks = strip.map { day in
            if starts.contains(day) {
                .done
            } else if day == current {
                .today
            } else {
                Self.session(on: day, in: input.program) == nil ? .rest : .planned
            }
        }
        done = inStrip.count
        planned = strip.count { Self.session(on: $0, in: input.program) != nil }
        volume = inStrip.reduce(Volume.zero) { $0 + $1.volume }
    }
}

nonisolated extension TodayOracle {
    static func civil(_ date: Date, _ calendar: Calendar) -> CivilDate? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// The program week `day` falls in; negative before the block.
    static func weekIndex(of day: CivilDate, in program: Program) -> Int {
        let offset = day.days(since: program.startDate)
        return offset >= 0 ? offset / 7 : -((6 - offset) / 7)
    }

    /// The session the program schedules on `day`, judged by that day's own program week.
    static func session(on day: CivilDate, in program: Program?) -> (week: Int, day: DayTemplateID)? {
        guard let program else {
            return nil
        }
        let index = weekIndex(of: day, in: program)
        guard index >= 0, let template = program.weeks.first(where: { $0.index == index })?.schedule[day.weekday]
        else {
            return nil
        }
        return (index, template)
    }

    /// The week's finished workouts, with the session's own once it is finished, each id once.
    static func finished(_ input: TodayInput) -> [WorkoutState] {
        var finished = input.weekWorkouts.filter { $0.phase == .finished }
        if let session = input.session, session.phase == .finished, !finished.contains(where: { $0.id == session.id }) {
            finished.append(session)
        }
        return finished
    }

    static func card(_ input: TodayInput, today: CivilDate, finished: [WorkoutState]) -> Card {
        if let session = input.session, session.phase == .live {
            return .resume(session.id)
        }
        guard let program = input.program else {
            return .noProgram
        }
        let index = weekIndex(of: today, in: program)
        if index >= program.weeks.count {
            return .blockComplete
        }
        guard let session = session(on: today, in: program) else {
            return .rest(week: max(0, index))
        }
        let source = WorkoutSource(programID: program.id, weekIndex: session.week, dayTemplateID: session.day)
        let logged = finished.filter { $0.source == source && civil($0.startedAt, input.calendar) == today }
        guard let newest = logged.map(\.startedAt).max() else {
            return .start(week: session.week, day: session.day)
        }
        return .logged(Set(logged.filter { $0.startedAt == newest }.map(\.id)), week: session.week)
    }

    /// Criterion 1: the day's name before " — ", "Rest day", or "Today" without a program or after the block.
    static func title(_ program: Program?, today: CivilDate) -> String {
        guard let program, weekIndex(of: today, in: program) < program.weeks.count else {
            return "Today"
        }
        guard let session = session(on: today, in: program),
              let name = program.days.first(where: { $0.id == session.day })?.name
        else {
            return "Rest day"
        }
        return name.components(separatedBy: " — ").first ?? name
    }
}
