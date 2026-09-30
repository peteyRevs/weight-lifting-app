import Foundation

/// Why LedgerPersistence refused to store or read a value (engineering-standards §8).
///
/// Other errors reach callers unwrapped, and nothing is swallowed: GRDB's `DatabaseError` (SQLite itself,
/// e.g. a locked or full disk), `EncodingError` (an envelope with a NaN `Weight`, which has no exact text),
/// `DecodingError` (a settings payload whose JSON holds an invalid value), `EngineError.conflictingEnvelope`
/// from `append`, and `CancellationError`.
public enum LedgerPersistenceError: Error, Equatable, Sendable {
    /// ADR-007: a weight, or a volume in gram·reps, that is not a whole number of 10⁻⁷ g or lies beyond
    /// `Int64` (±922,337 t). The storage boundary rejects it rather than round it.
    case inexactWeight(Decimal)
    /// A date column holds a finite count of seconds; ±∞ and NaN have no column value.
    case nonFiniteDate
    /// A stored identifier that is not a UUID string.
    case malformedIdentifier(String)
    /// A stored JSON payload in a version this app version does not know: a later one wrote it.
    case unknownPayloadVersion(Int)
    /// A column that holds the wrong kind of value, e.g. a payload version stored as text or a payload
    /// that is not UTF-8 (`"table.column"`). Only damage or a foreign writer makes one.
    case malformedColumn(String)
}
