import Foundation

/// The unit a lifter reads and enters weights in (decision #9: lb and kg both ship at launch).
///
/// `CodingKeyRepresentable` makes `[Units: Weight]` encode as a JSON object (`{"lb": …}`)
/// rather than a flat key/value array.
public enum Units: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    // swiftlint:disable:next identifier_name - unit symbols named by the F02 brief; renaming breaks `.lb` call sites
    case lb, kg
}

// MARK: - Exact unit lattices (internal)

extension Units {
    /// Grams in one unit. 1 lb is defined as exactly 453.59237 g (built from integers; a
    /// `Decimal` float literal would go through `Double` and lose the last digits).
    var gramsPerUnit: Decimal {
        switch self {
        case .lb: Decimal(sign: .plus, exponent: -5, significand: 45_359_237)
        case .kg: 1000
        }
    }

    /// Quanta per unit: the finest increment a weight in this unit is exact to.
    /// lb: 0.01 lb (≈ 4.54 g, so every hundredth of a pound maps to a distinct gram value and back);
    /// kg: 1 g (grams are the storage unit, so kilograms are always exact).
    var quantaPerUnit: Decimal {
        switch self {
        case .lb: 100
        case .kg: 1000
        }
    }

    /// Decision #9: the unit a step, bar or plate is denominated in. A weight that is a whole
    /// number of quarter pounds (every pound plate and increment: 0.25, 1.25, 2.5, 5, 45 …) is a
    /// pound weight; anything else (2.5 kg, 1.25 kg, 20 kg …) is a kilogram weight. Of the 0.25 kg
    /// multiples up to 60 kg only 11 kg is also a whole number of quarter pounds (24.25 lb, 0.4 g
    /// away), so every realistic kilogram step, bar and plate is read as kilograms (tested).
    static func denominating(_ weight: Weight) -> Units {
        let hundredths = weight.quanta(in: .lb)
        let isWholeQuarterPounds = hundredths % 25 == 0 && Weight(quanta: Decimal(hundredths), in: .lb) == weight
        return isWholeQuarterPounds ? .lb : .kg
    }
}

extension Weight {
    /// This weight as a whole number of the unit's quanta (lb: hundredths, kg: grams).
    func quanta(in units: Units) -> Int {
        (Decimal(grams) * units.quantaPerUnit / units.gramsPerUnit).roundedToInt()
    }

    /// The weight that is exactly `quanta` of the unit's quanta, to the nearest gram.
    init(quanta: Decimal, in units: Units) {
        self.init(grams: (quanta * units.gramsPerUnit / units.quantaPerUnit).roundedToInt())
    }
}
