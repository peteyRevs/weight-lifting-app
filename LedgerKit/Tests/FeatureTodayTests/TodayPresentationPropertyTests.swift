@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// Seeded checks of `TodayPresentation.make(_:)` against a reference written here with Foundation's calendar
/// alone: which card the decision table gives, the strip's seven days, and that the strip, the tiles and the
/// actions agree with one another.
@Suite("TodayPresentation properties", .tags(.feature, .property))
nonisolated struct TodayPresentationPropertyTests {
    /// Zones on both sides of UTC, with and without DST, and three whose clocks change at midnight.
    static let zones = [
        "UTC", "America/Los_Angeles", "Europe/Berlin", "Asia/Kolkata", "Pacific/Kiritimati", "Pacific/Pago_Pago",
        "Australia/Lord_Howe", "Africa/Cairo", "America/Santiago", "America/Havana"
    ]

    @Test("Any input gives the decision table's card, a whole strip and tiles that agree", arguments: PropertySeed.all)
    func make_randomInput_keepsTheInvariants(seed: PropertySeed) throws {
        var generator = seed.generator
        for _ in 0 ..< 4 {
            try Self.check(Self.input(using: &generator))
        }
    }
}

// MARK: - Random inputs

nonisolated extension TodayPresentationPropertyTests {
    /// A random input: the seed program begun on any day of 2026, with a few weeks emptied; any week start; a
    /// moment from two weeks before the block to two weeks after it; up to eight finished workouts around that
    /// moment, of the program's sessions or of none; and a session that is absent, live, finished or discarded.
    static func input(using generator: inout SeededGenerator) throws -> TodayInput {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zones.randomElement(using: &generator) ?? "UTC"))
        let start = try #require(TodayFixtures.civil(2026, 1, 1).adding(days: Int.random(
            in: 0 ..< 365,
            using: &generator
        )))
        var program = try TodayFixtures.program(startingOn: start)
        for index in program.weeks.indices where Int.random(in: 0 ..< 6, using: &generator) == 0 {
            program.weeks[index].schedule = [:]
        }
        var settings = Bool.random(using: &generator) ? Fixtures.settingsLb : Fixtures.settingsKg
        settings.weekStart = Weekday.allCases.randomElement(using: &generator) ?? .monday
        let blockStart = Fixtures.date(start.year, start.month, start.day, hour: 12, in: calendar.timeZone)
        let now = blockStart.addingTimeInterval(Double(Int.random(in: -14 * 86400 ..< 70 * 86400, using: &generator)))
        var input = try TodayFixtures.input(
            program: Int.random(in: 0 ..< 8, using: &generator) == 0 ? nil : program,
            now: now,
            settings: settings
        )
        input.calendar = calendar
        let workouts = try (0 ..< Int.random(in: 0 ... 8, using: &generator)).map { index in
            try workout(index, of: program, around: now, using: &generator)
        }
        input.weekWorkouts = workouts.sorted { $0.startedAt > $1.startedAt }
        input.recentWorkouts = input.weekWorkouts
        input.previousWeekVolume = Bool.random(using: &generator) ? Volume(weight: .pounds(22400), reps: .one) : nil
        if Bool.random(using: &generator) {
            var session = try workout(99, of: program, around: now, using: &generator)
            session.phase = WorkoutPhase.allCases.randomElement(using: &generator) ?? .live
            input.session = session
        }
        return input
    }

    /// A finished workout that started within eight days of `now`, often in its last hours, for a random
    /// session of the program's weeks around `now` or for none.
    static func workout(
        _ number: Int,
        of program: Program,
        around now: Date,
        using generator: inout SeededGenerator
    ) throws -> WorkoutState {
        let back = Bool.random(using: &generator)
            ? Int.random(in: 0 ..< 36 * 3600, using: &generator)
            : Int.random(in: -86400 ..< 8 * 86400, using: &generator)
        let weekIndex = Int.random(in: 0 ..< program.weeks.count, using: &generator)
        let source = Int.random(in: 0 ..< 5, using: &generator) == 0 ? nil : TodayFixtures.source(
            of: program,
            weekIndex: weekIndex,
            dayIndex: Int.random(in: 0 ..< program.days.count, using: &generator)
        )
        return try TodayFixtures.workout(
            number + 1,
            pounds: Decimal(Int.random(in: 0 ... 30000, using: &generator)),
            startedAt: now.addingTimeInterval(-Double(back)),
            source: source
        )
    }
}

