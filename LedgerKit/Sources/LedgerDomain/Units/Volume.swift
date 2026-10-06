import Foundation

/// Σ weight × reps, in exact gram·reps (rule 34: "lb moved" = Σ over done sets of w × r; ADR-007).
///
/// Exact like `Weight`, so 1,000 reps of 185 lb is exactly "185,000" lb moved at any horizon.
/// Encodes as `{"gramReps": "419572.94225"}` (exact decimal text).
public struct Volume: Hashable, Codable, Sendable, Comparable, AdditiveArithmetic {
    public let gramReps: Decimal

    public init(gramReps: Decimal) {
        self.gramReps = gramReps
    }

    /// The volume of one set: `weight × reps`, exactly.
    public init(weight: Weight, reps: Reps) {
        gramReps = weight.grams * Decimal(reps.value)
    }

    public static let zero = Volume(gramReps: 0)

    /// Rule 34: whole units with ',' thousands separators: "24,180".
    public func formatted(in units: Units) -> String {
        NumberText.thousands(value(in: units).roundedToInt())
    }

    /// Rule 34 (Today tile): thousands of units to exactly one decimal plus "k": "41.2k", "24.0k".
    public func compact(in units: Units) -> String {
        compactDigits(in: units) + "k"
    }

    /// Rule 34 (Today tile), for a caller that draws the "k" itself: the number `compact(in:)` prints,
    /// without the "k": "24.2" for 24,180 lb. Only the zero volume differs: it reads "0", where
    /// `compact(in:)` prints "0.0k". Every other volume keeps the one decimal: 40 lb, and a volume
    /// too small to show at all, read "0.0".
    public func thousands(in units: Units) -> String {
        gramReps == 0 ? "0" : compactDigits(in: units)
    }

    /// Rule 43 ("lb moved · +8%"): the change from `previous` to this volume in whole percent,
    /// `(self − previous) ÷ previous × 100`, rounded once, half away from zero: 24,180 lb after
    /// 22,400 lb is 8, and −2.5 is −3. The arithmetic is `Decimal`'s, never `Double`'s (ADR-007).
    /// For a negative `previous` the sign is the formula's, not the direction of the change: 100
    /// after −100 is −200.
    ///
    /// `nil` when there is no percentage to give: `previous` is zero, either volume is not a number,
    /// or `Decimal`'s arithmetic gives no number for the difference, the quotient or the percent
    /// (NaN, as for a result too large for it to hold). A change too large for `Int` is clamped to
    /// `Int.min` or `Int.max`. It never traps.
    public func percentChange(from previous: Volume) -> Int? {
        guard previous.gramReps != 0 else {
            return nil
        }
        let change = (gramReps - previous.gramReps) / previous.gramReps * 100
        guard change.isFinite else {
            return nil
        }
        return min(max(change, Decimal(Int.min)), Decimal(Int.max)).roundedToInt()
    }

    /// The digits `compact(in:)` and `thousands(in:)` share: thousands of units to one decimal,
    /// with ',' between thousands ("24.2", "1,234.5").
    private func compactDigits(in units: Units) -> String {
        let tenthsOfThousands = (value(in: units) / 100).roundedToInt()
        return NumberText.fixed(tenthsOfThousands, fractionDigits: 1, trimZeros: false, grouped: true)
    }

    private func value(in units: Units) -> Decimal {
        gramReps / units.gramsPerUnit
    }

    public static func < (lhs: Volume, rhs: Volume) -> Bool {
        lhs.gramReps < rhs.gramReps
    }

    public static func + (lhs: Volume, rhs: Volume) -> Volume {
        Volume(gramReps: lhs.gramReps + rhs.gramReps)
    }

    public static func - (lhs: Volume, rhs: Volume) -> Volume {
        Volume(gramReps: lhs.gramReps - rhs.gramReps)
    }

    private enum CodingKeys: String, CodingKey {
        case gramReps
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(gramReps: DecimalText.decode(container, forKey: .gramReps))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try DecimalText.encode(gramReps, into: &container, forKey: .gramReps)
    }
}
