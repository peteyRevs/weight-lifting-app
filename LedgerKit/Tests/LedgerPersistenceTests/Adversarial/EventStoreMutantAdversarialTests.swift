import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 1: is the moved contract still strong enough against *GRDB* mistakes? Each
/// `Mutation` is one plausible slip in `GRDBWorkoutEventStore`, on the real schema. The contract, plus
/// the GRDB suite's decoded-comparison check, must catch every one; the real store must pass both.
@Suite("Adversarial S1 · GRDB store mutants", .tags(.persistence), .timeLimit(.minutes(1)))
struct EventStoreMutantAdversarialTests {
    @Test("The real GRDB store passes the contract and the decoded-comparison check")
    func realStore_passesEverything() async throws {
        #expect(await WorkoutEventStoreContract.violations { try MutantGRDBStore(nil) }.isEmpty)
        #expect(try await MutantGRDBStore.decodedComparisonViolation(MutantGRDBStore(nil)) == nil)
    }

    @Test("Every GRDB mutant is caught", arguments: MutantGRDBStore.Mutation.allCases)
    func mutant_isCaught(_ mutation: MutantGRDBStore.Mutation) async throws {
        var found = await WorkoutEventStoreContract.violations { try MutantGRDBStore(mutation) }
        if let issue = try await MutantGRDBStore.decodedComparisonViolation(MutantGRDBStore(mutation)) {
            found.append(issue)
        }
        #expect(!found.isEmpty, "\(mutation) passed every check")
    }
}

/// `GRDBWorkoutEventStore`'s logic on the v001 schema, with at most one deliberate bug.
struct MutantGRDBStore: WorkoutEventStore {
    enum Mutation: String, CaseIterable, Sendable {
        /// Judges a stored key by comparing payload bytes, not decoded envelopes.
        case comparesBytes
        /// Payload dates as seconds since 1970 (`JSONEncoder.DateEncodingStrategy.secondsSince1970`).
        case payloadSecondsSince1970
        /// Payload dates as milliseconds since 1970 (GRDB's JSON default).
        case payloadMilliseconds
        /// Reads `wallClock` back from `wall_clock`, stored as seconds since 1970.
        case stampFromColumnSince1970
        /// Reads `wallClock` back from `wall_clock` as stored (seconds since 2001; `NULL` read as NaN).
        case stampFromColumn
        /// Writes each row in its own transaction, so rows before a conflict stay.
        case noTransaction
        /// `INSERT OR IGNORE`: a stored key is always a duplicate, never a conflict.
        case insertOrIgnore
        /// A same-key envelope with the same event is a duplicate, whatever its stamp.
        case ignoresStamp
        /// `MAX(seq)` on the signed column.
        case signedHighestSeq
        /// Returns what it stored sorted by `seq`.
        case returnsSortedBySeq
        /// Refuses non-finite stamps, as a `wall_clock REAL NOT NULL` column would.
        case refusesNonFiniteStamp
        /// Compacts by the lower-case UUID text, which matches no row.
        case compactsLowercased
        /// Decodes without the non-finite float strategy.
        case decoderWithoutNonFinite
    }

    let mutation: Mutation?
    let queue: DatabaseQueue

    init(_ mutation: Mutation?) throws {
        self.mutation = mutation
        queue = try LedgerDatabase.inMemory()
    }

