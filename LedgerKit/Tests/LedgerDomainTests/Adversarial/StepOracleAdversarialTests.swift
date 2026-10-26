import Foundation
@testable import LedgerDomain
import Testing

// F12 S3 adversarial round (G2), N19: the "+Δ" tag against an oracle written apart from the code, quadratic and
// literal, over histories the S2 generator never makes: sets not done, sessions with no set at all, sessions of
// warm-ups or drop sets alone, runs of them, equal top weights written in two units (100 lb is exactly
// 45.359237 kg), and records given at random (a record wins over a step and still carries its weight forward).

@Suite("Adversarial F12 S3 · the +step oracle", .tags(.domain))
struct StepOracleAdversarialTests {
    typealias Tag = ExerciseHistory.Tag

    /// Weights that collide across units: each pair is one mass.
    static let weights: [Weight] = [
        .pounds(100), .kilograms(Decimal(string: "45.359237") ?? 0),
        .pounds(135), .kilograms(60), .kilograms(Decimal(string: "61.2349699") ?? 0), .pounds(140), .pounds(225),
        .kilograms(100), .zero
    ]

    static func generate(_ seed: PropertySeed) -> (sessions: [ExerciseSession], records: Set<WorkoutID>) {
        var random = seed.generator
        let kinds: [SetKind] = [.working, .added, .warmup, .drop]
        let count = Int.random(in: 1 ... 14, using: &random)
        let days = Array((1 ... 200).shuffled(using: &random).prefix(count)).sorted()
        var records: Set<WorkoutID> = []
        let sessions = days.enumerated().map { number, back in
            let date = Fixtures.now.addingTimeInterval(-Double(back) * 86400)
            // A session that is all warm-ups, all drops, or mixed; sometimes no set at all.
            let only: SetKind? = Int.random(in: 0 ..< 3, using: &random) == 0 ? kinds
                .randomElement(using: &random) : nil
            let sets = (0 ..< Int.random(in: 0 ... 4, using: &random)).map { place in
                LoggedSet(
                    id: SetID(Fixtures.uuid(70000 + number * 20 + place)),
                    weight: weights.randomElement(using: &random) ?? .zero,
                    reps: Reps(clamping: Int.random(in: 1 ... 12, using: &random)),
                    kind: only ?? kinds.randomElement(using: &random) ?? .working,
                    doneAt: Int.random(in: 0 ..< 4, using: &random) == 0 ? nil : date
                )
            }
            let id = WorkoutID(Fixtures.uuid(9000 + number))
            if Int.random(in: 0 ..< 5, using: &random) == 0 {
                records.insert(id)
            }
            return ExerciseSession(workoutID: id, startedAt: date, sets: sets)
        }
        return (sessions, records)
    }

    /// The rule as the amendment words it, read literally, apart from the code.
    static func expectedTag(at index: Int, of sessions: [ExerciseSession], records: Set<WorkoutID>) -> Tag {
        func top(_ session: ExerciseSession) -> Weight? {
            var best: Weight?
            for set in session.sets where set.doneAt != nil && [.working, .added].contains(set.kind) {
                if set.weight.grams > (best?.grams ?? -1) {
                    best = set.weight
                }
            }
            return best
        }
        if records.contains(sessions[index].workoutID) {
            return .record
        }
        guard let mine = top(sessions[index]) else {
            return .same
        }
        var later = index + 1
        while later < sessions.count {
            if let theirs = top(sessions[later]) {
                return mine.grams > theirs.grams ? .heavier(Weight(grams: mine.grams - theirs.grams)) : .same
            }
            later += 1
        }
        return .same
    }

    @Test("N19: every entry's tag is the oracle's", .tags(.property), arguments: Array(PropertySeed.all.prefix(300)))
    func tags_matchTheOracle(_ seed: PropertySeed) {
        let (sessions, records) = Self.generate(seed)
        let history = ExerciseHistory.make(
            sessions: sessions, records: records, now: Fixtures.now,
            calendar: WeekCalendar(startDate: .unixEpoch, weekStart: .monday, calendar: Fixtures.calendar)
        )
        let expected = sessions.indices.map { Self.expectedTag(at: $0, of: sessions, records: records) }
        let found = history.log.map(\.tag)
        let agrees = found == expected
        #expect(agrees, "\(seed): \(found) against \(expected)")
    }

    @Test("N19 pin: an equal mass in the other unit is no step, and a lighter one is no step")
    func equalMassAcrossUnits_isSame() {
        let history = ExerciseHistory.make(
            sessions: [
                ExerciseHistoryAdversarialTests.session(3, on: Fixtures.now, weights: [.pounds(100)]),
                ExerciseHistoryAdversarialTests.session(
                    2, on: Fixtures.now - 86400, weights: [.kilograms(Decimal(string: "45.359237") ?? 0)]
                ),
                ExerciseHistoryAdversarialTests.session(1, on: Fixtures.now - 2 * 86400, weights: [.pounds(120)])
            ],
            records: [], now: Fixtures.now,
            calendar: WeekCalendar(startDate: .unixEpoch, weekStart: .monday, calendar: Fixtures.calendar)
        )
        #expect(history.log.map(\.tag) == [.same, .same, .same])
    }

    @Test("N19 pin: undone working sets count for nothing; the step reaches past a session of them")
    func undoneSets_arePassedOver() {
        let undone = ExerciseSession(
            workoutID: WorkoutID(Fixtures.uuid(9502)),
            startedAt: Fixtures.now - 86400,
            sets: [LoggedSet(
                id: SetID(Fixtures.uuid(9512)),
                weight: .pounds(300),
                reps: Reps(clamping: 5),
                kind: .working
            )]
        )
        let history = ExerciseHistory.make(
            sessions: [
                ExerciseHistoryAdversarialTests.session(3, on: Fixtures.now, weights: [.pounds(145)]),
                undone,
                ExerciseHistoryAdversarialTests.session(1, on: Fixtures.now - 2 * 86400, weights: [.pounds(135)])
            ],
            records: [], now: Fixtures.now,
            calendar: WeekCalendar(startDate: .unixEpoch, weekStart: .monday, calendar: Fixtures.calendar)
        )
        #expect(history.log.map(\.tag) == [.heavier(.pounds(10)), .same, .same])
    }
}
