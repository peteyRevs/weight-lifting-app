import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 1: `wallClock` and every payload date through `GRDBWorkoutEventStore`, bit for
/// bit, at the extremes and for any finite double; stored order against `EventEnvelope <`; ±∞ and NaN.
@Suite("Adversarial S1 · event store dates", .tags(.persistence), .timeLimit(.minutes(1)))
struct EventStoreDateAdversarialTests {
    typealias Contract = WorkoutEventStoreContract

    static func store() throws -> (GRDBWorkoutEventStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        return (GRDBWorkoutEventStore(queue, now: { EventBuilders.start }), queue)
    }

    /// Finite seconds since 2001 that stress a codec: the extremes, subnormals, signed zero, the F04 stamps
    /// and their neighbours one ulp away, and 10.493_826_8 as an absolute stamp.
    static let extremes: [Double] = {
        let f04 = [10.493_826_8, 10.493_827_3].map { Contract.at($0).timeIntervalSinceReferenceDate }
        let fixed: [Double] = [
            Date.distantPast.timeIntervalSinceReferenceDate, Date.distantFuture.timeIntervalSinceReferenceDate,
            .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
            .leastNormalMagnitude, 0, -0.0, 10.493_826_8, 1e22, -1e-300
        ]
        return fixed + f04 + f04.map(\.nextUp) + f04.map(\.nextDown)
    }()

    @Test("Extreme finite stamps and payload dates read back bit for bit, and wall_clock holds the same double")
    func extremes_readBackBitForBit() async throws {
        try await Self.expectExactRoundTrip(Self.extremes)
    }

