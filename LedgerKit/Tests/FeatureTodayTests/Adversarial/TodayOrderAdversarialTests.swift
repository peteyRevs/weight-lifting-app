@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2, round 2: criterion 13. "`make` gives the same model for `weekWorkouts` handed in any order:
/// of several finished workouts of today's session the Logged card shows the one that started last, and two
/// that started at the same instant are told apart the same way every time."
@Suite("Adversarial F09 S3 round 2 · the order of the week's workouts", .tags(.feature))
nonisolated struct TodayOrderAdversarialTests {
    typealias Support = TodayAdversarial

    /// Every order of `items`: n! of them, so the tests keep n at five or fewer.
    static func orders<Item>(of items: [Item]) -> [[Item]] {
        guard items.count > 1 else {
            return [items]
        }
        return items.indices.flatMap { index -> [[Item]] in
            var rest = items
            let first = rest.remove(at: index)
            return orders(of: rest).map { [first] + $0 }
        }
    }

    /// How many of `orders` of `input`'s week give another model than the order it came in.
    static func ordersThatDiffer(_ input: TodayInput, among orders: [[WorkoutState]]) -> Int {
        let reference = TodayPresentation.make(input)
        var copy = input
        return orders.count { order in
            copy.weekWorkouts = order
            return TodayPresentation.make(copy) != reference
        }
    }

    /// 1,000 seeds in two batches.
    static let batches: [ClosedRange<UInt64>] = [0 ... 499, 500 ... 999]

    @Test("Seeded inputs give one model in every order of the week's workouts", arguments: batches)
    func everyOrder_givesTheSameModel(_ seeds: ClosedRange<UInt64>) throws {
        let catalog = try Support.exercises()
        var lines: [String] = []
        var count = 0
        for seed in seeds {
            let scenario = try TodayScenario(seed: seed, catalog: catalog, asGenerated: true)
            // Every order of up to four workouts; of five, every fifth of the 120, the reverse among them.
            let all = Self.orders(of: scenario.input.weekWorkouts)
            let orders = all.count > 24 ? stride(from: 4, to: all.count, by: 5).map { all[$0] } : all
            count += orders.count
            let different = Self.ordersThatDiffer(scenario.input, among: orders)
            if different > 0 {
                lines.append("seed \(seed) [\(scenario.note)]: \(different) orders give another model")
            }
        }
        let holds = lines.isEmpty
        #expect(holds, "\(lines.count) of \(seeds.count) seeds:\n\(lines.prefix(5).joined(separator: "\n"))")
        print("TodayOrderAdversarialTests seeds \(seeds): \(count) orders")
    }

    /// Two to five finished workouts of today's session (Lower A, Wednesday 2026-09-16) that started at 06:00
    /// or at 09:00, so several often share the latest start; each with its own id, length and volume. One time
    /// in three the session's own workout is one of them, and one time in three a further one history lacks.
    static func tied(seed: UInt64) throws -> TodayInput {
        var random = AdversarialRandom(seed: seed)
        let program = try Support.seed()
        let lowerA = try Support.day("LA", in: program)
        let source = WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: lowerA.id)
        let starts = try [6, 9].map { try Support.moment(Support.civil(2026, 9, 16), $0) }
        var workouts: [WorkoutState] = []
        for number in 0 ..< Int.random(in: 2 ... 5, using: &random) {
            try workouts.append(Support.lifted(
                number: 40 + Int.random(in: 0 ..< 1000, using: &random) * 10 + number,
                start: starts[Int.random(in: 0 ..< 2, using: &random)],
                seconds: 600 + 61 * number,
                lifts: [.pounds(100, 1 + number)],
                source: source
            ))
        }
        var session: WorkoutState?
        switch Int.random(in: 0 ..< 3, using: &random) {
        case 0: session = workouts.randomElement(using: &random)
        case 1: session = try Support.lifted(
                number: 7,
                start: starts[1],
                seconds: 99,
                lifts: [.pounds(7, 7)],
                source: source
            )
        default: break
        }
        let now = try Support.moment(Support.civil(2026, 9, 16), 12)
        return try Support.input(program, now: now, week: workouts, recent: [], session: session)
    }

    @Test("Workouts that share a start are told apart the same way in every order", arguments: [UInt64(0) ... 299])
    func sameStart_isToldApartTheSameWayInEveryOrder(_ seeds: ClosedRange<UInt64>) throws {
        var lines: [String] = []
        for seed in seeds {
            let input = try Self.tied(seed: seed)
            let different = Self.ordersThatDiffer(input, among: Self.orders(of: input.weekWorkouts))
            let card = try Support.logged(TodayPresentation.make(input))
            let finished = TodayOracle.finished(input)
            let latest = finished.map(\.startedAt).max()
            let newest = finished.filter { $0.startedAt == latest }.map { TodayRoute.openWorkout($0.id) }
            let showsNewest = newest.contains(card.action.route)
            if different > 0 || !showsNewest {
                lines.append("seed \(seed): \(different) orders differ; shows one of the newest: \(showsNewest)")
            }
        }
        let holds = lines.isEmpty
        #expect(holds, "\(lines.count) of \(seeds.count) seeds:\n\(lines.prefix(5).joined(separator: "\n"))")
    }

    @Test("Two workouts with one start: the card is one of them, the same one whichever comes first")
    func twoWithOneStart_showTheSameOneEitherWay() throws {
        let program = try Support.seed()
        let start = try Support.moment(Support.civil(2026, 9, 16), 9)
        let first = try Support.finished(
            Support.live(program, week: 0, tag: "LA", number: 21, start: start),
            after: 600
        )
        let second = try Support.finished(
            Support.live(program, week: 0, tag: "LA", number: 22, start: start),
            after: 1462
        )
        let now = try Support.moment(Support.civil(2026, 9, 16), 12)
        let forwards = try Support.logged(TodayPresentation.make(Support.input(
            program,
            now: now,
            week: [first, second]
        )))
        let backwards = try Support.logged(TodayPresentation.make(Support.input(
            program,
            now: now,
            week: [second, first]
        )))
        #expect(forwards.action.route == backwards.action.route)
        #expect(forwards.elapsed == backwards.elapsed)
        #expect([.openWorkout(first.id), .openWorkout(second.id)].contains(forwards.action.route))
        // The session's own workout, a third with the same start that history does not hold yet.
        let own = try Support.finished(Support.live(program, week: 0, tag: "LA", number: 20, start: start), after: 99)
        let withOwn = try [[first, second], [second, first]].map { week in
            try Support.logged(TodayPresentation.make(Support.input(program, now: now, week: week, session: own)))
        }
        #expect(withOwn[0].action.route == withOwn[1].action.route)
        #expect(withOwn[0].elapsed == withOwn[1].elapsed)
        let shown = "ids 21 and 22 show \(forwards.elapsed); with the session's (20) \(withOwn[0].elapsed)"
        print("TodayOrderAdversarialTests one start: \(shown)")
    }

    @Test("History's older copy of the session's workout and another workout: one model in either order")
    func staleCopyOfTheSession_givesOneModel() throws {
        let program = try Support.seed()
        let now = try Support.moment(Support.civil(2026, 9, 16), 12)
        let live = try Support.live(program, week: 0, tag: "LA", number: 31, start: now.addingTimeInterval(-3000))
        let stale = Support.finished(live, after: 1000, done: 9)
        let own = Support.finished(live, after: 1462)
        let earlier = try Support.finished(
            Support.live(program, week: 0, tag: "LA", number: 32, start: now.addingTimeInterval(-9000)),
            after: 600
        )
        let models = try [[stale, earlier], [earlier, stale]].map { week in
            try TodayPresentation.make(Support.input(
                program,
                now: now,
                week: week,
                recent: [stale, earlier],
                session: own
            ))
        }
        let isSame = models[0] == models[1]
        #expect(isSame)
        #expect(try Support.logged(models[0]).action.route == .openWorkout(own.id))
        #expect(models[0].stats.sessions.value == "2")
        try print("TodayOrderAdversarialTests stale copy: the card reads \(Support.logged(models[0]).stats)")
    }
}