// MARK: - The reference and the checks

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

        /// Whole days from the block's first day to the day of `now`, by the calendar.
        func dayOfBlock(_ program: Program) throws -> Int {
            let start = program.startDate
            let first = try #require(calendar.date(from: DateComponents(
                year: start.year, month: start.month, day: start.day, hour: 12
            )))
            return try #require(calendar.dateComponents([.day], from: first, to: noon(of: input.now)).day)
        }

        /// The card the decision table gives, by name.
        func card() throws -> String {
            if input.session?.phase == .live {
                return "upNext"
            }
            guard let program = input.program else {
                return "noProgram"
            }
            let day = try dayOfBlock(program)
            guard day < 7 * program.weeks.count else {
                return "blockComplete"
            }
            let weekday = try #require(Weekday(calendarWeekday: calendar.component(.weekday, from: input.now)))
            guard day >= 0, let template = program.weeks[day / 7].schedule[weekday] else {
                return "restDay"
            }
            let source = WorkoutSource(programID: program.id, weekIndex: day / 7, dayTemplateID: template)
            let isLogged = finished.contains { $0.source == source && isSameDay($0.startedAt, input.now) }
            return isLogged ? "logged" : "upNext"
        }

        /// The seven days of the stats week of `now`, each at noon, by the calendar.
        func stripDays() throws -> [Date] {
            let today = try noon(of: input.now)
            let weekday = try #require(Weekday(calendarWeekday: calendar.component(.weekday, from: today)))
            let back = (weekday.rawValue - input.settings.weekStart.rawValue + 7) % 7
            return try (0 ..< 7).map { try #require(calendar.date(byAdding: .day, value: $0 - back, to: today)) }
        }
    }

    /// Every route of the model that starts or edits something, with the place it stands.
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
        // Exactly one card, and it is the decision table's; it resumes exactly when a workout is live.
        #expect(try model.card.kind == reference.card(), context)
        if let card = model.card.upNext {
            let resumes = card.action.action.route == .resumeWorkout
            #expect(resumes == (input.session?.phase == .live), context)
        }
        let days = try reference.stripDays()
        try checkStrip(model.weekStrip, days: days, reference, context)
        checkTiles(model, days: days, reference, context)
        checkRoutes(model, input, context)
        #expect(model.recent.rows.count <= 5, context)
        #expect(model.recent.rows.isEmpty == (model.recent.emptyMessage != nil), context)
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

    /// The tiles and the strip agree on what was done: the sessions that started in the seven days.
    static func checkTiles(_ model: TodayModel, days: [Date], _ reference: Reference, _ context: Comment) {
        let input = reference.input
        let sessions = reference.finished.filter { workout in
            days.contains { reference.isSameDay($0, workout.startedAt) }
        }
        let trainedDays = days.count { day in sessions.contains { reference.isSameDay($0.startedAt, day) } }
        #expect(model.stats.sessions.value == "\(sessions.count)", context)
        #expect(model.weekStrip.count { $0.mark == .done } == trainedDays, context)
        let volume = sessions.reduce(Volume.zero) { $0 + $1.volume }
        #expect(model.stats.volume.value == volume.thousands(in: input.settings.units), context)
        if input.program == nil {
            #expect(model.stats.sessions.unit == "/0", context)
            #expect(!model.weekStrip.contains { $0.mark == .planned }, context)
        }
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
