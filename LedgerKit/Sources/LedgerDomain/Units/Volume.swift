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
        let tenthsOfThousands = (value(in: units) / 100).roundedToInt()
        return NumberText.fixed(tenthsOfThousands, fractionDigits: 1, trimZeros: false, grouped: true) + "k"
    }

    /// Rule 34 (Today tile), for a caller that draws the "k" itself: the number `compact(in:)` prints,
    /// without the "k": "24.2" for 24,180 lb. It is cut from `compact(in:)`, so the two cannot
    /// disagree. Only the zero volume differs: it reads "0", where `compact(in:)` prints "0.0k". Every
    /// other volume keeps the one decimal, so 40 lb reads "0.0".
    public func thousands(in units: Units) -> String {
        gramReps == 0 ? "0" : String(compact(in: units).dropLast())
    }

    /// Rule 43 ("lb moved · +8%"): the change from `previous` to this volume in whole percent,
    /// `(self − previous) ÷ previous × 100`, rounded once, half away from zero: 24,180 lb after
    /// 22,400 lb is 8, and −2.5 is −3. The arithmetic is `Decimal`'s, never `Double`'s (ADR-007).
    ///
    /// `nil` when there is no percentage to give: `previous` is zero, or the result is not a number
    /// (a volume is NaN, or the arithmetic leaves `Decimal`'s own range, about 10¹⁶⁵). A change too
    /// large for `Int` is clamped to `Int.min` or `Int.max`. It never traps.
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
