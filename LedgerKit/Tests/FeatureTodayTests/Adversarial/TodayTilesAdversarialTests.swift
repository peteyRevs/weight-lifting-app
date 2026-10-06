@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: the strip, the tiles and the card tell one story (S3 criteria 2, 5 and 8). Sessions against
/// the strip's done marks, the volume against the tester's own exact sum in both units, the change against the
/// previous week on both sides of every rounding tie, and the Logged card's numbers against its workout.
@Suite("Adversarial F09 S3 · the strip, the tiles and the card agree", .tags(.feature))
nonisolated struct TodayTilesAdversarialTests {
    typealias Support = TodayAdversarial

    static func wednesday() throws -> Date {
        try Support.moment(Support.civil(2026, 9, 16), 20)
    }

    @Test("Five workouts in a week of four sessions read 5/4: two on one day are two sessions and one mark")
    func fiveWorkoutsInAWeekOfFour_readFiveOfFour() throws {
        let starts = try [(14, 6), (14, 18), (15, 7), (16, 7), (13, 9), (21, 9)].map { day, hour in
            try Support.moment(Support.civil(2026, 9, day), hour)
        }
        let workouts = try starts.enumerated().map { index, start in
            try Support.lifted(number: 30 + index, start: start, lifts: [.pounds(100, 10)])
        }
        let input = try Support.input(Support.seed(), now: Self.wednesday(), week: workouts)
        let model = TodayPresentation.make(input)
        // Sunday 09-13 and Monday 09-21 are outside the strip, so four of the six count; Tuesday's is off-schedule.
        #expect(model.stats.sessions.value == "4")
        #expect(model.stats.sessions.unit == "/4")
        #expect(model.weekStrip.count { $0.mark == .done } == 3)
        #expect(model.stats.volume.value == "4.0")
        let extra = try Support.lifted(number: 40, start: Support.moment(Support.civil(2026, 9, 16), 9), lifts: [])
        let more = try Support.input(Support.seed(), now: Self.wednesday(), week: workouts + [extra])
        let stats = TodayPresentation.make(more).stats
        #expect(stats.sessions.value == "5")
        #expect(stats.sessions.unit == "/4")
        #expect(stats.sessions.accessibilitySummary == "5 of 4 sessions this week")
        #expect(stats.volume.value == "4.0")
    }

    /// A week's volume to the pound, as one workout of one set, and the thousands the tile shows for it.
    struct Thousands: Sendable {
        let pounds: Decimal
        let lb: String
        let kg: String

        init(_ pounds: Decimal, _ lb: String, _ kg: String) {
            self.pounds = pounds
            self.lb = lb
            self.kg = kg
        }
    }

    static let volumes = [
        // 24,150 lb is a tie at one decimal (241.5 hundreds → 242); 10,954.26 kg → 109.5 → 110.
        Thousands(24150, "24.2", "11.0"),
        Thousands(24050, "24.1", "10.9"),
        Thousands(50, "0.1", "0.0"),
        Thousands(40, "0.0", "0.0"),
        Thousands(150, "0.2", "0.1"),
        // 999,950 lb rounds up into a new thousand: 9,999.5 hundreds → 10,000. In kilograms 453,569.69.
        Thousands(999_950, "1,000.0", "453.6"),
        Thousands(123_456_789, "123,456.8", "55,999.1")
    ]

    @Test("The volume tile rounds the week's exact sum once, half away from zero, in either unit", arguments: 0 ..< 7)
    func volumeTile_roundsTheExactSumOnce(_ index: Int) throws {
        let row = Self.volumes[index]
        let start = try Support.moment(Support.civil(2026, 9, 15), 7)
        let workout = try Support.lifted(
            number: 50,
            start: start,
            lifts: [Support.Lift(weight: .pounds(row.pounds), reps: 1)]
        )
        for units in Units.allCases {
            let input = try Support.input(
                Support.seed(),
                now: Self.wednesday(),
                settings: Support.settings(units),
                week: [workout]
            )
            let tile = TodayPresentation.make(input).stats.volume
            #expect(tile.value == (units == .lb ? row.lb : row.kg), "\(row.pounds) lb in \(units)")
            #expect(tile.unit == "k")
        }
    }

    @Test("The volume tile is the tester's own sum of the week's done sets, for seeded weeks", arguments: [
        UInt64(1) ... 400
    ])
    func volumeTile_isTheSumOfTheWeeksDoneSets(_ seeds: ClosedRange<UInt64>) throws {
        var lines: [String] = []
        for seed in seeds {
            var random = AdversarialRandom(seed: seed)
            let units: Units = Bool.random(using: &random) ? .lb : .kg
            var grams = Decimal(0)
            var workouts: [WorkoutState] = []
            for number in 0 ..< Int.random(in: 1 ... 6, using: &random) {
                let lifts = (0 ..< Int.random(in: 1 ... 8, using: &random)).map { _ in
                    let eighths = Decimal(Int.random(in: 0 ... 4000, using: &random)) / 8
                    let weight: Weight = Bool.random(using: &random) ? .pounds(eighths) : .kilograms(eighths)
                    let kind = SetKind.allCases.randomElement(using: &random) ?? .working
                    let isDone = Int.random(in: 0 ..< 4, using: &random) != 0
                    return Support.Lift(
                        weight: weight,
                        reps: Int.random(in: 1 ... 30, using: &random),
                        isDone: isDone,
                        kind: kind
                    )
                }
                grams += lifts.filter(\.isDone).reduce(Decimal(0)) { $0 + $1.weight.grams * Decimal($1.reps) }
                let start = try Support.moment(Support.civil(2026, 9, 14 + number % 3), 6 + number)
                try workouts.append(Support.lifted(number: 60 + number, start: start, lifts: lifts))
            }
            let input = try Support.input(
                Support.seed(),
                now: Self.wednesday(),
                settings: Support.settings(units),
                week: workouts
            )
            let tile = TodayPresentation.make(input).stats.volume
            let sum = Volume(gramReps: grams)
            if tile.value != sum.thousands(in: units) || !tile.accessibilitySummary.contains(sum.formatted(in: units)) {
                lines
                    .append(
                        "seed \(seed): \(tile.value) \"\(tile.accessibilitySummary)\", sum \(sum.formatted(in: units))"
                    )
            }
        }
        let agrees = lines.isEmpty
        #expect(agrees, "\(lines.count) seeds disagree:\n\(lines.prefix(5).joined(separator: "\n"))")
    }
}

