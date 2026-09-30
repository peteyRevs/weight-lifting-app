import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Random garbage never crashes the reducer and never breaks its structural invariants: arbitrary
/// indices, unknown IDs, negative and huge weights, odd durations and dates, snapshots with empty
/// exercises and wild cursors, envelopes from strangers.
@Suite("WorkoutEngine · garbage properties (adversarial)", .tags(.domain, .property))
struct GarbagePropertyAdversarialTests {
    static let indices = [-2, -1, 0, 1, 2, 3, 5, 7, Int.max, Int.min]
    static let grams = [
        "-1000",
        "-0.0000001",
        "0",
        "0.0000001",
        "45359.237",
        "83914.58845",
        "1e30",
        "123456789.123456789"
    ]
    static let seconds: [Int64] = [-300, -1, 0, 1, 30, 90, 86400, 31_536_000]

    static func garbageEvent(snapshot: WorkoutState, using generator: inout SeededGenerator) -> WorkoutEvent {
        let date = engineTime(Double(Int.random(in: -100_000 ... 100_000, using: &generator)))
        let amount = Duration.seconds(seconds.randomElement(using: &generator) ?? 30)
        switch Int.random(in: 0 ..< 13, using: &generator) {
        case 0: return .started(EngineGen.session(using: &generator, allowEmpty: true))
        case 1: return .exerciseSelected(
                exerciseIndex: indices.randomElement(using: &generator) ?? 0,
                setIndex: indices.randomElement(using: &generator) ?? 0
            )
        case 2 ... 7: return garbageRowEvent(snapshot: snapshot, at: date, using: &generator)
        case 8: return .restStarted(endsAt: date, total: amount)
        case 9: return .restExtended(amount: amount, extendsShownRest: generator.chance(50), tappedAt: date)
        case 10: return .restSkipped
        case 11: return .finished(endedAt: date)
        default: return .discarded(endedAt: date)
        }
    }

    static func garbageRowEvent(
        snapshot: WorkoutState,
        at date: Date,
        using generator: inout SeededGenerator
    ) -> WorkoutEvent {
        let rows = EngineGen.setIDs(of: snapshot).map(\.id)
        let known = generator.chance(60) ? rows.randomElement(using: &generator) : nil
        let setID = known ?? SetID(generator.uuid())
        let small = generator.chance(50) ? Int.random(in: 0 ..< 6, using: &generator) : nil
        let index = small ?? indices.randomElement(using: &generator) ?? 0
        let weight = Weight(grams: dec(grams.randomElement(using: &generator) ?? "0"))
        let reps = Reps(clamping: [Int.min, -5, 0, 1, 12, Int.max].randomElement(using: &generator) ?? 1)
        switch Int.random(in: 0 ..< 6, using: &generator) {
        case 0: return .setLogged(exerciseIndex: index, setID: setID, weight: weight, reps: reps, doneAt: date)
        case 1: return .setUnlogged(exerciseIndex: index, setID: setID)
        case 2: return .setTargetChanged(
                exerciseIndex: index, setID: setID, weight: weight, reps: generator.chance(50) ? reps : nil
            )
        case 3:
            let kind = SetKind.allCases.randomElement(using: &generator) ?? .added
            let set = LoggedSet(id: setID, weight: weight, reps: reps, kind: kind, doneAt: date)
            return .setAdded(exerciseIndex: index, set: set)
        case 4: return .allSetsRepeated(exerciseIndex: index, weight: weight, reps: reps)
        default: return .exerciseSwapped(
                exerciseIndex: index, exerciseID: ExerciseID(generator.uuid()), name: "", alsoUpdateProgram: true
            )
        }
    }

    /// A snapshot (possibly with empty exercises and a wild cursor) and 1–60 garbage envelopes from
    /// four devices, one of them a stranger to the workout.
    static func garbageLog(_ seed: PropertySeed) -> (snapshot: WorkoutState, log: [EventEnvelope]) {
        var generator = seed.generator
        var snapshot = EngineGen.session(using: &generator, allowEmpty: true)
        if generator.chance(30) {
            snapshot.cursor = Cursor(exerciseIndex: indices.randomElement(using: &generator) ?? 0, setIndex: -1)
        }
        let devices = [EngineAdv.phone, EngineAdv.watch, EngineAdv.tablet, DeviceID(generator.uuid())]
        var log = [EngineAdv.start(snapshot, EngineAdv.phone, seq: 1, at: 0)]
        for _ in 0 ..< Int.random(in: 1 ... 60, using: &generator) {
            let event = garbageEvent(snapshot: snapshot, using: &generator)
            let workout = generator.chance(10) ? WorkoutID(generator.uuid()) : EngineAdv.workoutID
            log.append(EventEnvelope(
                event: event, workoutID: workout, device: devices.randomElement(using: &generator) ?? EngineAdv.phone,
                seq: UInt64.random(in: 1 ... 40, using: &generator),
                wallClock: engineTime(Double(Int.random(in: -50 ... 500, using: &generator)))
            ))
        }
        return (snapshot, log)
    }
}

