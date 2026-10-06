import Foundation
@testable import LedgerDomain
import Testing

/// Seeded checks of `Volume.percentChange(from:)` and `Volume.thousands(in:)` (F09 S2, criteria 2 and 3).
@Suite("Volume percent change and thousands properties", .tags(.domain, .property))
struct VolumePropertyTests {
    /// `numerator / denominator` rounded half away from zero, in integer arithmetic alone.
    static func roundedQuotient(_ numerator: Int64, _ denominator: Int64) -> Int64 {
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        guard 2 * abs(remainder) >= abs(denominator) else {
            return quotient
        }
        return (numerator < 0) == (denominator < 0) ? quotient + 1 : quotient - 1
    }

    /// `hundredths` hundredths of a pound or of a kilogram, lifted once.
    static func volume(hundredths: Int64, of units: Units) -> Volume {
        let amount = Decimal(hundredths) / 100
        return Volume(gramReps: (units == .lb ? Weight.pounds(amount) : Weight.kilograms(amount)).grams)
    }
}

extension VolumePropertyTests {
    @Test(
        "The percent change equals integer arithmetic on hundredths of a unit, rounded half away from zero.",
        arguments: PropertySeed.all
    )
    func percentChange_matchesIntegerArithmetic(seed: PropertySeed) {
        var generator = seed.generator
        for _ in 0 ..< 50 {
            // Small volumes make exact ties common; large ones are a lifetime's training in hundredths.
            let limit: Int64 = [100, 10000, 1_000_000_000_000].randomElement(using: &generator) ?? 100
            let current = Int64.random(in: -limit ... limit, using: &generator)
            let previous = Int64.random(in: -limit ... limit, using: &generator)
            let units = Units.allCases.randomElement(using: &generator) ?? .lb
            let expected = previous == 0
                ? nil
                : Int(clamping: Self.roundedQuotient(100 * (current - previous), previous))
            let percent = Self.volume(hundredths: current, of: units)
                .percentChange(from: Self.volume(hundredths: previous, of: units))
            #expect(percent == expected, "\(current) after \(previous) hundredths of a \(units)")
        }
    }

    @Test(
        "Every volume but zero reads as compact does without its k, with one decimal, in pounds and kilograms.",
        arguments: PropertySeed.all
    )
    func thousands_matchesCompact(seed: PropertySeed) {
        var generator = seed.generator
        for _ in 0 ..< 50 {
            let limit: Int64 = [0, 10000, 100_000_000, 1_000_000_000_000].randomElement(using: &generator) ?? 0
            let volume = Self.volume(
                hundredths: Int64.random(in: -limit ... limit, using: &generator),
                of: Units.allCases.randomElement(using: &generator) ?? .lb
            )
            for units in Units.allCases {
                let text = volume.thousands(in: units)
                guard volume != .zero else {
                    #expect(text == "0")
                    continue
                }
                #expect(text + "k" == volume.compact(in: units), "\(volume.gramReps) in \(units)")
                #expect(text.split(separator: ".").last?.count == 1, "\(text)")
                #expect(text.count(where: { $0 == "." }) == 1, "\(text)")
            }
        }
    }
}
