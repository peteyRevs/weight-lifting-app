import Foundation

/// Why LedgerPersistence refused to store or read a value (engineering-standards §8).
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
}
