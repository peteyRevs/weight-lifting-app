@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S5 adversarial round 1 (G2): the store against an oracle, on seeded walks over the in-memory stores
/// and the fake session.
///
/// A walk is bursts of one to four steps, taken without waiting for the store between them: a setting saved
/// (any week start, the units, the same again), the program renamed, re-dated (a block that began on any
/// weekday, has not begun, or is over), deleted and saved again, a workout stored or deleted, a workout
/// started, logged in, finished or discarded in the session, the root's task restarted without waiting for
/// the old one (always after a delete: see `deleteWorkout`), and the clock moved on with a restart. After each burst
/// the store must come to show exactly
/// what the oracle makes: `TodayPresentation.make` over the stores as they then stand, with the week's
/// stretch found here from the calendar alone (the stats week and the program week as one stretch, criterion
/// 2), not with `TodayHistory.ranges`. Once it has shown a model it must never show loading or a failure.
@MainActor
@Suite("Adversarial: TodayStore against an oracle", .tags(.feature, .property), .timeLimit(.minutes(10)))
struct TodayStoreWalkAdversarialTests {
    static let zones = ["UTC", "America/Los_Angeles", "Pacific/Auckland", "Asia/Kolkata"]

    @Test("On seeded walks the store comes to the oracle's model after every burst, and never leaves loaded")
    func walks_endAtTheOraclesModel() async throws {
        var failures: [String] = []
        // A walk is some seventy changes; a twentieth of the property seeds keeps the PR lane's cost small
        // (10 walks of 200 seeds, 100 of the nightly 2,000).
        let seeds = PropertySeed.all.prefix(max(10, PropertySeed.all.count / 20))
        for seed in seeds {
            let walk = try TodayWalk(seed: seed, zone: Self.zones[Int(seed.value % 4)])
            if let failure = try await walk.run(bursts: 24) {
                failures.append(failure)
                break
            }
        }
        #expect(failures == [])
    }

    /// Criterion 2 by itself, over many moments: the stretch `TodayHistory.ranges` reads is the stats week and
    /// the program week as one stretch, and the week before is the seven days before the stats week, for any
    /// week start, any weekday the block began on, and zones whose days are 23 and 25 hours long.
    @Test("The stretch that is read is the calendar's two weeks as one, for any week start, block start and zone")
    func ranges_areTheCalendarsWeeks() throws {
        var failures: [String] = []
        let program = try TodayFixtures.program()
        for seed in PropertySeed.all {
            var generator = seed.generator
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: Self.zones[Int(seed.value % 4)]))
            let now = Fixtures.date(2026, 1, 1).addingTimeInterval(Double(Int.random(
                in: 0 ..< 366 * 86400,
                using: &generator
            )))
            var settings = Fixtures.settingsLb
            settings.weekStart = Weekday.allCases.randomElement(using: &generator) ?? .monday
            var dated: Program? = program
            let today = try #require(CivilDate(now, in: calendar))
            dated?.startDate = try #require(today.adding(days: Int.random(in: -70 ... 14, using: &generator)))
            if Int.random(in: 0 ..< 8, using: &generator) == 0 {
                dated = nil
            }
            let made = TodayHistory.ranges(program: dated, settings: settings, now: now, calendar: calendar)
            let wanted = TodayWalk.ranges(program: dated, weekStart: settings.weekStart, now: now, calendar: calendar)
            if made?.week != wanted.week || made?.previousWeek != wanted.previous {
                let start = dated.map { "\($0.startDate)" } ?? "no program"
                failures.append("\(seed) \(calendar.timeZone.identifier) \(now) \(settings.weekStart) \(start)")
            }
        }
        #expect(failures == [])
    }
}
