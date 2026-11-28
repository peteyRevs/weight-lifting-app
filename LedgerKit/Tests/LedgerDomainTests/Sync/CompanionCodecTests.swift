import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F19 S2: the companion payloads and their bytes (`CompanionCodec`): criterion 2's revision rule, the context's
/// 256 KB bound and criterion 8's file fallback for a record over 60 000 bytes.
@Suite("CompanionCodec", .tags(.domain))
struct CompanionCodecTests {
    // MARK: Revision (criterion 2)

    @Test("A context replaces the held one only with a higher revision; any context replaces none")
    func test_context_revisionMonotonic() {
        let held = Self.context(revision: 7)
        #expect(held.supersedes(nil))
        #expect(Self.context(revision: 8).supersedes(held))
        #expect(!Self.context(revision: 7).supersedes(held))
        #expect(!Self.context(revision: 6).supersedes(held))
        #expect(!Self.context(revision: 0).supersedes(Self.context(revision: .max)))
    }

    // MARK: Round trips

    @Test("Every payload round-trips behind the header 0x43 0x01, and every date keeps every bit")
    func encode_roundTrips_withMagicAndVersion() throws {
        let program = try Fixtures.fourDayProgram()
        let last = LastPerformance(date: Engine.at(1 / 3), sets: 5, reps: 5, load: .kilograms(dec("102.5")))
        let custom = Fixtures.inclineDB
        try Self.expectRoundTrip(Self.context(revision: 42))
        try Self.expectRoundTrip(Self.record(WireCodecTests.setsLogged(12)))
        try Self.expectRoundTrip(CompanionFile.workoutLog(Self.record([])))
        try Self.expectRoundTrip(CompanionFile.program(
            program, customExercises: [custom], lastPerformance: [custom.id: last, Fixtures.bench.id: last]
        ))
        let empty = CompanionContext(
            revision: 0, programID: nil, programName: nil, weekIndex: 0, weekCount: 0, isDeload: false,
            nextDay: nil, settings: WatchSettings(.default), acknowledgedWorkoutIDs: []
        )
        try Self.expectRoundTrip(empty)
    }

    // MARK: Refusals