// MARK: - The change against the previous week

nonisolated extension TodayTilesAdversarialTests {
    /// This week's and the previous week's pounds, and the change the tile shows.
    struct Change: Sendable {
        let this: Decimal
        let previous: Decimal?
        let delta: String?

        init(_ this: Decimal, _ previous: Decimal?, _ delta: String?) {
            self.this = this
            self.previous = previous
            self.delta = delta
        }
    }

    static let changes = [
        Change(24180, 22400, "+8%"),
        Change(21728, 22400, "\u{2212}3%"),
        Change(22400, 22400, "0%"),
        Change(22400, nil, nil),
        Change(22400, 0, nil),
        // +0.5 % and −0.5 % are ties: half away from zero. 0.49 % rounds to nothing.
        Change(20100, 20000, "+1%"),
        Change(19900, 20000, "\u{2212}1%"),
        Change(20098, 20000, "0%"),
        Change(19902, 20000, "0%"),
        Change(40000, 20000, "+100%"),
        Change(0, 20000, "\u{2212}100%"),
        Change(20000, 1, "+1999900%")
    ]

    @Test("The change against last week reads +, a real minus, 0%, or nothing", arguments: 0 ..< 12)
    func change_readsPlusMinusZeroOrNothing(_ index: Int) throws {
        let row = Self.changes[index]
        let start = try Support.moment(Support.civil(2026, 9, 15), 7)
        let workout = try Support.lifted(
            number: 70,
            start: start,
            lifts: [Support.Lift(weight: .pounds(row.this), reps: 1)]
        )
        let previous = row.previous.map { Volume(weight: .pounds($0), reps: .one) }
        for units in Units.allCases {
            let input = try Support.input(
                Support.seed(),
                now: Self.wednesday(),
                settings: Support.settings(units),
                week: [workout],
                previous: previous
            )
            let tile = TodayPresentation.make(input).stats.volume
            #expect(
                tile.delta?.replacingOccurrences(of: ",", with: "") == row.delta,
                "\(row.this) after \(row.previous ?? -1)"
            )
        }
    }
}
