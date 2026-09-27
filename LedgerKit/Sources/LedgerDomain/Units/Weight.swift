import Foundation

/// Exact mass in grams. 1 lb = 453.59237 g. Never a `Double` (engineering-standards §5, decision #9).
///
/// Pound weights are not whole grams, so any operation that must land on a pound value
/// (rounding to a 5 lb step, adding 2.5 lb) runs in the step's own unit lattice
/// (`Units.denominating(_:)`) and converts back once. That keeps every prescribed pound load
/// equal to `Weight.pounds(x)` for the same `x`: 250 lb + 7 × 5 lb == `.pounds(285)`, never 1 g off.
public struct Weight: Hashable, Codable, Sendable, Comparable, AdditiveArithmetic {
    public let grams: Int

    public init(grams: Int) {
        self.grams = grams
    }

    public static let zero = Weight(grams: 0)

    /// Decision #9: `value` pounds, rounded half away from zero to the nearest gram.
    /// Pass non-dyadic values as exact decimals (`Decimal(string:)`): a float literal such as
    /// `453.59237` goes through `Double` first (dyadic values like 242.25 or 52.5 are exact).
    public static func pounds(_ value: Decimal) -> Weight {
        Weight(grams: (value * Units.lb.gramsPerUnit).roundedToInt())
    }

    /// Decision #9: `value` kilograms, rounded half away from zero to the nearest gram.
    public static func kilograms(_ value: Decimal) -> Weight {
        Weight(grams: (value * Units.kg.gramsPerUnit).roundedToInt())
    }

    /// The exact value in pounds (up to 38 significant digits; round for display).
    public var pounds: Decimal {
        value(in: .lb)
    }

    /// The exact value in kilograms.
    public var kilograms: Decimal {
        value(in: .kg)
    }

    /// The exact value in `units`.
    public func value(in units: Units) -> Decimal {
        Decimal(grams) / units.gramsPerUnit
    }

    public static func < (lhs: Weight, rhs: Weight) -> Bool {
        lhs.grams < rhs.grams
    }

    public static func + (lhs: Weight, rhs: Weight) -> Weight {
        Weight(grams: lhs.grams + rhs.grams)
    }

    public static func - (lhs: Weight, rhs: Weight) -> Weight {
        Weight(grams: lhs.grams - rhs.grams)
    }
}

// MARK: - Step arithmetic

public extension Weight {
    /// Spec §7.2 / rule 12 / decision #3: the nearest multiple of `step` under `rule`
    /// (default: ties away from zero, so 242.5 lb → 245 lb on a 5 lb step).
    ///
    /// The division runs in the step's unit (`Units.denominating`): `self` and `step` are taken
    /// to the nearest 0.01 lb (or 1 g for kilogram steps), so a tie that is exact in pounds stays
    /// a tie. The result is exactly `n × step` in that unit. A non-positive step returns `self`.
    func rounded(
        toStep step: Weight,
        _ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> Weight {
        guard step > .zero else {
            return self
        }
        let units = Units.denominating(step)
        let stepQuanta = step.quanta(in: units)
        let count = (Decimal(quanta(in: units)) / Decimal(stepQuanta)).roundedToInt(rule)
        return Weight(quanta: Decimal(count) * Decimal(stepQuanta), in: units)
    }

    /// Spec §7.2 (`start + step × adv`) and rule 6 (stepper ± step): `self` plus `count` steps,
    /// computed in the step's unit so pound loads never drift from `Weight.pounds(_:)`.
    /// Zero steps (or a zero step) return `self` unchanged.
    func advanced(bySteps count: Int, of step: Weight) -> Weight {
        guard count != 0, step != .zero else {
            return self
        }
        let units = Units.denominating(step)
        let total = quanta(in: units) + count * step.quanta(in: units)
        return Weight(quanta: Decimal(total), in: units)
    }

    /// Rules 12 and 15 (`load × 0.85`): exact `Decimal` product, then the nearest gram.
    func scaled(by factor: Decimal) -> Weight {
        Weight(grams: (Decimal(grams) * factor).roundedToInt())
    }
}

// MARK: - Presentation

public extension Weight {
    /// Rule 34/38 number format, no unit suffix: "185", "52.5", "46.25", "0", "83.9".
    ///
    /// A value that is a whole number of quarter units (every plate and step value: 1.25, 2.5,
    /// 52.5 …) prints exactly with trailing zeros dropped; anything else (usually a converted
    /// value such as 185 lb in kg = 83.915) prints to one decimal. '.' is always the decimal point.
    func formatted(in units: Units) -> String {
        let value = value(in: units)
        let hundredths = (value * 100).roundedToInt()
        if hundredths % 25 == 0 {
            return NumberText.fixed(hundredths, fractionDigits: 2)
        }
        return NumberText.fixed((value * 10).roundedToInt(), fractionDigits: 1)
    }

    /// Decision #4 presentation of an estimated 1RM: the value rounded to a whole unit
    /// (195 lb × 5 → 219.375 lb → 219).
    func wholeValue(in units: Units) -> Int {
        value(in: units).roundedToInt()
    }
}
