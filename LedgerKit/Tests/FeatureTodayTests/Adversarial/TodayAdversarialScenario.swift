@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// One seeded input for the model suites (testing-strategy §3 rule 5): a time zone, a week start, units, the
/// seed program begun on any weekday with its schedule sometimes edited (or no program), a moment from nine
/// days before the block to nine days after it, up to five finished workouts around today, and the session's
/// workout in each of its states. The same seed always gives the same input.
///
/// The week's workouts are handed over newest first, as `WorkoutRepository.workouts(in:)` returns them, unless
/// `asGenerated` asks for the order they were made in: `TodayInput.weekWorkouts` promises no order.
nonisolated struct TodayScenario {
    typealias Support = TodayAdversarial

    let seed: UInt64
    let input: TodayInput
    /// A few words about the input, for a failure's line.
    let note: String

    static let zones = [
        "UTC", "Pacific/Kiritimati", "Etc/GMT+12", "America/Santiago", "Africa/Cairo", "Asia/Kathmandu",
        "America/Havana", "Australia/Lord_Howe", "Pacific/Chatham", "America/St_Johns", "Asia/Beirut"
    ]
    static let otherProgram = ProgramID(Fixtures.uuid(7777))

    init(seed: UInt64, catalog: [ExerciseID: Exercise], asGenerated: Bool = false) throws {
        var random = AdversarialRandom(seed: seed)
        let zone = try Support.zone(Self.zones.randomElement(using: &random) ?? "UTC")
        let calendar = Support.calendar(zone)
        let weekStart = Weekday.allCases.randomElement(using: &random) ?? .monday
        let settings = Support.settings(Bool.random(using: &random) ? .lb : .kg, weekStart: weekStart)
        let program = try Self.program(&random)
        let today = try Self.today(program, &random)
        let now = Self.moment(of: today, calendar, &random)
        let sources = Self.sources(program, today: today)
        var workouts: [WorkoutState] = []
        for number in 0 ..< Int.random(in: 0 ... 5, using: &random) {
            let isToday = number == 0 && Bool.random(using: &random)
            let day = try #require(today.adding(days: isToday ? 0 : Int.random(in: -8 ... 8, using: &random)))
            let second = Int.random(in: 2 * 3600 ... 21 * 3600, using: &random)
            let start = day.startOfDay(in: calendar).addingTimeInterval(TimeInterval(second))
            let source = isToday ? sources[0] : sources.randomElement(using: &random) ?? nil
            try workouts.append(Self.workout(number: 100 + number, start: start, source: source, &random))
        }
        let session = try Self.session(now: now, workouts: workouts, sources: sources, &random)
        let previous: [Volume?] = [nil, .zero, Volume(weight: .pounds(1000), reps: Reps(clamping: 7))]
        self.seed = seed
        input = TodayInput(
            program: program,
            exercises: catalog,
            settings: settings,
            weekWorkouts: asGenerated ? workouts : Self.newestFirst(workouts),
            recentWorkouts: Self.newestFirst(workouts),
            previousWeekVolume: previous.randomElement(using: &random) ?? nil,
            session: session,
            now: now,
            calendar: calendar,
            locale: Support.english
        )
        let block = program.map { "block from \($0.startDate), \($0.weeks.count) weeks" } ?? "no program"
        let state = session?.phase.rawValue ?? "none"
        note = "\(zone.identifier) \(today) week from \(weekStart), \(block), session \(state)"
    }
}