    func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope] {
        if mutation == .refusesNonFiniteStamp {
            _ = try envelopes.map { try ColumnCodec.seconds($0.wallClock) }
        }
        let rows = try envelopes.map { try ($0, encode($0)) }
        let body: @Sendable (Database) throws -> [EventEnvelope] = { try insert(rows, into: $0) }
        let fresh = if mutation == .noTransaction {
            try await queue.writeWithoutTransaction(body)
        } else {
            try await queue.write(body)
        }
        return mutation == .returnsSortedBySeq ? fresh.sorted { $0.seq < $1.seq } : fresh
    }

    private func insert(_ rows: [(EventEnvelope, Data)], into database: Database) throws -> [EventEnvelope] {
        var fresh: [EventEnvelope] = []
        for (envelope, payload) in rows {
            let key: StatementArguments = [
                ColumnCodec.text(envelope.workoutID), ColumnCodec.text(envelope.device),
                ColumnCodec.column(seq: envelope.seq)
            ]
            let stored = try Data.fetchOne(
                database,
                sql: "SELECT payload FROM workout_event WHERE workout_id = ? AND device_id = ? AND seq = ?",
                arguments: key
            )
            if let stored, mutation != .insertOrIgnore {
                guard try isDuplicate(stored, of: envelope, payload: payload) else {
                    throw EngineError.conflictingEnvelope(envelope.key)
                }
                continue
            }
            let seconds = envelope.wallClock.timeIntervalSinceReferenceDate
            let column = mutation == .stampFromColumnSince1970 ? envelope.wallClock.timeIntervalSince1970 : seconds
            var arguments = key
            arguments += [column.isFinite ? column : nil, payload]
            try database.execute(
                sql: """
                INSERT OR IGNORE INTO workout_event (workout_id, device_id, seq, wall_clock, payload, created_at)
                VALUES (?, ?, ?, ?, ?, 'now')
                """,
                arguments: arguments
            )
            if database.changesCount > 0 {
                fresh.append(envelope)
            }
        }
        return fresh
    }

    private func isDuplicate(_ stored: Data, of envelope: EventEnvelope, payload: Data) throws -> Bool {
        switch mutation {
        case .comparesBytes:
            return stored == payload
        case .ignoresStamp:
            let old = try decode(stored)
            return old.key == envelope.key && old.event == envelope.event
        default:
            return try decode(stored) == envelope
        }
    }

    func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope] {
        let rows = try await queue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT payload, wall_clock FROM workout_event WHERE workout_id = ? ORDER BY id",
                arguments: [ColumnCodec.text(workout)]
            ).map { ($0["payload"] as Data, $0["wall_clock"] as Double?) }
        }
        return try rows.map { payload, stamp in
            let envelope = try decode(payload)
            guard mutation == .stampFromColumn || mutation == .stampFromColumnSince1970 else {
                return envelope
            }
            let seconds = stamp ?? .nan
            let wallClock = mutation == .stampFromColumn
                ? Date(timeIntervalSinceReferenceDate: seconds) : Date(timeIntervalSince1970: seconds)
            return EventEnvelope(
                event: envelope.event, workoutID: envelope.workoutID, device: envelope.device, seq: envelope.seq,
                wallClock: wallClock
            )
        }
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64? {
        let order = mutation == .signedHighestSeq ? "seq DESC" : "seq < 0 DESC, seq DESC"
        let stored = try await queue.read { database in
            try Int64.fetchOne(
                database,
                sql: "SELECT seq FROM workout_event WHERE workout_id = ? AND device_id = ? ORDER BY \(order) LIMIT 1",
                arguments: [ColumnCodec.text(workout), ColumnCodec.text(device)]
            )
        }
        return stored.map(ColumnCodec.seq(column:))
    }

    func uncompactedWorkoutIDs() async throws -> [WorkoutID] {
        let stored = try await queue
            .read { try String.fetchAll($0, sql: "SELECT DISTINCT workout_id FROM workout_event") }
        return try stored.map { text throws(LedgerPersistenceError) in try ColumnCodec.identifier(text) }
    }

    func compact(workout: WorkoutID) async throws {
        let text = ColumnCodec.text(workout)
        try await queue.write { database in
            try database.execute(
                sql: "DELETE FROM workout_event WHERE workout_id = ?",
                arguments: [mutation == .compactsLowercased ? text.lowercased() : text]
            )
        }
    }
}

extension MutantGRDBStore {
    // MARK: Codec

    private func encode(_ envelope: EventEnvelope) throws -> Data {
        switch mutation {
        case .payloadSecondsSince1970, .payloadMilliseconds:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            encoder.dateEncodingStrategy = mutation == .payloadMilliseconds ? .millisecondsSince1970 : .secondsSince1970
            encoder.nonConformingFloatEncodingStrategy = .convertToString(
                positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN"
            )
            return try encoder.encode(envelope)
        default:
            return try EnvelopeCodec.encode(envelope)
        }
    }

    private func decode(_ payload: Data) throws -> EventEnvelope {
        switch mutation {
        case .payloadSecondsSince1970, .payloadMilliseconds, .decoderWithoutNonFinite:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = switch mutation {
            case .payloadMilliseconds: .millisecondsSince1970
            case .payloadSecondsSince1970: .secondsSince1970
            default: .deferredToDate
            }
            if mutation != .decoderWithoutNonFinite {
                decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                    positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN"
                )
            }
            return try decoder.decode(EventEnvelope.self, from: payload)
        default:
            return try EnvelopeCodec.decode(payload)
        }
    }

    // MARK: The GRDB suite's own check

    /// `WorkoutEventStoreTests.append_comparesDecodedEnvelopes_notBytes` against `store`: the stored copy of
    /// an envelope was written by another encoder (unsorted keys), and a re-append must still be a duplicate.
    static func decodedComparisonViolation(_ store: MutantGRDBStore) async throws -> String? {
        let envelope = WorkoutEventStoreContract.start(WorkoutEventStoreContract.workout)
        let unsorted = try JSONEncoder().encode(envelope)
        try await store.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO workout_event (workout_id, device_id, seq, wall_clock, payload, created_at)
                VALUES (?, ?, 1, NULL, ?, 'then')
                """,
                arguments: [ColumnCodec.text(envelope.workoutID), ColumnCodec.text(envelope.device), unsorted]
            )
        }
        do {
            let fresh = try await store.append([envelope])
            return fresh.isEmpty ? nil : "stored the other encoding's copy again"
        } catch {
            return "re-append of another encoding's copy threw \(error)"
        }
    }
}