    @Test(
        "Any finite double, and any sub-second stamp near now, reads back bit for bit in every date field",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func anyFiniteDate_readsBackBitForBit(_ seed: PropertySeed) async throws {
        var random = seed.generator
        var seconds: [Double] = []
        while seconds.count < 3 {
            let any = Double(bitPattern: random.next())
            if any.isFinite {
                seconds.append(any)
            }
        }
        let nearNow = (0 ..< 3).map { _ in
            EventBuilders.start.timeIntervalSinceReferenceDate + Double.random(in: 0 ..< 7200, using: &random)
        }
        try await Self.expectExactRoundTrip(seconds + nearNow)
    }

    @Test(
        "Rows ordered by wall_clock, device_id, then seq as unsigned come out in EventEnvelope < order",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func storedColumns_orderLikeEnvelopeLessThan(_ seed: PropertySeed) async throws {
        var random = seed.generator
        let devices = (0 ..< 3).map { _ in DeviceID(Self.uuid(using: &random)) }
        let stamps = (0 ..< 4).map { _ in Contract.at(Double.random(in: -5 ... 5, using: &random)) } // ties
        var log: [EventEnvelope] = []
        for (index, device) in devices.enumerated() {
            let seqs: [UInt64] = [1, UInt64(Int64.max), 1 << 63, .max, UInt64(index) + 2]
            log += seqs.map { seq in
                let stamp = stamps[Int.random(in: 0 ..< stamps.count, using: &random)]
                return EventBuilders.envelope(.restSkipped, device: device, seq: seq, at: stamp)
            }
        }
        log.shuffle(using: &random)
        let (store, queue) = try Self.store()
        _ = try await store.append(log)
        let ordered = try await queue.read { database in
            try Data.fetchAll(database, sql: """
            SELECT payload FROM workout_event ORDER BY wall_clock, device_id, seq < 0, seq
            """).map { try EnvelopeCodec.decode($0, version: EnvelopeCodec.version) }
        }
        #expect(ordered == log.sorted(by: <))
        let byStamp = try await queue.read { database in
            try Double.fetchAll(database, sql: "SELECT wall_clock FROM workout_event ORDER BY wall_clock")
        }
        #expect(byStamp == log.map(\.wallClock.timeIntervalSinceReferenceDate).sorted())
    }

    @Test("±∞ and NaN stamps and payload dates are stored: wall_clock is NULL, the payload keeps them")
    func nonFinite_areStored_payloadKeepsThem() async throws {
        let (store, queue) = try Self.store()
        let log = Self.envelopes([.infinity, -.infinity, .nan], firstSeq: 1)
        #expect(try await store.append(log).map(\.key) == log.map(\.key))
        let columns = try await queue.read { database in
            try Row.fetchAll(database, sql: "SELECT wall_clock, CAST(payload AS TEXT) AS json FROM workout_event")
                .map { ($0["wall_clock"] as Double?, $0["json"] as String) }
        }
        #expect(columns.allSatisfy { $0.0 == nil })
        let json = columns.map(\.1).joined()
        #expect(json.contains("\"+Infinity\"") && json.contains("\"-Infinity\"") && json.contains("\"NaN\""))
        let stored = try await store.envelopes(for: Contract.workout).sorted { $0.seq < $1.seq }
        #expect(stored.map { Self.bits($0) } == log.map { Self.bits($0) }, "NaN compared by bit pattern")
        // ±∞ re-append as duplicates. NaN is never == itself, so its re-append is a conflict: documented in
        // the contract (`nonFiniteIsStored`) and handed to F17 ("Inputs from F05": drop on receipt).
        let infinite = log.filter { !$0.wallClock.timeIntervalSinceReferenceDate.isNaN }
        #expect(try await store.append(infinite).isEmpty)
        let nan = try #require(log.first { $0.wallClock.timeIntervalSinceReferenceDate.isNaN })
        await #expect(throws: EngineError.conflictingEnvelope(nan.key)) { try await store.append([nan]) }
    }

    @Test("A string field spelled like a non-finite float stays a string")
    func stringsSpelledLikeNonFiniteFloats_stayStrings() async throws {
        var session = EventBuilders.session(EventBuilders.seedExercises)
        session.name = "NaN"
        session.tag = "+Infinity"
        let started = EventBuilders.envelope(.started(session), seq: 1, at: Contract.at(0))
        let (store, _) = try Self.store()
        _ = try await store.append([started])
        #expect(try await store.envelopes(for: Contract.workout) == [started])
    }

    // MARK: Helpers

    /// Appends one envelope per date-carrying event for each of `seconds`, then checks every date and the
    /// `wall_clock` column bit for bit, and that a re-append stores nothing.
    static func expectExactRoundTrip(_ seconds: [Double]) async throws {
        let (store, queue) = try store()
        let log = envelopes(seconds, firstSeq: 1)
        #expect(try await store.append(log) == log)
        #expect(try await store.append(log.reversed()).isEmpty)
        let stored = try await store.envelopes(for: Contract.workout).sorted { $0.seq < $1.seq }
        #expect(stored == log)
        #expect(stored.map { bits($0) } == log.map { bits($0) })
        let column = try await queue.read { database in
            try Double.fetchAll(database, sql: "SELECT wall_clock FROM workout_event ORDER BY id")
        }
        #expect(column == log.map(\.wallClock.timeIntervalSinceReferenceDate))
    }

    /// For each of `seconds`: a `started` snapshot, `setLogged`, `restStarted`, `restExtended` and `finished`,
    /// each dated and stamped `seconds` since 2001.
    static func envelopes(_ seconds: [Double], firstSeq: UInt64) -> [EventEnvelope] {
        seconds.enumerated().flatMap { index, value in
            let date = Date(timeIntervalSinceReferenceDate: value)
            let events: [WorkoutEvent] = [
                .started(EventBuilders.session(EventBuilders.seedExercises, startedAt: date)),
                .setLogged(
                    exerciseIndex: 0, setID: EventBuilders.setID(0, index), weight: .pounds(185),
                    reps: Reps(clamping: 5), doneAt: date
                ),
                .restStarted(endsAt: date, total: .seconds(90)),
                .restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: date),
                .finished(endedAt: date)
            ]
            return events.enumerated().map { offset, event in
                let seq = firstSeq + UInt64(index * events.count + offset)
                return EventBuilders.envelope(event, device: EventBuilders.watch, seq: seq, at: date)
            }
        }
    }

    /// The bit patterns of an envelope's stamp and payload date.
    static func bits(_ envelope: EventEnvelope) -> [UInt64] {
        let payload: Date? = switch envelope.event {
        case let .started(state): state.startedAt
        case let .setLogged(_, _, _, _, date), let .finished(date), let .discarded(date): date
        case let .restStarted(date, _), let .restExtended(_, _, date): date
        default: nil
        }
        return [envelope.wallClock, payload].compactMap { $0?.timeIntervalSinceReferenceDate.bitPattern }
    }

    static func uuid(using random: inout SeededGenerator) -> UUID {
        let bytes = (0 ..< 16).map { _ in UInt8.random(in: 0 ... .max, using: &random) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
