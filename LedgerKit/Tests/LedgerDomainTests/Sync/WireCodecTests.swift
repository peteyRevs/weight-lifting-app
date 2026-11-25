import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F17 S1: the live wire format, criteria 1 and 2 (`WireCodec`, `WireFrame`); `WireCodecRefusalTests` holds the rest.
@Suite("WireCodec", .tags(.domain))
struct WireCodecTests {
    /// A handshake vector naming both devices.
    static let vector: [DeviceID: UInt64] = [Engine.phone: 12, Engine.watch: 3]

    /// One frame of each kind, an empty one and both vectors' edges among them.
    static let frames: [WireFrame] = [
        .envelopes([]),
        .envelopes(ReduceTerminalTests.lateEvents.enumerated().map { offset, event in
            Engine.envelope(
                event,
                10 + Double(offset),
                from: offset.isMultiple(of: 2) ? Engine.phone : Engine.watch,
                seq: UInt64(offset + 1)
            )
        }),
        .handshake(workoutID: EventBuilders.workoutID, contiguousSeq: vector),
        .handshake(workoutID: EventBuilders.workoutID, contiguousSeq: [:]),
        .replayRequest(workoutID: EventBuilders.workoutID, contiguousSeq: vector),
        .replayRequest(workoutID: WorkoutID(EventBuilders.uuid(0xF101)), contiguousSeq: [Engine.watch: .max])
    ]

    // MARK: Criterion 1

    @Test("Criterion 1: every frame round-trips, as one payload that starts with 0x4C 0x01", arguments: frames)
    func encode_roundTrips_withMagicAndVersion(frame: WireFrame) throws {
        let payloads = try WireCodec.encode(frame)
        let payload = try #require(payloads.first)
        #expect(payloads.count == 1)
        #expect(Array(payload.prefix(2)) == [0x4C, 0x01])
        let decoded = try WireCodec.decode(payload)
        let same = decoded == frame
        #expect(same, "the frame did not round-trip")
    }

