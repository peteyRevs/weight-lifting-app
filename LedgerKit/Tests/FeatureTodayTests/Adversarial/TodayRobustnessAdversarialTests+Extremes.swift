@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Numbers and dates at the ends of their types. Each test only asks that `make` returns a whole model; what it
/// shows for such an input is printed for the findings, not judged.
nonisolated extension TodayRobustnessAdversarialTests {
    static let weights: [String: Weight] = [
        "zero": .zero,
        "negative": Weight(grams: -100_000),
        "not a number": Weight(grams: .nan),
        "the largest decimal": Weight(grams: .greatestFiniteMagnitude),
        "the smallest decimal": Weight(grams: .leastNonzeroMagnitude),
        "2^53 + 1 pounds": .pounds(9_007_199_254_740_993)
    ]

    static let volumes: [String: Volume?] = [
        "none": nil,
        "zero": .zero,
        "a negative speck": Volume(gramReps: Decimal(sign: .minus, exponent: -100, significand: 1)),
        "a speck": Volume(gramReps: Decimal(sign: .plus, exponent: -100, significand: 1)),
        "not a number": Volume(gramReps: .nan),
        "the largest decimal": Volume(gramReps: .greatestFiniteMagnitude),
        "the most negative decimal": Volume(gramReps: -.greatestFiniteMagnitude)
    ]

    /// Whether the model is whole: seven days, two tiles with a value, and every text finished.
    static func isWhole(_ model: TodayModel) -> Bool {
        model.weekStrip.count == 7 && !model.stats.sessions.value.isEmpty && !model.stats.volume.value.isEmpty
            && !model.header.date.isEmpty
    }

    @Test(
        "Sets of any weight, against a previous week of any volume, give a whole model",
        arguments: weights.keys.sorted()
    )
    func setsOfAnyWeight_giveAModel(_ label: String) throws {
        let weight = try #require(Self.weights[label])
        let program = try Support.seed()
        let lowerA = try Support.day("LA", in: program)
        let source = WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: lowerA.id)
        let start = try Support.moment(Support.civil(2026, 9, 16), 6)
        let lifts = [Support.Lift(weight: weight, reps: 30), Support.Lift(weight: weight, reps: 1, isDone: false)]
        let done = try Support.lifted(number: 810, start: start, lifts: lifts, source: source)
        var live = done
        live.phase = .live
        live.endedAt = nil
        var shown: [String] = []
        for (name, previous) in Self.volumes.sorted(by: { $0.key < $1.key }) {
            for units in Units.allCases {
                let settings = Support.settings(units)
                let logged = try Support.input(
                    program,
                    now: Self.wednesday(),
                    settings: settings,
                    week: [done],
                    recent: [done],
                    previous: previous
                )
                let resumed = try Support.input(
                    program,
                    now: Self.wednesday(),
                    settings: settings,
                    previous: previous,
                    session: live
                )
                let models = [TodayPresentation.make(logged), TodayPresentation.make(resumed)]
                let areWhole = models.allSatisfy(Self.isWhole)
                #expect(areWhole, "\(label) after \(name) in \(units)")
                let tile = models[0].stats.volume
                shown.append("\(name)/\(units): \(tile.value)k \(tile.delta ?? "no change")")
            }
        }
        print("TodayRobustnessAdversarialTests sets of \(label): \(shown.joined(separator: "; "))")
    }

    /// Moments inside the years a `CivilDate` holds (0001 … 9999) and outside them.
    static let moments: [String: Date] = [
        "distantFuture": .distantFuture,
        "year 9892": Date(timeIntervalSince1970: 2.5e11),
        "year 1700": Date(timeIntervalSince1970: -8.5e9),
        "distantPast": .distantPast,
        "year −1199": Date(timeIntervalSince1970: -1e11),
        "year 10209": Date(timeIntervalSince1970: 2.6e11),
        "1e13 s": Date(timeIntervalSince1970: 1e13),
        "−1e13 s": Date(timeIntervalSince1970: -1e13),
        "1e15 s": Date(timeIntervalSince1970: 1e15),
        "1e17 s": Date(timeIntervalSince1970: 1e17),
        "the largest double": Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude),
        "infinity": Date(timeIntervalSinceReferenceDate: .infinity),
        "not a number": Date(timeIntervalSinceReferenceDate: .nan)
    ]
    static let representable = ["distantFuture", "year 9892", "year 1700"]

    @Test("A clock set to any moment gives a model: whole inside years 1 to 9999", arguments: moments.keys.sorted())
    func anyMoment_givesAModel(_ label: String) throws {
        let now = try #require(Self.moments[label])
        let stored = try Support.lifted(number: 820, start: Self.wednesday(), lifts: [.pounds(100, 10)])
        for program in try [Support.seed(), nil] {
            for zone in try [Support.utc, Support.zone("Pacific/Kiritimati"), Support.zone("Etc/GMT+12")] {
                let input = try Support.input(program, now: now, zone: zone, week: [stored], recent: [stored])
                let model = TodayPresentation.make(input)
                let days = model.weekStrip.count
                let isWhole = Self.isWhole(model) || (!Self.representable.contains(label) && days == 0)
                #expect(isWhole, "\(label) in \(zone.identifier): \(days) days in the strip")
                if zone == Support.utc, program != nil {
                    print("TodayRobustnessAdversarialTests now \(label): \(model.header.date) / \(Self.kind(model)) / "
                        + "\(days) days")
                }
            }
        }
    }

    @Test("The last and the first day a calendar date can name give a model", arguments: [
        [9999, 12, 31], [9999, 12, 27], [1, 1, 1], [1, 1, 7]
    ])
    func endsOfTheCalendar_giveAModel(_ date: [Int]) throws {
        let today = try Support.civil(date[0], date[1], date[2])
        var lines: [String] = []
        for start in try [today, #require(today.adding(days: date[0] == 1 ? 0 : -50)), Support.civil(2026, 9, 14)] {
            for weekStart in Weekday.allCases {
                let input = try Support.input(
                    Support.seed(start: start),
                    now: Support.moment(today, 23, 59, 59),
                    settings: Support.settings(weekStart: weekStart)
                )
                let model = TodayPresentation.make(input)
                lines.append("\(start)/\(weekStart): \(Self.kind(model)) \(model.weekStrip.count)")
                #expect(model.weekStrip.count <= 7)
            }
        }
        print("TodayRobustnessAdversarialTests on \(today): \(Set(lines).sorted().prefix(8))")
    }

    @Test("Workouts that start or end at any moment give a whole model", arguments: moments.keys.sorted())
    func workoutsAtAnyMoment_giveAModel(_ label: String) throws {
        let moment = try #require(Self.moments[label])
        let program = try Support.seed()
        var early = try Support.lifted(number: 830, start: moment, lifts: [.pounds(100, 10)])
        early.endedAt = try Self.wednesday()
        var late = try Support.lifted(
            number: 831,
            start: Self.wednesday().addingTimeInterval(-600),
            lifts: [.pounds(100, 10)]
        )
        late.endedAt = moment
        var open = late
        open.endedAt = nil
        var live = early
        live.phase = .live
        live.endedAt = nil
        for session in [nil, live, early, late] {
            let input = try Support.input(
                program,
                now: Self.wednesday(),
                week: [early, late, open],
                recent: [early, late, open],
                session: session
            )
            let model = TodayPresentation.make(input)
            let isWhole = Self.isWhole(model)
            #expect(isWhole, "\(label)")
            if session == nil {
                print("TodayRobustnessAdversarialTests workouts at \(label): \(model.recent.rows.map(\.meta))")
            }
        }
    }

    @Test("A workout built for a week no program holds gives a whole model", arguments: [
        Int.max, Int.min, -1, 8, 1_000_000
    ])
    func workoutOfAnImpossibleWeek_givesAModel(_ week: Int) throws {
        let program = try Support.seed()
        let lowerA = try Support.day("LA", in: program)
        let source = WorkoutSource(programID: program.id, weekIndex: week, dayTemplateID: lowerA.id)
        let start = try Support.moment(Support.civil(2026, 9, 16), 6)
        let done = try Support.lifted(number: 840, start: start, lifts: [.pounds(100, 10)], source: source)
        var live = done
        live.phase = .live
        live.endedAt = nil
        for day in [15, 16] {
            let now = try Support.moment(Support.civil(2026, 9, day), 20)
            for session in [nil, live, done] {
                let input = try Support.input(program, now: now, week: [done], recent: [done], session: session)
                let isWhole = Self.isWhole(TodayPresentation.make(input))
                #expect(isWhole, "week \(week) on 09-\(day)")
            }
        }
    }
}
