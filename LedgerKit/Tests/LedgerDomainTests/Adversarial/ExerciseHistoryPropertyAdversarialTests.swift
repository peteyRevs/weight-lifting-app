import Foundation
@testable import LedgerDomain
import Testing

// F12 S2 adversarial round 1 (G2): `ExerciseHistory.make`'s tags against `PersonalRecords` over random histories.
// Each history's records are judged one workout at a time against the bests before it, oldest first, as F05 stores
// them (decision #27); then PR must be exactly those workouts, "+Δ" the exact step between top working sets, and
// the fold's estimate and best set those of `PersonalRecords.Bests` over everything.

extension ExerciseHistoryAdversarialTests {
    /// A generated history: its sessions newest first, and which were deloads.
    struct Generated {
        var sessions: [ExerciseSession]
        var deloads: Set<WorkoutID>
    }

    static func generate(_ seed: PropertySeed) -> Generated {
        var random = seed.generator
        let kinds: [SetKind] = [.working, .working, .working, .added, .warmup, .drop]
        let count = Int.random(in: 1 ... 12, using: &random)
        // Distinct days, so "the one before" in time is the next in the list.
        let days = Array((1 ... 120).shuffled(using: &random).prefix(count)).sorted()
        var deloads: Set<WorkoutID> = []
        let sessions = days.enumerated().map { number, back in
            let date = Fixtures.now.addingTimeInterval(-Double(back) * 86400 + Double(number))
            let sets = (0 ..< Int.random(in: 1 ... 4, using: &random)).map { place in
                let quarters = Decimal(Int.random(in: 0 ... 100, using: &random)) * 2.5
                let weight: Weight = Bool
                    .random(using: &random) ? .pounds(95 + quarters) : .kilograms(40 + quarters / 2)
                return LoggedSet(
                    id: SetID(Fixtures.uuid(50000 + number * 20 + place)),
                    weight: weight,
                    reps: Reps(clamping: Int.random(in: 1 ... 15, using: &random)),
                    kind: kinds.randomElement(using: &random) ?? .working,
                    doneAt: date
                )
            }
            let session = ExerciseSession(
                workoutID: WorkoutID(Fixtures.uuid(6000 + number)),
                startedAt: date,
                sets: sets
            )
            if Int.random(in: 0 ..< 6, using: &random) == 0 {
                deloads.insert(session.workoutID)
            }
            return session
        }
        return Generated(sessions: sessions, deloads: deloads)
    }

    /// What F05 stores: each session's records judged against the bests of the sessions before it, oldest first;
    /// and the bests after all of them.
    static func detect(_ generated: Generated) throws -> (records: Set<WorkoutID>, bests: PersonalRecords.Bests) {
        var bests = PersonalRecords.Bests()
        var records: Set<WorkoutID> = []
        for session in generated.sessions.reversed() {
            let workout = try WorkoutState(
                id: session.workoutID, source: nil, name: "", tag: "",
                isDeload: generated.deloads.contains(session.workoutID),
                exercises: [Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: session.sets)],
                cursor: nil, startedAt: session.startedAt, phase: .finished, originDevice: Fixtures.deviceID
            )
            if !PersonalRecords.detect(workout: workout, against: bests, now: session.startedAt).isEmpty {
                records.insert(session.workoutID)
            }
            bests.include(workout)
        }
        return (records, bests)
    }

    static func topWorking(_ session: ExerciseSession) -> Weight? {
        session.sets.filter { $0.kind == .working }.map(\.weight).max()
    }

    /// The first broken property of `seed`'s history, or nil.
    static func violation(_ seed: PropertySeed) throws -> String? {
        let generated = generate(seed)
        let sessions = generated.sessions
        let (records, bests) = try detect(generated)
        let history = ExerciseHistory.make(
            sessions: sessions, records: records, now: Fixtures.now, calendar: weeks(.monday)
        )
        if history.e1RM != bests.e1RM[Fixtures.bench.id] {
            return "estimate \(history.e1RM as Any) against the bests' \(bests.e1RM[Fixtures.bench.id] as Any)"
        }
        let best = bests.bestSet(of: Fixtures.bench.id).map { BestSet(weight: $0.weight, reps: $0.reps) }
        if history.bestSet != best {
            return "best set \(history.bestSet as Any) against the bests' \(best as Any)"
        }
        for index in history.log.indices {
            if let broken = entryViolation(at: index, history, generated, records) {
                return broken
            }
        }
        if case .heavier = history.log.last?.tag {
            return "the oldest session has a step"
        }
        return nil
    }

    /// The first broken property of the log's entry at `index`, or nil.
    static func entryViolation(
        at index: Int,
        _ history: ExerciseHistory,
        _ generated: Generated,
        _ records: Set<WorkoutID>
    ) -> String? {
        let sessions = generated.sessions
        let (entry, session) = (history.log[index], sessions[index])
        let earlier = sessions.indices.contains(index + 1) ? topWorking(sessions[index + 1]) : nil
        let isRecord = records.contains(session.workoutID)
        if (entry.tag == .record) != isRecord {
            return "entry \(index): \(entry.tag), records \(isRecord)"
        }
        if case let .heavier(step) = entry.tag {
            guard let top = topWorking(session), let earlier, step == top - earlier, step > .zero else {
                return "entry \(index): \(entry.tag) is not the step from \(earlier as Any)"
            }
        }
        if entry.tag == .same, let top = topWorking(session), let earlier, top > earlier {
            return "entry \(index): — over a lighter session before"
        }
        // A session that raised the estimate over one already set is a record, unless it was a deload.
        let estimate = { (from: Int) in
            ExerciseHistory.make(
                sessions: Array(sessions[from...]), records: [], now: Fixtures.now, calendar: weeks(.monday)
            ).e1RM
        }
        let isDeload = generated.deloads.contains(session.workoutID)
        guard let before = estimate(index + 1), let through = estimate(index), through > before, !isDeload,
              entry.tag != .record
        else {
            return nil
        }
        return "entry \(index) raised the estimate \(before) → \(through) but is \(entry.tag)"
    }

    @Test(
        "Random histories: PR is exactly F05's records, +Δ the exact step, and the bests are PersonalRecords'",
        .tags(.property),
        arguments: Array(PropertySeed.all.prefix(200))
    )
    func tags_randomHistories_agreeWithPersonalRecords(_ seed: PropertySeed) throws {
        #expect(try Self.violation(seed) == nil, "\(seed)")
    }
}
