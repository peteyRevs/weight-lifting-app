import Foundation
import LedgerDomain

/// How Ledger's values become column values. Each replaces a GRDB 7.11 default that would lose data
/// or trap (F05 implementation notes, "Weight encoding" and "Date encoding"):
/// - weights and volumes are whole counts of 10⁻⁷ g in `INTEGER` columns suffixed `_e7g` (ADR-007),
///   so SQL compares and orders them exactly;
/// - identifiers are `uuidString` text, as the schema's `TEXT` ids expect, not GRDB's 16-byte blob;
/// - a `UInt64` sequence number is stored as its `Int64` bit pattern, where GRDB's `UInt64` conversion
///   traps above `Int64.max`;
/// - history dates are `REAL` seconds since 2001 (`timeIntervalSinceReferenceDate`), exact and
///   range-queryable, where GRDB writes millisecond text.
enum ColumnCodec {
    /// A gram is 10⁷ stored units.
    private static let unitExponent = 7

    // MARK: Exact mass (ADR-007)

    /// `grams` as a whole count of 10⁻⁷ g. It only moves the decimal exponent, so it never rounds: a
    /// value that is not a whole count (⅛ lb is 566,990,462.5 units), NaN, or one beyond `Int64` throws.
    static func e7g(grams: Decimal) throws(LedgerPersistenceError) -> Int64 {
        let units = Decimal(sign: .plus, exponent: unitExponent, significand: grams)
        guard let count = Int64(units.description) else {
            throw .inexactWeight(grams)
        }
        return count
    }

    /// The grams a stored count of 10⁻⁷ g stands for, exactly.
    static func grams(e7g count: Int64) -> Decimal {
        Decimal(sign: count < 0 ? .minus : .plus, exponent: -unitExponent, significand: Decimal(count.magnitude))
    }

    // MARK: Identifiers

    static func text(_ identifier: some TypedIdentifier) -> String {
        identifier.rawValue.uuidString
    }

    static func identifier<ID: TypedIdentifier>(_ text: String) throws(LedgerPersistenceError) -> ID {
        guard let uuid = UUID(uuidString: text) else {
            throw .malformedIdentifier(text)
        }
        return ID(uuid)
    }

    // MARK: Sequence numbers

    /// The column value of `seq`: its bit pattern, so seqs above `Int64.max` are stored negative.
    static func column(seq: UInt64) -> Int64 {
        Int64(bitPattern: seq)
    }

    static func seq(column: Int64) -> UInt64 {
        UInt64(bitPattern: column)
    }

    // MARK: Dates

    /// `date` as seconds since 2001 for a `REAL` column. Throws for ±∞ and NaN, which SQLite cannot
    /// keep (it stores NaN as `NULL`).
    static func seconds(_ date: Date) throws(LedgerPersistenceError) -> Double {
        guard let seconds = finiteSeconds(date) else {
            throw .nonFiniteDate
        }
        return seconds
    }

    /// `date` as seconds since 2001, or `nil` when it is not finite.
    static func finiteSeconds(_ date: Date) -> Double? {
        let seconds = date.timeIntervalSinceReferenceDate
        return seconds.isFinite ? seconds : nil
    }

    static func date(seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// A `created_at`, `updated_at` or `deleted_at` value: ISO 8601 UTC text to the millisecond, fixed
    /// width, so it sorts as text. It is row metadata, never compared with a domain date.
    static func timestamp(_ date: Date) -> String {
        date.formatted(timestampStyle)
    }

    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

extension Weight {
    /// The `_e7g` column value (ADR-007); throws `LedgerPersistenceError.inexactWeight`.
    func e7g() throws(LedgerPersistenceError) -> Int64 {
        try ColumnCodec.e7g(grams: grams)
    }

    init(e7g count: Int64) {
        self.init(grams: ColumnCodec.grams(e7g: count))
    }
}

extension Volume {
    /// The `_e7g_reps` column value: 10⁻⁷ g·reps; throws `LedgerPersistenceError.inexactWeight`.
    func e7gReps() throws(LedgerPersistenceError) -> Int64 {
        try ColumnCodec.e7g(grams: gramReps)
    }

    init(e7gReps count: Int64) {
        self.init(gramReps: ColumnCodec.grams(e7g: count))
    }
}
