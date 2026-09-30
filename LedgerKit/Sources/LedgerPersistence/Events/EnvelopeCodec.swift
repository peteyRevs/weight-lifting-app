import Foundation
import LedgerDomain

/// An envelope as `workout_event.payload`: JSON, and the source of truth for what the event store reads
/// back (F05 implementation notes, "Date encoding").
///
/// - Dates keep `JSONEncoder`'s default `.deferredToDate`: a binary64 count of seconds since 2001,
///   written with shortest round-trip digits, so every date reads back `==` (F04 "Inputs" item 4).
///   GRDB's JSON default, milliseconds since 1970, does not.
/// - A non-finite date is written as a string: the store keeps a malformed envelope like any other,
///   and JSON has no ±∞ or NaN.
/// - Keys are sorted, so an envelope always encodes to the same bytes.
/// - Every row records the payload version it was written in (`workout_event.payload_version`), and
///   decoding dispatches on it, so a later shape of `EventEnvelope` adds a version rather than stranding the
///   rows already stored (orchestrator decision, 2026-09-30). Version 1 is the only one so far.
enum EnvelopeCodec {
    /// The payload version `encode` writes.
    static let version = 1

    static func encode(_ envelope: EventEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: positiveInfinity,
            negativeInfinity: negativeInfinity,
            nan: notANumber
        )
        return try encoder.encode(envelope)
    }

    /// Decodes a payload written in `version`; throws `LedgerPersistenceError.unknownPayloadVersion` for a
    /// version this app does not know, and the decoder's error for bytes it cannot read.
    static func decode(_ payload: Data, version: Int) throws -> EventEnvelope {
        switch version {
        case 1:
            try decodeVersion1(payload)
        default:
            throw LedgerPersistenceError.unknownPayloadVersion(version)
        }
    }

    private static func decodeVersion1(_ payload: Data) throws -> EventEnvelope {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: positiveInfinity,
            negativeInfinity: negativeInfinity,
            nan: notANumber
        )
        return try decoder.decode(EventEnvelope.self, from: payload)
    }

    private static let positiveInfinity = "+Infinity"
    private static let negativeInfinity = "-Infinity"
    private static let notANumber = "NaN"
}
