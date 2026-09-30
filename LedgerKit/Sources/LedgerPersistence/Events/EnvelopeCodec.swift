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
enum EnvelopeCodec {
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

    static func decode(_ payload: Data) throws -> EventEnvelope {
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
