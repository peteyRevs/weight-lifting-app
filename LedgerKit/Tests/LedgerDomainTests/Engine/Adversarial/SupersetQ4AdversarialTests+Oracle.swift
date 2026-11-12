import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S9: seeded scripts of every edit on a 3-member block of unequal counts with a drop row, auto rest
/// on and off, checked event by event against `ModelOracle` (its Q4 rule included).
extension SupersetQ4AdversarialTests {
    /// One seeded event on `rows`: an un-log, "+30s", a skip, an added set (whose row joins `rows`) or a log.
    static func randomEvent(
        _ generator: inout SeededGenerator,
        rows: inout [(Int, SetID)],
        step: Int,
        seed: UInt64
    ) -> WorkoutEvent {
        let (exercise, setID) = rows[Int.random(in: 0 ..< rows.count, using: &generator)]
        let seconds = Double(10 * (step + 1)) + Double(Int.random(in: 0 ..< 200, using: &generator))
        switch Int.random(in: 0 ..< 8, using: &generator) {
        case 0:
            return .setUnlogged(exerciseIndex: exercise, setID: setID)
        case 1:
            return Engine.extend(tapped: seconds)
        case 2:
            return .restSkipped
        case 3:
            let id = SetID(EventBuilders.uuid(0xA000 + Int(seed) * 64 + step))
            rows.append((exercise, id))
            return .setAdded(exerciseIndex: exercise, set: LoggedSet(
                id: id, weight: .pounds(50), reps: Reps(clamping: 8), kind: .added
            ))
        default:
            return .setLogged(
                exerciseIndex: exercise, setID: setID, weight: .pounds(50), reps: Reps(clamping: 8),
                doneAt: Engine.at(seconds)
            )
        }
    }

    @Test(
        "Seeded scripts on a 3-member block with a drop row, added sets and re-logs: rest and cursor are the oracle's",
        arguments: [true, false]
    )
    func seeded_threeMembers_matchTheOracle(autoRest: Bool) {
        var session = Self.three
        session.autoRest = autoRest
        session.exercises[2].sets.append(LoggedSet(
            id: .derived(from: session.exercises[2].id, index: 2), weight: .pounds(15), reps: Reps(clamping: 12),
            kind: .drop
        ))
        for seed in UInt64(1) ... 60 {
            var generator = SeededGenerator(seed: seed &* 31 &+ (autoRest ? 0 : 1000))
            var events: [WorkoutEvent] = []
            var rows: [(Int, SetID)] = session.exercises.indices.flatMap { exercise in
                session.exercises[exercise].sets.map { (exercise, $0.id) }
            }
            for step in 0 ..< 18 {
                events.append(Self.randomEvent(&generator, rows: &rows, step: step, seed: seed))
                let log = [Engine.started(session)]
                    + EventBuilders.log(from: events, firstSeq: 2, startingAt: Engine.at(10))
                let engine = Engine.fold(log)
                var oracle = ModelOracle()
                log.forEach { oracle.apply($0) }
                let restAgrees = engine?.rest == oracle.state?.rest
                let cursorAgrees = engine?.cursor == oracle.state?.cursor
                #expect(restAgrees, "autoRest \(autoRest), seed \(seed), step \(step)")
                #expect(cursorAgrees, "autoRest \(autoRest), seed \(seed), step \(step)")
            }
        }
    }
}
