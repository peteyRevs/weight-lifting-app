import Foundation

/// An exact mass in grams (ADR-007, amending decision #9). Never a `Double`.
///
/// `grams` is an exact `Decimal`: `.pounds(185)` is 185 × 453.59237 = 83,914.58845 g, with no
/// rounding on construction. Arithmetic (`+`, `-`, `scaled(by:)`) is exact, so pound loads never
/// drift (185 lb + 6 × 2.5 lb == `.pounds(200)`) and ties on any step are real ties. Rounding
/// happens only where a rule says so: `rounded(toStep:_:)` (rules 12, 15; decision #3) and the
/// Brzycki estimate (decision #4). Equality, hashing and ordering are numeric (1 g == 1.00 g).
///
/// Encodes as `{"grams": "83914.58845"}`: the exact decimal text, so no JSON consumer can
/// degrade it through `Double`. Persistence stores whole 10⁻⁷ g (ADR-007).
public struct Weight: Hashable, Codable, Sendable, Comparable, AdditiveArithmetic {
    public let grams: Decimal

    public init(grams: Decimal) {
        self.grams = grams
    }

    public static let zero = Weight(grams: 0)

    /// Decision #9 / ADR-007: exactly `value` pounds (`value` × 453.59237 g, not rounded).
    /// Pass non-dyadic values as exact decimals (`Decimal(string:)`): a float literal such as
    /// `453.59237` goes through `Double` first (dyadic values like 242.25 or 52.5 are exact).
    public static func pounds(_ value: Decimal) -> Weight {
        Weight(grams: value * Units.lb.gramsPerUnit)
    }

    /// Decision #9 / ADR-007: exactly `value` kilograms.
    public static func kilograms(_ value: Decimal) -> Weight {
        Weight(grams: value * Units.kg.gramsPerUnit)
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
        grams / units.gramsPerUnit
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
    /// (default: ties away from zero, so 242.5 lb → 245 lb on a 5 lb step), computed exactly as
    /// `(grams / step.grams).rounded(rule) × step.grams`. A non-positive step returns `self`.
    func rounded(
        toStep step: Weight,
        _ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> Weight {
        guard step > .zero else {
            return self
        }
        let count = (grams / step.grams).rounded(scale: 0, rule)
        return Weight(grams: count * step.grams)
    }

    /// Spec §7.2 (`start + step × adv`) and rule 6 (stepper ± step): exactly `self + count × step`.
    func advanced(bySteps count: Int, of step: Weight) -> Weight {
        Weight(grams: grams + Decimal(count) * step.grams)
    }

    /// Rules 12 and 15 (`load × 0.85`): the exact product. Round it with `rounded(toStep:)`.
    func scaled(by factor: Decimal) -> Weight {
        Weight(grams: grams * factor)
    }
}

// MARK: - Presentation

public extension Weight {
    /// Rule 34/38 number format, no unit suffix: "185", "52.5", "46.25", "0", "83.9".
    ///
    /// A value that is a whole number of quarter units (every plate and step value: 1.25, 2.5,
    /// 52.5 …) prints exactly with trailing zeros dropped; anything else (usually a converted
    /// value such as 185 lb in kg = 83.91458845) prints to one decimal. '.' is always the decimal point.
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

// MARK: - Codable (exact decimal text)

public extension Weight {
    private enum CodingKeys: String, CodingKey {
        case grams
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(grams: DecimalText.decode(container, forKey: .grams))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(DecimalText.encode(grams), forKey: .grams)
    }
}
