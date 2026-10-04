import Foundation

/// What a store can keep exactly (ADR-007, "Persistence"), as one rule for every store: the GRDB columns
/// (LedgerPersistence's `ColumnCodec`) and LedgerFakes' in-memory stores (ADR-008), so a fake refuses what the
/// database refuses, with the same error, as `ExerciseSearch` keeps search one rule.
///
/// - A weight, or a volume in gram·reps, is stored as a whole count of 10⁻⁷ g within `Int64` (±922,337 t).
///   Anything else (⅛ lb is 566,990,462.5 units, NaN, 10⁹ kg × 5 reps) throws `RepositoryError.inexactWeight`
///   with the grams given: the boundary refuses rather than rounds.
/// - A date is stored as a finite count of seconds since 2001; ±∞ and NaN throw `RepositoryError.nonFiniteDate`.
public enum StorageBoundary {
    /// A gram is 10⁷ stored units.
    private static let unitExponent = 7

    /// `grams` as a whole count of 10⁻⁷ g. It only moves the decimal exponent, so it never rounds.
    public static func units(ofGrams grams: Decimal) throws(RepositoryError) -> Int64 {
        let units = Decimal(sign: .plus, exponent: unitExponent, significand: grams)
        guard let count = Int64(units.description) else {
            throw .inexactWeight(grams)
        }
        return count
    }

    /// The grams a count of 10⁻⁷ g stands for, exactly.
    public static func grams(units count: Int64) -> Decimal {
        Decimal(sign: count < 0 ? .minus : .plus, exponent: -unitExponent, significand: Decimal(count.magnitude))
    }

    /// `date` as seconds since 2001; throws `nonFiniteDate` for ±∞ and NaN.
    public static func seconds(_ date: Date) throws(RepositoryError) -> Double {
        let seconds = date.timeIntervalSinceReferenceDate
        guard seconds.isFinite else {
            throw .nonFiniteDate
        }
        return seconds
    }
}

public extension Weight {
    /// Throws `RepositoryError.inexactWeight` unless a store can keep the weight exactly (`StorageBoundary`).
    func checkStorable() throws(RepositoryError) {
        _ = try StorageBoundary.units(ofGrams: grams)
    }
}

public extension Volume {
    /// Throws `RepositoryError.inexactWeight` unless a store can keep the volume exactly (`StorageBoundary`).
    func checkStorable() throws(RepositoryError) {
        _ = try StorageBoundary.units(ofGrams: gramReps)
    }
}