nonisolated extension TodayScenario {
    /// The repository's order: newest start first, and of two that started together the smaller id first.
    static func newestFirst(_ workouts: [WorkoutState]) -> [WorkoutState] {
        workouts.sorted { first, second in
            first.startedAt == second.startedAt
                ? first.id.rawValue.uuidString < second.id.rawValue.uuidString
                : first.startedAt > second.startedAt
        }
    }

    static func program(_ random: inout AdversarialRandom) throws -> Program? {
        guard Int.random(in: 0 ..< 8, using: &random) != 0 else {
            return nil
        }
        let shift = Int.random(in: -10 ... 10, using: &random)
        let start: CivilDate = try #require(Support.civil(2026, 9, 14).adding(days: shift))
        var program = try Support.seed(start: start)
        if Int.random(in: 0 ..< 3, using: &random) == 0 {
            program.weeks[Int.random(in: 0 ..< 8, using: &random)].schedule = [:]
        }
        if Int.random(in: 0 ..< 3, using: &random) == 0 {
            program.weeks[Int.random(in: 0 ..< 8, using: &random)].schedule[.sunday] = program.days[3].id
        }
        if Int.random(in: 0 ..< 4, using: &random) == 0, let weekday = Weekday.allCases.randomElement(using: &random) {
            for index in program.weeks.indices {
                program.weeks[index].schedule[weekday] = nil
            }
        }
        if Int.random(in: 0 ..< 8, using: &random) == 0 {
            program.weeks = Array(program.weeks.prefix(2))
        }
        return program
    }

    static func today(_ program: Program?, _ random: inout AdversarialRandom) throws -> CivilDate {
        let start = try program?.startDate ?? Support.civil(2026, 9, 14)
        let length = 7 * (program?.weeks.count ?? 8)
        return try #require(start.adding(days: Int.random(in: -9 ... length + 9, using: &random)))
    }

    /// The day's first instant, its second second, its last second, a moment twelve hours in, or any other.
    static func moment(of day: CivilDate, _ calendar: Calendar, _ random: inout AdversarialRandom) -> Date {
        let start = day.startOfDay(in: calendar)
        let next = day.adding(days: 1)?.startOfDay(in: calendar) ?? start
        switch Int.random(in: 0 ..< 5, using: &random) {
        case 0: return start
        case 1: return start.addingTimeInterval(1)
        case 2: return next.addingTimeInterval(-1)
        case 3: return start.addingTimeInterval(12 * 3600)
        default: return start.addingTimeInterval(TimeInterval(Int.random(in: 0 ..< 22 * 3600, using: &random)))
        }
    }

    /// Where a workout may come from. The first is today's own session when there is one; the others are the
    /// same day a week off, another day of the week, another program, and no program at all.
    static func sources(_ program: Program?, today: CivilDate) -> [WorkoutSource?] {
        guard let program else {
            return [
                nil,
                WorkoutSource(programID: otherProgram, weekIndex: 0, dayTemplateID: DayTemplateID(Fixtures.uuid(1)))
            ]
        }
        let week = max(0, TodayOracle.weekIndex(of: today, in: program))
        let day = TodayOracle.session(on: today, in: program)?.day ?? program.days[0].id
        let other = program.days.first { $0.id != day }?.id ?? day
        let own = WorkoutSource(programID: program.id, weekIndex: week, dayTemplateID: day)
        return [
            own, own, own,
            WorkoutSource(programID: program.id, weekIndex: week + 1, dayTemplateID: day),
            WorkoutSource(programID: program.id, weekIndex: week, dayTemplateID: other),
            WorkoutSource(programID: otherProgram, weekIndex: week, dayTemplateID: day),
            nil
        ]
    }

    static func workout(
        number: Int,
        start: Date,
        seconds: Int = 3000,
        source: WorkoutSource?,
        _ random: inout AdversarialRandom
    ) throws -> WorkoutState {
        let lifts = (0 ..< Int.random(in: 1 ... 3, using: &random)).map { _ in
            Support.Lift.pounds(
                Decimal(Int.random(in: 0 ... 1600, using: &random)) / 4,
                Int.random(in: 1 ... 12, using: &random)
            )
        }
        return try Support.lifted(
            number: number,
            start: start,
            seconds: seconds,
            lifts: lifts,
            name: "Workout \(number) — seeded",
            tag: "W\(number % 10)",
            source: source
        )
    }

    /// None (4 in 10), live (2), finished a moment ago and not yet in history (2), finished and already in
    /// history (1), discarded (1).
    static func session(
        now: Date,
        workouts: [WorkoutState],
        sources: [WorkoutSource?],
        _ random: inout AdversarialRandom
    ) throws -> WorkoutState? {
        let kind = Int.random(in: 0 ..< 10, using: &random)
        guard kind > 3 else {
            return nil
        }
        if kind == 8 {
            return workouts.first
        }
        let age = Int.random(in: 60 ... 7200, using: &random)
        let source = sources.randomElement(using: &random) ?? nil
        var session = try workout(
            number: 900,
            start: now.addingTimeInterval(TimeInterval(-age)),
            seconds: age,
            source: source,
            &random
        )
        if kind < 6 {
            session.phase = .live
            session.endedAt = nil
        } else if kind == 9 {
            session.phase = .discarded
        }
        return session
    }
}
