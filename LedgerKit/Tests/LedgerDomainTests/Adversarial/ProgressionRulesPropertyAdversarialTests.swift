import Foundation
@testable import LedgerDomain
import Testing

/// The spec §7.2 pseudo-code, transcribed with exact decimals in the program's unit.
struct ProgressionOracle {
    let start: Decimal
    let step: Decimal
    let slot: Slot
    let weekIndex: Int
    let isDeload: Bool

    var advancement: Int {
        (0 ..< weekIndex).count(where: { !slot.misses.contains($0) })
    }

    var loadAndReps: (load: Decimal, reps: Int) {
        switch slot.progression {
        case .linear:
            return (start + step * Decimal(advancement), slot.reps)
        case .double:
            let span = max(1, slot.repsHi - slot.reps + 1)
            return (start + step * Decimal(advancement / span), slot.reps + advancement % span)
        case .fixed:
            return (start, slot.reps)
        }
    }

    /// Rule 12 / decision #3: `(load × 0.85)` rounded half away from zero to a multiple of `step`.
    var load: Decimal {
        let base = loadAndReps.load
        guard isDeload else { return base }
        return decimalRounded(base * dec("0.85") / step) * step
    }

    var sets: Int {
        isDeload ? max(1, slot.sets - 1) : slot.sets
    }

    var rpe: Decimal {
        isDeload ? max(5, slot.rpe.value - 2) : slot.rpe.value
    }

    var isHeld: Bool {
        slot.misses.contains(weekIndex - 1)
    }
}

/// A random slot with its start load and step as exact decimals in the program's unit.
struct RandomSlot {
    let slot: Slot
    let start: Decimal
    let step: Decimal
}

@Suite("ProgressionRules properties (adversarial)", .tags(.domain, .property))
struct ProgressionRulesPropertyAdversarialTests {
    static func randomSlot(units: Units, using generator: inout SeededGenerator) throws -> RandomSlot {
        let steps = units == .lb ? ["1.25", "2.5", "5"] : ["1.25", "2.5"]
        let stepText = steps.randomElement(using: &generator) ?? "2.5"
        let start = randomMultiple(of: dec(stepText), in: 0 ... 240, using: &generator)
        let reps = Int.random(in: 1 ... 20, using: &generator)
        let weight: (Decimal) -> Weight = units == .lb ? { .pounds($0) } : { .kilograms($0) }
        let slot = try Fixtures.slot(
            Fixtures.backSquat,
            id: 990,
            sets: Int.random(in: 1 ... 12, using: &generator),
            reps: reps,
            repsHi: Int.random(in: reps + 1 ... min(40, reps + 6), using: &generator),
            rpe: Decimal(Int.random(in: 10 ... 20, using: &generator)) / 2,
            progression: Progression.allCases.randomElement(using: &generator) ?? .linear,
            startLoad: weight(start),
            step: weight(dec(stepText)),
            misses: Set((0 ..< 20).filter { _ in Int.random(in: 0 ..< 4, using: &generator) == 0 })
        )
        return RandomSlot(slot: slot, start: start, step: dec(stepText))
    }
}

extension ProgressionRulesPropertyAdversarialTests {
    @Test(
        "prescribe matches the spec §7.2 pseudo-code exactly for random slots.",
        arguments: PropertySeed.all(plus: [3_587_324])
    )
    func prescribe_matchesSpecOracle(seed: PropertySeed) throws {
        var generator = seed.generator
        let units: Units = Bool.random(using: &generator) ? .lb : .kg
        let random = try Self.randomSlot(units: units, using: &generator)
        let (slot, start, step) = (random.slot, random.start, random.step)
        let weekIndex = Int.random(in: 0 ... 24, using: &generator)
        let isDeload = Int.random(in: 0 ..< 3, using: &generator) == 0
        let oracle = ProgressionOracle(start: start, step: step, slot: slot, weekIndex: weekIndex, isDeload: isDeload)
        let prescription = ProgressionRules.prescribe(
            week: Fixtures.week(weekIndex, deload: isDeload),
            weekIndex: weekIndex,
            slot: slot,
            exercise: Fixtures.backSquat,
            units: units
        )
        let expectedLoad: Weight = units == .lb ? .pounds(oracle.load) : .kilograms(oracle.load)
        let context = "\(units) \(slot.progression) start \(start) step \(step) week \(weekIndex) deload \(isDeload)"
        #expect(prescription.load == expectedLoad, "\(context): \(oracle.load)")
        #expect(prescription.reps == oracle.loadAndReps.reps, "\(context)")
        #expect(prescription.sets == oracle.sets, "\(context)")
        #expect(prescription.rpe.value == oracle.rpe, "\(context)")
        #expect(prescription.isHeld == oracle.isHeld, "\(context)")
        #expect(prescription.isDeload == isDeload)
        #expect(prescription.load.formatted(in: units) == "\(oracle.load)", "\(context)")
    }

    @Test("Load never decreases from one non-deload week to the next.", arguments: PropertySeed.all)
    func prescribe_loadIsMonotonicAcrossWeeks(seed: PropertySeed) throws {
        var generator = seed.generator
        let slot = try Self.randomSlot(units: .lb, using: &generator).slot
        var previous = Weight.zero
        for week in 0 ..< 16 {
            let load = ProgressionRulesAdversarialTests.prescribe(slot, Fixtures.backSquat, week: week).load
            #expect(load >= previous, "week \(week)")
            previous = load
        }
    }
}
