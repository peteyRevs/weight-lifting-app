@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Seeded checks of `TodayPresentation.make(_:)` against a reference written with Foundation's calendar alone
/// (`+Reference`): which card the decision table gives and which workout it shows, the strip's seven days and
/// what is planned on them, and that the strip, the tiles and the actions agree with one another.
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
    /// moment, handed in shuffled (the input promises no order); and a session that is absent, live, finished
    /// or discarded.
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
        let sinceStart = Int.random(in: -14 * 86400 ..< 70 * 86400, using: &generator)
        let blockStart = Fixtures.date(start.year, start.month, start.day, hour: 12, in: calendar.timeZone)
        let now = blockStart.addingTimeInterval(Double(sinceStart))
        var input = try TodayFixtures.input(
            program: Int.random(in: 0 ..< 8, using: &generator) == 0 ? nil : program,
            now: now,
            settings: settings
        )
        input.calendar = calendar
        // About the program week of `now`: half the workouts are of that week, so today's session is often logged.
        let week = min(max(0, sinceStart / (7 * 86400)), program.weeks.count - 1)
        let workouts = try Self.workouts(of: program, around: now, week: week, using: &generator)
        input.weekWorkouts = workouts.shuffled(using: &generator)
        input.recentWorkouts = workouts.sorted { $0.startedAt > $1.startedAt }
        input.previousWeekVolume = Bool.random(using: &generator) ? Volume(weight: .pounds(22400), reps: .one) : nil
        if Bool.random(using: &generator) {
            var session = try workout(99, of: program, around: now, week: week, using: &generator)
            session.phase = WorkoutPhase.allCases.randomElement(using: &generator) ?? .live
            input.session = session
        }
        return input
    }

    /// Up to eight finished workouts. One in four starts at the instant the one before it did, for the same
    /// session: a tie that the order they are handed in must not decide.
    static func workouts(
        of program: Program,
        around now: Date,
        week: Int,
        using generator: inout SeededGenerator
    ) throws -> [WorkoutState] {
        var workouts: [WorkoutState] = []
        for index in 0 ..< Int.random(in: 0 ... 8, using: &generator) {
            var next = try workout(index, of: program, around: now, week: week, using: &generator)
            if let twin = workouts.last, Int.random(in: 0 ..< 4, using: &generator) == 0 {
                next.startedAt = twin.startedAt
                next.endedAt = twin.endedAt
                next.source = twin.source
            }
            workouts.append(next)
        }
        return workouts
    }

    /// A finished workout that started within eight days of `now`, often in its last hours, for a session of
    /// program week `week` or of any other, or for none.
    static func workout(
        _ number: Int,
        of program: Program,
        around now: Date,
        week: Int,
        using generator: inout SeededGenerator
    ) throws -> WorkoutState {
        let back = Bool.random(using: &generator)
            ? Int.random(in: 0 ..< 36 * 3600, using: &generator)
            : Int.random(in: -86400 ..< 8 * 86400, using: &generator)
        let weekIndex = Bool.random(using: &generator) ? week : Int.random(
            in: 0 ..< program.weeks.count,
            using: &generator
        )
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
