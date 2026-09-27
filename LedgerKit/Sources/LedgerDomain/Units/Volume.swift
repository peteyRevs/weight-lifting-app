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
        try container.encode(DecimalText.encode(gramReps), forKey: .gramReps)
    }
}
