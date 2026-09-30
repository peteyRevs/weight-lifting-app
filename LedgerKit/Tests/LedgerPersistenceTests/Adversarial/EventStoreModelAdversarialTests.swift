import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 1: `GRDBWorkoutEventStore` against a dictionary model of the protocol's doc
/// comments, over random interleavings of appends (duplicates, rivals, seqs across 2^63) and compactions.
@Suite("Adversarial S1 · event store against a model", .tags(.persistence), .timeLimit(.minutes(1)))
struct EventStoreModelAdversarialTests {
    typealias Contract = WorkoutEventStoreContract

    static let workouts = (0 ..< 3).map { WorkoutID(EventBuilders.uuid(0xF300 + $0)) }
    static let devices = [EventBuilders.phone, EventBuilders.watch]
    static let seqs: [UInt64] = [1, 2, 3, UInt64(Int64.max), 1 << 63, .max]

    @Test(
        "Random appends and compactions: every result, log, highestSeq and listing matches the model",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func randomOperations_matchTheModel(_ seed: PropertySeed) async throws {
        var random = seed.generator
        let store = try GRDBWorkoutEventStore(LedgerDatabase.inMemory(), now: { EventBuilders.start })
        var model = StoreModel()
        for step in 0 ..< 25 {
            if Int.random(in: 0 ..< 6, using: &random) == 0 {
                let workout = Self.workouts.randomElement(using: &random) ?? Contract.workout
                try await store.compact(workout: workout)
                model.logs[workout] = nil
            } else {
                let batch = (0 ..< Int.random(in: 0 ... 5, using: &random)).map { _ in Self.envelope(using: &random) }
                let expected = model.append(batch)
                do {
                    let fresh = try await store.append(batch)
                    #expect(.success(fresh) == expected, "\(seed), step \(step)")
                } catch let error as EngineError {
                    #expect(expected == .failure(error), "\(seed), step \(step)")
                }
            }
            try await Self.expectSameObservables(store, model, "\(seed), step \(step)")
        }
    }

    @Test(
        "Every event kind, with random weights, reps, durations and names, reads back == and re-appends as a no-op",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func everyEventKind_readsBackEqual(_ seed: PropertySeed) async throws {
        var random = seed.generator
        let log = (1 ... 12).map { seq in
            EventBuilders.envelope(
                Self.event(using: &random), device: EventBuilders.watch, seq: UInt64(seq),
                at: Contract.at(Double.random(in: -1e6 ... 1e6, using: &random))
            )
        }
        let store = try GRDBWorkoutEventStore(LedgerDatabase.inMemory(), now: { EventBuilders.start })
        #expect(try await store.append(log) == log)
        #expect(try await store.append(log).isEmpty)
        #expect(try await store.envelopes(for: Contract.workout) == log)
    }

    /// A random event of any kind, with extreme but valid field values.
    static func event(using random: inout SeededGenerator) -> WorkoutEvent {
        let fields = RandomFields(using: &random)
        return RandomFields.makers[Int.random(in: 0 ..< RandomFields.makers.count, using: &random)](fields)
    }

    /// A `restSkipped` with a random key; one in six carries the rival stamp.
    static func envelope(using random: inout SeededGenerator) -> EventEnvelope {
        let seq = seqs.randomElement(using: &random) ?? 1
        return Contract.skip(
            seq,
            devices.randomElement(using: &random) ?? EventBuilders.phone,
            in: workouts.randomElement(using: &random) ?? Contract.workout,
            at: Int.random(in: 0 ..< 6, using: &random) == 0 ? 1.5 : 1
        )
    }

    static func expectSameObservables(
        _ store: GRDBWorkoutEventStore,
        _ model: StoreModel,
        _ context: String
    ) async throws {
        #expect(try await Set(store.uncompactedWorkoutIDs()) == Set(model.logs.keys), "\(context)")
        #expect(try await store.uncompactedWorkoutIDs().count == model.logs.count, "\(context): listed twice")
        for workout in workouts {
            let log = try await store.envelopes(for: workout)
            #expect(log.count == Set(log).count && Set(log) == model.envelopes(for: workout), "\(context)")
            for device in devices {
                let highest = try await store.highestSeq(for: workout, device: device)
                #expect(highest == model.highestSeq(for: workout, device: device), "\(context)")
            }
        }
    }
}

/// The protocol's doc comments as a dictionary: a batch is all or nothing, a stored key with an equal
/// envelope is skipped, and a different one is a conflict.
struct StoreModel {
    var logs: [WorkoutID: [EnvelopeKey: EventEnvelope]] = [:]

    mutating func append(_ batch: [EventEnvelope]) -> Result<[EventEnvelope], EngineError> {
        var updated = logs
        var fresh: [EventEnvelope] = []
        for envelope in batch {
            if let stored = updated[envelope.workoutID]?[envelope.key] {
                guard stored == envelope else {
                    return .failure(.conflictingEnvelope(envelope.key))
                }
                continue
            }
            updated[envelope.workoutID, default: [:]][envelope.key] = envelope
            fresh.append(envelope)
        }
        logs = updated
        return .success(fresh)
    }

    func envelopes(for workout: WorkoutID) -> Set<EventEnvelope> {
        Set(logs[workout]?.values.map(\.self) ?? [])
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) -> UInt64? {
        logs[workout]?.keys.filter { $0.device == device }.map(\.seq).max()
    }
}

/// One draw of every field an event can carry, and one maker per event kind.
struct RandomFields {
    static let names = ["", "NaN", "+Infinity", "Ω≈ç√ \"q\" \\ /", "🏋️‍♀️ Squat", "e\u{301}", "\u{0}\u{2028}", "x"]

    static let makers: [@Sendable (RandomFields) -> WorkoutEvent] = [
        { .started(EventBuilders.session(EventBuilders.seedExercises, startedAt: $0.date)) },
        { .exerciseSelected(exerciseIndex: $0.index, setIndex: $0.index) },
        { .setLogged(exerciseIndex: $0.index, setID: $0.set, weight: $0.weight, reps: $0.reps, doneAt: $0.date) },
        { .setUnlogged(exerciseIndex: $0.index, setID: $0.set) },
        { .setTargetChanged(
            exerciseIndex: $0.index, setID: $0.set, weight: $0.flag ? $0.weight : nil, reps: $0.flag ? nil : $0.reps
        ) },
        { .setAdded(exerciseIndex: $0.index, set: $0.loggedSet) },
        { .allSetsRepeated(exerciseIndex: $0.index, weight: $0.weight, reps: $0.reps) },
        { .exerciseSwapped(
            exerciseIndex: $0.index, exerciseID: ExerciseID(EventBuilders.uuid($0.index)), name: $0.name,
            alsoUpdateProgram: $0.flag
        ) },
        { .restStarted(endsAt: $0.date, total: $0.duration) },
        { .restExtended(amount: $0.duration, extendsShownRest: $0.flag, tappedAt: $0.date) },
        { _ in .restSkipped },
        { .finished(endedAt: $0.date) },
        { .discarded(endedAt: $0.date) }
    ]

    let date: Date
    let weight: Weight
    let reps: Reps
    let duration: Duration
    let index: Int
    let flag: Bool
    let name: String

    init(using random: inout SeededGenerator) {
        date = WorkoutEventStoreContract.at(Double.random(in: -1e9 ... 1e9, using: &random))
        let sign: FloatingPointSign = Bool.random(using: &random) ? .minus : .plus
        weight = Weight(grams: Decimal(
            sign: sign,
            exponent: Int.random(in: -30 ... 20, using: &random),
            significand: Decimal(UInt64.random(in: 0 ... .max, using: &random))
        ))
        reps = Reps(clamping: Int.random(in: 1 ... 10000, using: &random))
        duration = Duration(
            secondsComponent: Int64.random(in: -1 << 40 ... 1 << 40, using: &random),
            attosecondsComponent: Int64.random(in: 0 ..< 1_000_000_000_000_000_000, using: &random)
        )
        index = Int.random(in: 0 ... 50, using: &random)
        flag = Bool.random(using: &random)
        name = Self.names.randomElement(using: &random) ?? ""
    }

    var set: SetID {
        EventBuilders.setID(index, index)
    }

    var loggedSet: LoggedSet {
        LoggedSet(id: set, weight: weight, reps: reps, kind: .drop, doneAt: flag ? date : nil)
    }
}
