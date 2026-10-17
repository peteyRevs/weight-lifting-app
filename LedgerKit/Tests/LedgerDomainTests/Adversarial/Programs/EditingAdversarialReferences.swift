import Foundation
@testable import LedgerDomain
import Testing

// Reference rules for the F11 S1 adversarial suites, written from the plan in whole numbers so that no
// expected value passes through the code under test or through `Decimal` rounding.

// MARK: - Names (slice criterion 2)

extension EditAdv {
    /// Unicode general category `Cc`: U+0000…U+001F and U+007F…U+009F, 65 scalars.
    static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x1F || (0x7F ... 0x9F).contains(scalar.value)
    }

    /// What "trims white space and newlines" removes from the ends: Unicode `White_Space`, plus U+200B,
    /// which Foundation's `whitespacesAndNewlines` also holds (probed on this toolchain).
    static func isBlank(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar.value == 0x200B
    }

    /// "Removes every scalar of general category `Cc`, then trims white space and newlines; `nil` when
    /// nothing is left", scalar by scalar.
    static func referenceName(_ text: String) -> [Unicode.Scalar]? {
        var scalars = Array(text.unicodeScalars).filter { !isControl($0) }
        while let first = scalars.first, isBlank(first) {
            scalars.removeFirst()
        }
        while let last = scalars.last, isBlank(last) {
            scalars.removeLast()
        }
        return scalars.isEmpty ? nil : scalars
    }

    /// The reference name as text, for a model that stores it.
    static func referenceNameText(_ text: String) -> String? {
        referenceName(text).map { scalars in
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars)
            return String(view)
        }
    }

    /// Whether `name` is the reference's result for `text`, scalar for scalar (`String ==` would take a
    /// composed and a decomposed letter for the same).
    static func isReferenceName(_ name: String?, for text: String) -> Bool {
        name.map { Array($0.unicodeScalars) } == referenceName(text)
    }

    /// `scalar` as "U+00E9", for a failure message.
    static func codePoint(_ scalar: Unicode.Scalar) -> String {
        "U+" + String(scalar.value, radix: 16, uppercase: true)
    }
}

// MARK: - Clamps (slice criterion 7; rules 2 and 3)

extension EditAdv {
    static func clamped(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }

    /// Rest: 30…300 s on the 15. No whole number of seconds is half way between two multiples of 15.
    static func referenceRest(_ seconds: Int) -> Int {
        (clamped(seconds, 30, 300) + 7) / 15 * 15
    }

    /// RPE as half points (10…20, that is 5…10) for `hundredths / 100`: the nearest half, a value half
    /// way between two going up, as `RPE(clamping:)` declares.
    static func referenceRPEHalves(hundredths: Int) -> Int {
        clamped((clamped(hundredths, 0, 2000) + 25) / 50, 10, 20)
    }

    /// Whether `hundredths / 100` is half way between two halves (7.25, 7.75): the one case the plan's
    /// "nearest half" does not decide.
    static func isRPETie(hundredths: Int) -> Bool {
        hundredths % 50 == 25
    }

    static func rpe(halves: Int) -> Decimal {
        Decimal(halves) / 2
    }

    static func decimal(hundredths: Int) -> Decimal {
        Decimal(hundredths) / 100
    }
}

// MARK: - Loads in whole tenths of a microgram (ADR-007's stored grain, 10⁻⁷ g)

extension EditAdv {
    /// 10⁻⁷ g in a hundredth of a unit: 0.01 lb is 4.5359237 g, 0.01 kg is 10 g.
    static func grain(_ units: Units) -> Int {
        units == .lb ? 45_359_237 : 100_000_000
    }

    /// `hundredths / 100` of `units`, as a count of 10⁻⁷ g.
    static func fine(hundredths: Int, _ units: Units) -> Int {
        hundredths * grain(units)
    }

    /// The exact weight of `fine` × 10⁻⁷ g (a division by a power of ten is exact in `Decimal`).
    static func weight(fine: Int) -> Weight {
        Weight(grams: Decimal(fine) / 10_000_000)
    }

    /// Rule 1, decisions #9 and #22, as hundredths of the unit: barbell 5 lb / 2.5 kg, kettlebell 5 lb /
    /// 2 kg, everything else 2.5 lb / 1.25 kg.
    static func defaultStepHundredths(_ equipment: Equipment, _ units: Units) -> Int {
        switch (equipment, units) {
        case (.barbell, .lb), (.kettlebell, .lb): 500
        case (.barbell, .kg): 250
        case (.kettlebell, .kg): 200
        case (_, .lb): 250
        case (_, .kg): 125
        }
    }

    /// Rule 6 and the plan's behaviour 10: the multiple of `step` next to `load` on the side asked for,
    /// never below zero. A load on a multiple moves one step; a load between two goes to the one above or
    /// the one below. `load` is not negative and `step` is positive, both in 10⁻⁷ g.
    static func referenceStep(load: Int, step: Int, _ direction: StepDirection) -> Int {
        let below = load / step * step
        switch direction {
        case .upward: return below + step
        case .downward: return below == load ? max(0, load - step) : below
        }
    }
}
