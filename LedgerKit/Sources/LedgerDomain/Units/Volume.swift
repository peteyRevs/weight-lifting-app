import Foundation

/// Σ weight × reps, in gram·reps (rule 34: "lb moved" = Σ over done sets of w × r).
public struct Volume: Hashable, Codable, Sendable, Comparable, AdditiveArithmetic {
    public let gramReps: Int

    public init(gramReps: Int) {
        self.gramReps = gramReps
    }

    /// The volume of one set: `weight × reps`.
    public init(weight: Weight, reps: Reps) {
        gramReps = weight.grams * reps.value
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
        Decimal(gramReps) / units.gramsPerUnit
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
}