    @Test("Dates keep every bit: a stamp and a payload date with sub-millisecond fractions decode equal")
    func encode_keepsDatesExactly() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: Engine.at(0.000_123_456_789).timeIntervalSinceReferenceDate
            .nextUp)
        let done = Engine.at(1 / 3)
        let envelope = EventBuilders.envelope(Engine.logged(0, 0, at: 0), seq: 2, at: stamp)
        let logged = EventEnvelope(
            event: .setLogged(
                exerciseIndex: 0,
                setID: Engine.set(0, 0),
                weight: .kilograms(dec("102.5")),
                reps: Reps(clamping: 3),
                doneAt: done
            ),
            workoutID: envelope.workoutID, device: Engine.watch, seq: 3, wallClock: done
        )
        let payloads = try WireCodec.encode(.envelopes([envelope, logged]))
        let decoded = try #require(try Self.envelopes(in: payloads))
        #expect(decoded.map(\.wallClock) == [stamp, done])
        #expect(decoded == [envelope, logged])
    }

    @Test("A frame read from a slice of a larger buffer decodes as the frame")
    func decode_readsASlice() throws {
        let frame = WireFrame.handshake(workoutID: EventBuilders.workoutID, contiguousSeq: Self.vector)
        let payload = try #require(try WireCodec.encode(frame).first)
        let slice = (Data([0xFF, 0xFF, 0xFF]) + payload).dropFirst(3)
        #expect(slice.startIndex == 3)
        #expect(try WireCodec.decode(slice) == frame)
    }

    // MARK: Criterion 2

    @Test("Criterion 2: 400 envelopes of about 300 bytes are cut into frames of at most 60 000 bytes, in order")
    func encode_cutsAt60000Bytes() throws {
        let envelopes = Self.setsLogged(400)
        let single = try #require(try WireCodec.encode(.envelopes([envelopes[0]])).first).count
        let empty = try #require(try WireCodec.encode(.envelopes([])).first).count
        #expect((250 ... 350).contains(single - empty), "one envelope takes \(single - empty) bytes")
        let payloads = try WireCodec.encode(.envelopes(envelopes))
        #expect(payloads.count > 1)
        #expect(payloads.allSatisfy { $0.count <= WireCodec.frameLimit }, "sizes \(payloads.map(\.count))")
        #expect(payloads.allSatisfy { Array($0.prefix(2)) == [0x4C, 0x01] })
        let decoded = try #require(try Self.envelopes(in: payloads))
        #expect(decoded.map(\.seq) == Array(1 ... 400))
        let same = decoded == envelopes
        #expect(same, "the concatenated decode differs from the input")
    }

    @Test("Two envelopes that cannot share a frame go one per frame; one that fits alone is never cut")
    func encode_cutsBetweenEnvelopes() throws {
        let large = [Self.swap(named: 40000, seq: 1), Self.swap(named: 40000, seq: 2)]
        let payloads = try WireCodec.encode(.envelopes(large))
        #expect(payloads.count == 2)
        #expect(payloads.allSatisfy { $0.count <= WireCodec.frameLimit })
        #expect(try Self.envelopes(in: payloads)?.map(\.seq) == [1, 2])
        let fits = try WireCodec.encode(.envelopes([Self.swap(named: WireCodec.frameLimit - 1000, seq: 3)]))
        #expect(fits.count == 1 && fits[0].count <= WireCodec.frameLimit)
    }

    @Test("A large workout's started snapshot fits one frame: 12 exercises of 8 sets with a drop row each")
    func encode_largeStartFitsOneFrame() throws {
        let specs = (0 ..< 12).map { index in
            EventBuilders.ExerciseSpec(
                "Exercise number \(index) with a long name",
                .barbell,
                sets: 8,
                reps: 12,
                pounds: 225,
                restSeconds: 180,
                dropSet: true
            )
        }
        let started = Engine.started(EventBuilders.session(specs))
        let payloads = try WireCodec.encode(.envelopes([started]))
        #expect(payloads.count == 1)
        #expect(payloads[0].count < WireCodec.frameLimit / 2, "the snapshot takes \(payloads[0].count) bytes")
    }

    @Test("An envelope, or a handshake, larger than the limit on its own is refused as tooLarge")
    func encode_refusesWhatCannotBeCut() {
        #expect(throws: WireCodecError.tooLarge) {
            try WireCodec.encode(.envelopes([Self.swap(named: WireCodec.frameLimit, seq: 1)]))
        }
        #expect(throws: WireCodecError.tooLarge) {
            try WireCodec.encode(.envelopes(Self.setsLogged(3) + [Self.swap(named: 70000, seq: 4)]))
        }
        let devices = (0 ..< 2000).map { DeviceID(EventBuilders.uuid(0x10000 + $0)) }
        let crowd = Dictionary(uniqueKeysWithValues: devices.map { ($0, UInt64.max) })
        #expect(throws: WireCodecError.tooLarge) {
            try WireCodec.encode(.handshake(workoutID: EventBuilders.workoutID, contiguousSeq: crowd))
        }
        #expect(throws: WireCodecError.tooLarge) {
            try WireCodec.encode(.replayRequest(workoutID: EventBuilders.workoutID, contiguousSeq: crowd))
        }
    }
}

// MARK: - Helpers

extension WireCodecTests {
    /// `count` set-logged envelopes from the watch, seq 1 … count, about 300 bytes each.
    static func setsLogged(_ count: Int) -> [EventEnvelope] {
        (1 ... count).map { seq in
            Engine.envelope(
                Engine.logged(seq % 5, seq % 3, at: Double(seq)),
                Double(seq) + 0.25,
                from: Engine.watch,
                seq: UInt64(seq)
            )
        }
    }

    /// A swap whose exercise is named with `length` letters: one envelope of about that many bytes.
    static func swap(named length: Int, seq: UInt64) -> EventEnvelope {
        let event = WorkoutEvent.exerciseSwapped(
            exerciseIndex: 0,
            exerciseID: ExerciseID(EventBuilders.uuid(0xE100)),
            name: String(repeating: "x", count: length),
            alsoUpdateProgram: false
        )
        return Engine.envelope(event, 20, seq: seq)
    }

    /// Every envelope `payloads` decode to, in order; nil if one is not an `.envelopes` frame.
    static func envelopes(in payloads: [Data]) throws -> [EventEnvelope]? {
        var all: [EventEnvelope] = []
        for payload in payloads {
            guard case let .envelopes(some) = try WireCodec.decode(payload) else {
                return nil
            }
            all += some
        }
        return all
    }

    /// `payload` with the bytes after the header replaced by `json`, under `version`.
    static func frame(_ json: String, version: UInt8 = WireCodec.version) -> Data {
        Data([WireCodec.magic, version]) + Data(json.utf8)
    }
}