    @Test(
        "A payload of another version is refused whole, typed with the version it was written in",
        arguments: [UInt8(0), 2, 0xFF]
    )
    func decode_refusesAnotherVersion(version: UInt8) throws {
        var payload = try CompanionCodec.encode(Self.record(WireCodecTests.setsLogged(3)))
        payload[payload.startIndex + 1] = version
        #expect(throws: CompanionCodecError.unsupportedVersion(version)) {
            try CompanionCodec.decode(FinishedWorkoutRecord.self, from: payload)
        }
    }

    @Test("Bytes without the magic and a version byte are not a payload: a live frame among them")
    func decode_refusesWhatIsNotAPayload() throws {
        let frame = try #require(try WireCodec.encode(.envelopes([])).first)
        for data in [Data(), Data([CompanionCodec.magic]), frame, Data("{}".utf8)] {
            #expect(throws: CompanionCodecError.notAPayload) {
                try CompanionCodec.decode(CompanionContext.self, from: data)
            }
        }
    }

    @Test("JSON that is not the payload asked for is unreadable: a context read as a record, a broken tail")
    func decode_refusesTheWrongPayload() throws {
        let context = try CompanionCodec.encode(Self.context(revision: 1))
        #expect(throws: CompanionCodecError.unreadable) {
            try CompanionCodec.decode(FinishedWorkoutRecord.self, from: context)
        }
        #expect(throws: CompanionCodecError.unreadable) {
            try CompanionCodec.decode(CompanionContext.self, from: context.dropLast())
        }
    }

    @Test("A date that is not finite cannot be encoded")
    func encode_refusesANonFiniteDate() {
        var record = Self.record([])
        record.finishedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(throws: CompanionCodecError.unencodable) {
            try CompanionCodec.encode(record)
        }
    }

    // MARK: The context's bound

    @Test("A full context is far under 256 000 bytes; one of exactly the limit encodes, one byte more is refused")
    func test_context_encodedUnder256KB() throws {
        var full = Self.context(revision: .max)
        full.acknowledgedWorkoutIDs = (0 ..< 200).map { WorkoutID(EventBuilders.uuid(0xA000 + $0)) }
        #expect(try CompanionCodec.encode(full).count < 20000)
        #expect(CompanionCodec.contextLimit == 256_000)

        var padded = Self.context(revision: 1)
        padded.programName = ""
        let base = try CompanionCodec.encode(padded).count
        padded.programName = String(repeating: "x", count: CompanionCodec.contextLimit - base)
        #expect(try CompanionCodec.encode(padded).count == CompanionCodec.contextLimit)
        padded.programName? += "x"
        #expect(throws: CompanionCodecError.tooLarge) {
            try CompanionCodec.encode(padded)
        }
        var flooded = Self.context(revision: 1)
        flooded.acknowledgedWorkoutIDs = (0 ..< 7000).map { WorkoutID(EventBuilders.uuid(0x10000 + $0)) }
        #expect(throws: CompanionCodecError.tooLarge) {
            try CompanionCodec.encode(flooded)
        }
    }

    // MARK: The record's route (criterion 8)

    @Test("A record of 60 000 encoded bytes goes as user info, one of 60 001 as a file")
    func test_record_encodedUnder60000_orFileFallback() throws {
        #expect(CompanionCodec.delivery(forEncodedSize: 0) == .userInfo)
        #expect(CompanionCodec.delivery(forEncodedSize: 60000) == .userInfo)
        #expect(CompanionCodec.delivery(forEncodedSize: 60001) == .file)

        let base = try CompanionCodec.encode(Self.record([WireCodecTests.swap(named: 0, seq: 2)])).count
        let atLimit = Self.record([WireCodecTests.swap(named: CompanionCodec.userInfoLimit - base, seq: 2)])
        let overLimit = Self.record([WireCodecTests.swap(named: CompanionCodec.userInfoLimit - base + 1, seq: 2)])
        #expect(try CompanionCodec.encode(atLimit).count == 60000)
        #expect(try CompanionCodec.encode(overLimit).count == 60001)
        #expect(try CompanionCodec.delivery(for: atLimit) == .userInfo)
        #expect(try CompanionCodec.delivery(for: overLimit) == .file)
    }

    @Test("A 30-set workout goes as user info; 300 logged sets go as a file, which still round-trips")
    func delivery_realisticWorkouts() throws {
        #expect(try CompanionCodec.delivery(for: Self.record(WireCodecTests.setsLogged(30))) == .userInfo)
        let long = Self.record(WireCodecTests.setsLogged(300))
        #expect(try CompanionCodec.delivery(for: long) == .file)
        try Self.expectRoundTrip(CompanionFile.workoutLog(long))
    }
}

extension CompanionCodecTests {
    /// A context naming the seed program and a next day, with two acknowledged workouts.
    static func context(revision: UInt64) -> CompanionContext {
        CompanionContext(
            revision: revision,
            programID: Fixtures.programID,
            programName: "Upper / Lower · 12 weeks",
            weekIndex: 4,
            weekCount: 12,
            isDeload: false,
            nextDay: NextDay(
                dayTemplateID: DayTemplateID(EventBuilders.uuid(0xD001)),
                name: "Lower A",
                tag: "Squat focus",
                weekday: .thursday,
                exerciseCount: 5,
                setCount: 17,
                firstExerciseName: "Back Squat",
                isToday: true,
                isLoggedToday: false
            ),
            settings: WatchSettings(.default),
            acknowledgedWorkoutIDs: [EventBuilders.workoutID, WorkoutID(EventBuilders.uuid(0xF1F1))]
        )
    }

    /// The watch's record of a workout with `log`.
    static func record(_ log: [EventEnvelope]) -> FinishedWorkoutRecord {
        FinishedWorkoutRecord(
            workoutID: EventBuilders.workoutID,
            log: log,
            healthKitUUID: EventBuilders.uuid(0xBEEF),
            finishedAt: Engine.at(3600.000_123),
            device: Engine.watch
        )
    }

    /// `payload` decodes equal from its bytes, which start with the magic and the version.
    static func expectRoundTrip<Payload: CompanionPayload & Equatable>(
        _ payload: Payload,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let data = try CompanionCodec.encode(payload)
        #expect(Array(data.prefix(2)) == [0x43, 0x01], sourceLocation: sourceLocation)
        let same = try CompanionCodec.decode(Payload.self, from: data) == payload
        #expect(same, "the \(Payload.self) did not round-trip", sourceLocation: sourceLocation)
    }
}
