@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// The reference the seeded checks compare with, and the checks.
nonisolated extension TodayPresentationPropertyTests {
    /// The reference, with Foundation's calendar alone: day numbers come from the calendar's own components.
    struct Reference {
        let input: TodayInput
        let calendar: Calendar

        init(_ input: TodayInput) {
            self.input = input
            calendar = input.calendar
        }

        /// Noon of the calendar day `date` falls on.
        func noon(of date: Date) throws -> Date {
            var parts = calendar.dateComponents([.year, .month, .day], from: date)
            parts.hour = 12
            return try #require(calendar.date(from: parts))
        }

        func isSameDay(_ first: Date, _ second: Date) -> Bool {
            calendar.dateComponents([.year, .month, .day], from: first)
                == calendar.dateComponents([.year, .month, .day], from: second)
        }

        /// The finished workouts the model counts: the week's, and the session's own once it is finished.
        var finished: [WorkoutState] {
            let session = input.session.flatMap { $0.phase == .finished ? $0 : nil }
            return input.weekWorkouts + (session.map { [$0] } ?? [])
        }

        /// Whole days from the block's first day to the day of `date`, by the calendar.
        func dayOfBlock(_ program: Program, on date: Date) throws -> Int {
            let start = program.startDate
            let first = try #require(calendar.date(from: DateComponents(
                year: start.year, month: start.month, day: start.day, hour: 12
            )))
            return try #require(calendar.dateComponents([.day], from: first, to: noon(of: date)).day)
        }

        /// The session the program schedules on the day of `date`, as a workout's source; nil on a rest day,
        /// before and after the block, and with no program.
        func session(on date: Date) throws -> WorkoutSource? {
            guard let program = input.program else {
                return nil
            }
            let day = try dayOfBlock(program, on: date)
            let weekday = try #require(Weekday(calendarWeekday: calendar.component(.weekday, from: date)))
            guard (0 ..< 7 * program.weeks.count).contains(day),
                  let template = program.weeks[day / 7].schedule[weekday]
            else {
                return nil
            }
            return WorkoutSource(programID: program.id, weekIndex: day / 7, dayTemplateID: template)
        }

        /// The finished workouts of today's session that started today.
        func loggedToday() throws -> [WorkoutState] {
            let source = try session(on: input.now)
            return finished.filter { source != nil && $0.source == source && isSameDay($0.startedAt, input.now) }
        }

        /// The card the decision table gives, by name.
        func card() throws -> String {
            if input.session?.phase == .live {
                return "upNext"
            }
            guard let program = input.program else {
                return "noProgram"
            }
            guard try dayOfBlock(program, on: input.now) < 7 * program.weeks.count else {
                return "blockComplete"
            }
            guard try session(on: input.now) != nil else {
                return "restDay"
            }
            return try loggedToday().isEmpty ? "upNext" : "logged"
        }

        /// The seven days of the stats week of `now`, each at noon, by the calendar.
        func stripDays() throws -> [Date] {
            let today = try noon(of: input.now)
            let weekday = try #require(Weekday(calendarWeekday: calendar.component(.weekday, from: today)))
            let back = (weekday.rawValue - input.settings.weekStart.rawValue + 7) % 7
            return try (0 ..< 7).map { try #require(calendar.date(byAdding: .day, value: $0 - back, to: today)) }
        }
    }

    /// Every route of the model that starts or edits something.
    static func programRoutes(of model: TodayModel) -> [TodayRoute] {
        switch model.card {
        case let .upNext(card): [card.action.action.route]
        case let .restDay(card): [card.editWeek.route] + card.offSchedule.days.map(\.route)
        case .logged, .noProgram, .blockComplete: []
        }
    }

    /// What a failing check prints: the input in a line, never the model.
    static func summary(of input: TodayInput) -> Comment {
        let block = input.program.map { "\($0.startDate)" } ?? "none"
        let session = input.session.map { "\($0.phase)" } ?? "none"
        let zone = input.calendar.timeZone.identifier
        return "\(zone), now \(input.now), week from \(input.settings.weekStart), block \(block), session \(session)"
    }

    static func check(_ input: TodayInput) throws {
        let model = TodayPresentation.make(input)
        let reference = Reference(input)
        let context = summary(of: input)
        try checkCard(model, reference, context)
        let days = try reference.stripDays()
        try checkStrip(model.weekStrip, days: days, reference, context)
        try checkTiles(model, days: days, reference, context)
        checkRoutes(model, input, context)
        #expect(model.recent.rows.count <= 5, context)
        #expect(model.recent.rows.isEmpty == (model.recent.emptyMessage != nil), context)
        // The order the week's workouts are handed in changes nothing (criterion 13).
        var reversed = input
        reversed.weekWorkouts.reverse()
        let isSame = TodayPresentation.make(reversed) == model
        #expect(isSame, context)
    }

    /// Exactly one card, and it is the decision table's. It resumes exactly when a workout is live, and a
    /// Logged card shows the one of today's that started last (any of them, when several started together).
    static func checkCard(_ model: TodayModel, _ reference: Reference, _ context: Comment) throws {
        #expect(try model.card.kind == reference.card(), context)
        if let card = model.card.upNext {
            let resumes = card.action.action.route == .resumeWorkout
            #expect(resumes == (reference.input.session?.phase == .live), context)
        }
        if let card = model.card.logged {
            let logged = try reference.loggedToday()
            let newest = logged.map(\.startedAt).max()
            let routes = logged.filter { $0.startedAt == newest }.map { TodayRoute.openWorkout($0.id) }
            #expect(routes.contains(card.action.route), context)
        }
    }

    /// Seven strip days from the week start, today among them, each spoken as its own date.
    static func checkStrip(
        _ strip: [WeekStrip.Day],
        days: [Date],
        _ reference: Reference,
        _ context: Comment
    ) throws {
        let input = reference.input
        let style = Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: input.locale,
            calendar: input.calendar,
            timeZone: input.calendar.timeZone
        )
        let spoken = days.map { $0.formatted(style.weekday(.wide).month(.wide).day()) }
        #expect(strip.count == 7, context)
        #expect(strip.map { $0.accessibilitySummary.replacing("Today, ", with: "") } == spoken, context)
        let todayIndex = try #require(days.firstIndex { reference.isSameDay($0, input.now) })
        let todaysMark = strip[todayIndex].mark
        #expect(todaysMark == .today || todaysMark == .done, context)
        #expect(strip.count { $0.mark == .today } <= 1, context)
    }

    /// The tiles and the strip agree on what was done, the sessions that started in the seven days, and on
    /// what is planned: the days of the seven on which the program schedules a session, each judged by its own
    /// program week.
    static func checkTiles(
        _ model: TodayModel,
        days: [Date],
        _ reference: Reference,
        _ context: Comment
    ) throws {
        let input = reference.input
        let sessions = reference.finished.filter { workout in
            days.contains { reference.isSameDay($0, workout.startedAt) }
        }
        let trainedDays = days.count { day in sessions.contains { reference.isSameDay($0.startedAt, day) } }
        #expect(model.stats.sessions.value == "\(sessions.count)", context)
        #expect(model.weekStrip.count { $0.mark == .done } == trainedDays, context)
        let volume = sessions.reduce(Volume.zero) { $0 + $1.volume }
        #expect(model.stats.volume.value == volume.thousands(in: input.settings.units), context)
        let planned = try days.map { try reference.session(on: $0) != nil }
        #expect(model.stats.sessions.unit == "/\(planned.count { $0 })", context)
        // A planned mark stands only on a planned day, and no planned day is marked as a rest day.
        let marks = zip(model.weekStrip.map(\.mark), planned)
        #expect(!marks.contains { $0 == .planned && !$1 }, context)
        #expect(!marks.contains { $0 == .rest && $1 }, context)
    }

    /// Every action that starts or edits names the active program and one of its weeks.
    static func checkRoutes(_ model: TodayModel, _ input: TodayInput, _ context: Comment) {
        for route in programRoutes(of: model) {
            switch route {
            case let .startWorkout(program, weekIndex, _), let .editWeek(program, weekIndex):
                #expect(program == input.program?.id, context)
                #expect((0 ..< 8).contains(weekIndex), context)
            case .resumeWorkout:
                #expect(input.session?.phase == .live, context)
            case .openWorkout, .openProgram, .settings, .setUpProgram:
                Issue.record("a route that neither starts, resumes nor edits: \(route)")
            }
        }
    }
}
