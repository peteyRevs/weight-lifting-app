import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8 criterion 3 (Q1 ruled C, by equipment): what the chosen exercise brings, and the load its sets take.
@Suite("SwapAlternatives · replacement", .tags(.domain))
struct SwapReplacementTests {
    /// Bench 5 × 5 at 185 lb, as the seed session builds it.
    static let bench = EventBuilders.seedSession().exercises[0]

    static func exercise(_ name: String, _ equipment: Equipment, start: [Units: Weight]) -> Exercise {
        Exercise(
            id: ExerciseID(EventBuilders.uuid(0xA500 + name.count)),
            name: name,
            shortName: name.uppercased(),
            equipment: equipment,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: start
        )
    }

    static let inclineBench = exercise(
        "Incline Bench Press", .barbell, start: [.lb: .pounds(45), .kg: .kilograms(20)]
    )
    static let dumbbellBench = exercise(
        "Dumbbell Bench Press", .dumbbell, start: [.lb: .pounds(15), .kg: .kilograms(7.5)]
    )

    /// What a swap brings with no history.
    static func fresh(_ equipment: Equipment, step: Weight, load: Weight) -> SwappedExercise {
        SwappedExercise(equipment: equipment, step: step, load: load, lastPerformance: nil)
    }

    static func last(_ load: Weight) -> LastPerformance {
        LastPerformance(date: EventBuilders.start.addingTimeInterval(-86400), sets: 3, reps: 10, load: load)
    }

    @Test("Same equipment, never done: the original's target load (Bench 185 → Incline Bench 185)")
    func sameEquipment_keepsTheTargetLoad() {
        let swapped = SwapAlternatives.replacement(of: Self.bench, with: Self.inclineBench, last: nil, units: .lb)
        #expect(swapped == Self.fresh(.barbell, step: .pounds(5), load: .pounds(185)))
    }

    @Test("Other equipment, never done: its catalog start load (Bench 185 → Dumbbell Bench 15)")
    func otherEquipment_takesTheStartLoad() {
        let swapped = SwapAlternatives.replacement(of: Self.bench, with: Self.dumbbellBench, last: nil, units: .lb)
        #expect(swapped == Self.fresh(.dumbbell, step: .pounds(2.5), load: .pounds(15)))
    }

    @Test("Done before: its last load, rounded to its step, whatever the equipment (→ Dumbbell Bench, last 60: 60)")
    func history_takesTheLastLoad_rounded() {
        let sixty = Self.last(.pounds(60))
        let swapped = SwapAlternatives.replacement(of: Self.bench, with: Self.dumbbellBench, last: sixty, units: .lb)
        let expected = SwappedExercise(
            equipment: .dumbbell, step: .pounds(2.5), load: .pounds(60), lastPerformance: sixty
        )
        #expect(swapped == expected)
        let odd = Self.last(.pounds(61.3))
        #expect(SwapAlternatives.replacement(of: Self.bench, with: Self.inclineBench, last: odd, units: .lb).load
            == .pounds(60))
    }

    @Test("Kilograms: a kettlebell takes its start on a 2 kg step; a pound history is rounded to the kg step")
    func kilograms_steps() {
        let kettlebell = Self.exercise(
            "Kettlebell Floor Press", .kettlebell, start: [.lb: .pounds(15), .kg: .kilograms(8)]
        )
        let fresh = SwapAlternatives.replacement(of: Self.bench, with: kettlebell, last: nil, units: .kg)
        #expect(fresh.step == .kilograms(2) && fresh.load == .kilograms(8))
        // 135 lb is 61.23 kg: 62 on the kettlebell's 2 kg step, 61.25 on a dumbbell's 1.25 kg step.
        let pounds = Self.last(.pounds(135))
        #expect(SwapAlternatives.replacement(of: Self.bench, with: kettlebell, last: pounds, units: .kg).load
            == .kilograms(62))
        #expect(SwapAlternatives.replacement(of: Self.bench, with: Self.dumbbellBench, last: pounds, units: .kg).load
            == .kilograms(61.25))
    }

    @Test("Same equipment in kilograms: the target load in pounds is rounded to the kg step")
    func sameEquipment_kilograms_rounded() {
        let swapped = SwapAlternatives.replacement(of: Self.bench, with: Self.inclineBench, last: nil, units: .kg)
        #expect(swapped.step == .kilograms(2.5) && swapped.load == .kilograms(85)) // 185 lb = 83.91 kg
    }

    @Test("A start known only in the other unit is converted; none at all is zero (bodyweight)")
    func startLoad_otherUnitOrNone() {
        let poundsOnly = Self.exercise("Machine Chest Press", .machine, start: [.lb: .pounds(40)])
        #expect(SwapAlternatives.replacement(of: Self.bench, with: poundsOnly, last: nil, units: .kg).load
            == .kilograms(18.75)) // 40 lb = 18.14 kg, to 1.25 kg
        let pushUp = Self.exercise("Push-Up", .bodyweight, start: [:])
        let swapped = SwapAlternatives.replacement(of: Self.bench, with: pushUp, last: nil, units: .lb)
        #expect(swapped.load == .zero && swapped.step == .pounds(2.5))
    }

    @Test("Never below zero: a negative history, target or start gives zero")
    func neverNegative() {
        var negative = Self.bench
        negative.targetLoad = .pounds(-50)
        let fromTarget = SwapAlternatives.replacement(of: negative, with: Self.inclineBench, last: nil, units: .lb)
        #expect(fromTarget.load == .zero)
        let below = Self.last(.pounds(-20))
        #expect(SwapAlternatives.replacement(of: Self.bench, with: Self.dumbbellBench, last: below, units: .lb).load
            == .zero)
        let odd = Self.exercise("Odd", .cable, start: [.lb: .pounds(-10)])
        #expect(SwapAlternatives.replacement(of: Self.bench, with: odd, last: nil, units: .lb).load == .zero)
    }

    @Test("The replacement's equipment decides, not its name: the original's step plays no part")
    func originalStep_isIgnored() {
        var bench = Self.bench
        bench.step = .pounds(10) // a slot's custom step
        let swapped = SwapAlternatives.replacement(of: bench, with: Self.inclineBench, last: nil, units: .lb)
        #expect(swapped.step == .pounds(5))
    }
}
