import Foundation
@testable import LedgerDomain
import Testing

/// Seeded invariants for ADR-007's new surface: exact `Weight`/`Volume` and `CivilDate`.
@Suite("Exact weight and civil date properties (adversarial, ADR-007)", .tags(.domain, .property))
struct ExactPropertyAdversarialTests {
    static let utcGregorian = WeekCalendarAdversarialTests.calendar()

    /// A random decimal with up to `scale` fractional digits in ±`limit`.
    static func randomDecimal(scale: Int, limit: Int, using generator: inout SeededGenerator) -> Decimal {
        let quantum = (0 ..< scale).reduce(Decimal(1)) { value, _ in value / 10 }
        return Decimal(Int.random(in: -limit ... limit, using: &generator)) * quantum
    }

    static func randomCivil(using generator: inout SeededGenerator) throws -> CivilDate {
        try #require(CivilDate(year: 1600, month: 1, day: 1)?.adding(days: Int.random(
            in: 0 ... 292_000,
            using: &generator
        )))
    }
}

extension ExactPropertyAdversarialTests {
    @Test(
        "Summing pound weights with + equals the pound literal of the decimal sum (no drift).",
        arguments: PropertySeed.all
    )
    func plus_equalsDecimalSum(seed: PropertySeed) {
        var generator = seed.generator
        let values = (0 ..< Int.random(in: 1 ... 60, using: &generator)).map { _ in
            Self.randomDecimal(scale: 2, limit: 50000, using: &generator)
        }
        let total = values.reduce(Weight.zero) { $0 + .pounds($1) }
        let sum = values.reduce(Decimal(0), +)
        #expect(total == .pounds(sum))
        #expect(total.pounds == sum)
    }

    @Test(
        "Equal values built along different paths hash equally, including trailing zeros.",
        arguments: PropertySeed.all
    )
    func hash_isNumeric(seed: PropertySeed) {
        var generator = seed.generator
        let value = Self.randomDecimal(scale: 6, limit: 1_000_000_000, using: &generator)
        let padded = value * 1000 / 1000
        let viaText = dec(value.description.contains(".") ? "\(value)000" : "\(value).000")
        let weights = [
            Weight(grams: value),
            Weight(grams: padded),
            Weight(grams: viaText),
            Weight(grams: value) + .zero
        ]
        #expect(Set(weights).count == 1, "\(value)")
        #expect(Set(weights.map(\.hashValue)).count == 1, "\(value)")
        let volumes = weights.map { Volume(gramReps: $0.grams) }
        #expect(Set(volumes).count == 1, "\(value)")
    }

    @Test("Weight and Volume Codable round-trips are exact for arbitrary decimals.", arguments: PropertySeed.all)
    func codable_isExact(seed: PropertySeed) throws {
        var generator = seed.generator
        let grams = Self.randomDecimal(scale: 9, limit: Int.max / 4, using: &generator)
        #expect(try Adversarial.roundTrip(Weight(grams: grams)).grams == grams)
        #expect(try Adversarial.roundTrip(Volume(gramReps: grams)).gramReps == grams)
        let pounds = Weight.pounds(Self.randomDecimal(scale: 4, limit: 10_000_000, using: &generator))
        #expect(try Adversarial.roundTrip(pounds) == pounds)
    }

    @Test(
        "A half-step tie on any step rounds away from zero by default and to even under .toNearestOrEven.",
        arguments: PropertySeed.all
    )
    func rounded_exactTies(seed: PropertySeed) {
        var generator = seed.generator
        let steps = [pounds("1.25"), pounds("2.5"), pounds("5"), kilos("1.25"), kilos("2.5"), kilos("0.5"), kilos("11")]
        let step = steps.randomElement(using: &generator) ?? pounds("5")
        let count = Int.random(in: 0 ... 400, using: &generator)
        let tie = step.scaled(by: Decimal(count) + dec("0.5"))
        #expect(tie.rounded(toStep: step) == step.scaled(by: Decimal(count + 1)), "\(count) + ½ × \(step.grams) g")
        #expect(tie.rounded(toStep: step, .toNearestOrEven) == step
            .scaled(by: Decimal(count.isMultiple(of: 2) ? count : count + 1)))
        #expect(tie.scaled(by: -1).rounded(toStep: step) == step.scaled(by: Decimal(-(count + 1))))
        let multiple = step.scaled(by: Decimal(count))
        #expect(multiple.rounded(toStep: step, .up) == multiple)
        #expect(multiple.rounded(toStep: step, .down) == multiple)
    }

    @Test(
        "Sets summed as volume equal the exact pound total and format as its whole number.",
        arguments: PropertySeed.all
    )
    func volume_sumIsExact(seed: PropertySeed) {
        var generator = seed.generator
        var total = Volume.zero
        var poundReps = Decimal(0)
        for _ in 0 ..< Int.random(in: 1 ... 2000, using: &generator) {
            let load = randomMultiple(of: dec("2.5"), in: 0 ... 240, using: &generator)
            let reps = 2 * Int.random(in: 1 ... 10, using: &generator)
            total += Volume(weight: .pounds(load), reps: Reps(clamping: reps))
            poundReps += load * Decimal(reps)
        }
        #expect(total == Volume(gramReps: Weight.pounds(poundReps).grams))
        let whole = NSDecimalNumber(decimal: poundReps).intValue
        #expect(total.formatted(in: .lb) == whole
            .formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US"))))
    }

    @Test(
        "CivilDate day numbers, weekdays and day steps agree with Foundation (1600–2399).",
        arguments: PropertySeed.all
    )
    func civilDate_matchesFoundation(seed: PropertySeed) throws {
        var generator = seed.generator
        let date = try Self.randomCivil(using: &generator)
        let midnight = try #require(Self.utcGregorian.date(from: DateComponents(
            year: date.year,
            month: date.month,
            day: date.day
        )))
        #expect(date.daysSinceEpoch == Int(midnight.timeIntervalSince1970 / 86400), "\(date)")
        #expect(
            date.weekday == Weekday(calendarWeekday: Self.utcGregorian.component(.weekday, from: midnight)),
            "\(date)"
        )
        #expect(CivilDate(midnight, in: Self.utcGregorian) == date)
        let step = Int.random(in: -5000 ... 5000, using: &generator)
        let moved = try #require(date.adding(days: step))
        let foundation = try #require(Self.utcGregorian.date(byAdding: .day, value: step, to: midnight))
        #expect(moved == CivilDate(foundation, in: Self.utcGregorian), "\(date) + \(step)")
        #expect(moved.days(since: date) == step)
        #expect((moved < date) == (step < 0))
    }

    @Test("CivilDate survives text, JSON and startOfDay round-trips in any zone.", arguments: PropertySeed.all)
    func civilDate_roundTrips(seed: PropertySeed) throws {
        var generator = seed.generator
        let date = try Self.randomCivil(using: &generator)
        #expect(CivilDate(iso8601: date.description) == date)
        #expect(try Adversarial.roundTrip(date) == date)
        let identifier = (WeekCalendarTravelAdversarialTests.zones + ["Asia/Beirut", "Asia/Tehran"])
            .randomElement(using: &generator)
        let calendar = try WeekCalendarAdversarialTests.calendar(Fixtures.zone(identifier ?? "UTC"))
        let start = date.startOfDay(in: calendar)
        #expect(CivilDate(start, in: calendar) == date, "\(identifier ?? "") \(date)")
        #expect(
            CivilDate(start.addingTimeInterval(-1), in: calendar) == date.adding(days: -1),
            "\(identifier ?? "") \(date)"
        )
    }
}