// MARK: - Properties

extension GarbagePropertyAdversarialTests {
    @Test("Garbage never traps reduce or replay, and replay stays order-invariant on it.", arguments: PropertySeed.all)
    func garbage_neverTraps(seed: PropertySeed) {
        var (_, log) = Self.garbageLog(seed)
        var generator = seed.generator
        // Keys must name one envelope (EngineError.conflictingEnvelope): keep the first per key.
        var seen = Set<EnvelopeKey>()
        log = log.filter { seen.insert($0.key).inserted }
        let replayed = WorkoutEngine.replay(log)
        _ = EngineAdv.fold(log.shuffled(using: &generator))
        #expect(WorkoutEngine.replay(log.shuffled(using: &generator)) == replayed)
    }

    @Test(
        "Garbage keeps the structure: exercises fixed, rows only grow, IDs unique, weights ≥ 0, terminals stick.",
        arguments: PropertySeed.all
    )
    func garbage_keepsInvariants(seed: PropertySeed) {
        let (snapshot, log) = Self.garbageLog(seed)
        var state: WorkoutState?
        for envelope in log {
            let previous = state
            state = WorkoutEngine.reduce(state, envelope).0
            guard let current = state else {
                continue
            }
            #expect(current.exercises.count == snapshot.exercises.count)
            #expect(current.exercises.map(\.id) == snapshot.exercises.map(\.id))
            if let previous {
                #expect(zip(previous.exercises, current.exercises).allSatisfy { $0.sets.count <= $1.sets.count })
                if previous.phase != .live {
                    #expect(current == previous, "a \(previous.phase) workout changed on \(envelope.event)")
                }
            }
            let ids = current.exercises.flatMap(\.sets).map(\.id)
            #expect(Set(ids).count == ids.count, "duplicate set IDs after \(envelope.event)")
            #expect(
                current.exercises.flatMap(\.sets).allSatisfy { $0.weight >= .zero },
                "negative weight after \(envelope.event)"
            )
        }
    }

    @Test(
        "Criterion 10 on garbage (incl. invalid starteds): WorkoutEngine.replay agrees with ModelOracle.replay.",
        arguments: PropertySeed.all
    )
    func garbage_replayMatchesOracle(seed: PropertySeed) {
        var (snapshot, log) = Self.garbageLog(seed)
        var generator = SeededGenerator(seed: seed.value ^ 0x5EED)
        if generator.chance(50) {
            // An unusable started (not live, or for another workout) that sorts before the real one.
            var ended = snapshot
            ended.phase = generator.chance(50) ? .finished : .discarded
            let other = EventBuilders.session(EventBuilders.seedExercises, id: WorkoutID(generator.uuid()))
            let bogus: WorkoutEvent = generator.chance(50) ? .started(ended) : .started(other)
            log.append(EngineAdv.env(bogus, EngineAdv.tablet, seq: 999, at: -100))
        }
        var seen = Set<EnvelopeKey>()
        log = log.filter { seen.insert($0.key).inserted }
        #expect(WorkoutEngine.replay(log) == ModelOracle.replay(log))
    }

    @Test(
        "Garbage never leaves the cursor on a missing row once it has pointed at a real one.",
        arguments: PropertySeed.all
    )
    func garbage_cursorStaysReal(seed: PropertySeed) {
        let (_, log) = Self.garbageLog(seed)
        var state: WorkoutState?
        var wasReal = false
        for envelope in log {
            state = WorkoutEngine.reduce(state, envelope).0
            guard let current = state, let cursor = current.cursor else {
                continue
            }
            let isReal = EngineAdv.row(current, cursor.exerciseIndex, cursor.setIndex) != nil
            if wasReal {
                #expect(isReal, "cursor \(cursor) points at no row after \(envelope.event)")
            }
            wasReal = wasReal || isReal
        }
    }
}
