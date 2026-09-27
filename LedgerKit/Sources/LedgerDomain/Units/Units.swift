import Foundation

/// The unit a lifter reads and enters weights in (decision #9: lb and kg both ship at launch).
///
/// `CodingKeyRepresentable` makes `[Units: Weight]` encode as a JSON object (`{"lb": …}`)
/// rather than a flat key/value array.
public enum Units: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case lb, kg // allowed by `identifier_name.excluded` in .swiftlint.yml (unit symbols)
}

extension Units {
    /// Grams in one unit. 1 lb is defined as exactly 453.59237 g (built from integers; a
    /// `Decimal` float literal would go through `Double` and lose the last digits).
    var gramsPerUnit: Decimal {
        switch self {
        case .lb: Decimal(sign: .plus, exponent: -5, significand: 45_359_237)
        case .kg: 1000
        }
    }
}
