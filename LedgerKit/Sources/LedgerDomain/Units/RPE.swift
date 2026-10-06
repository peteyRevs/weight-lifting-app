import Foundation

/// Target rate of perceived exertion: 5…10 in 0.5 steps (rule 3).
///
/// Stored as a count of half points so that `8` and `8.0` are the same value with the same hash.
/// Encodes as a bare number (`8.5`); decoding re-validates.
public struct RPE: Hashable, Codable, Sendable, Comparable {
    private let halfPoints: Int

    /// Rule 3: the lowest and the highest RPE.
    static let range: ClosedRange<Decimal> = 5 ... 10

    /// Rule 3: RPE moves in halves.
    static let step = Decimal(1) / 2

    /// Rule 3: `nil` unless `value` is in 5…10 and a multiple of 0.5.
    public init?(_ value: Decimal) {
        let doubled = value * 2
        guard doubled.rounded(scale: 0, .toNearestOrAwayFromZero) == doubled, Self.range.contains(value) else {
            return nil
        }
        halfPoints = doubled.roundedToInt()
    }

    /// Rule 3 stepper semantics: `value` held to 5…10, then rounded to the nearest half (a tie goes up:
    /// 7.25 → 7.5). A NaN, which `Decimal` orders below every number, becomes 5.
    public init(clamping value: Decimal) {
        let held = min(max(value, Self.range.lowerBound), Self.range.upperBound)
        halfPoints = (held * 2).roundedToInt()
    }

    /// The RPE value, e.g. `8.5`.
    public var value: Decimal {
        Decimal(halfPoints) / 2
    }

    /// "8", "8.5" (the number in "RPE 8").
    public var label: String {
        NumberText.fixed(halfPoints * 5, fractionDigits: 1)
    }

    /// Rule 12 / decision #3: deload lowers RPE by 2, never below 5.
    func deloaded() -> RPE {
        RPE(clamping: value - 2)
    }

    public static func < (lhs: RPE, rhs: RPE) -> Bool {
        lhs.halfPoints < rhs.halfPoints
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Decimal.self)
        guard let rpe = RPE(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "RPE must be 5…10 by 0.5, got \(raw)"
            )
        }
        self = rpe
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
