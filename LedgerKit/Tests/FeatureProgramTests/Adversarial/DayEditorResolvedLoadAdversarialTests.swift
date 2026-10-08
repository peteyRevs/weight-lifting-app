import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 1: `Slot.resolvedStartLoad` and `Slot.resolvedStep` against the pair of fallbacks
/// they replace (criterion 8 of the slice; S1's note "For S7"), and `ProgressionRules` and `DayEditing`
/// against product spec §7.2 and rule 6 worked by the tester, so that the two callers behave as before.
@Suite("Adversarial F11 S6 · the start load and the step a slot resolves to", .tags(.feature))
nonisolated struct DayEditorResolvedLoadAdversarialTests {
    static func catalog() throws -> [ExerciseID: Exercise] {
        try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
    }

    /// Every slot of the seed program four ways: as stored, without its start load, with a step of its own,
    /// and with neither.
    static func slots() throws -> [Slot] {
        try Fixtures.seedProgram().days.flatMap(\.slots).flatMap { slot in
            var bare = slot
            bare.startLoad = nil
            var stepped = slot
            stepped.step = .kilograms(2)
            var neither = bare
            neither.step = nil
            return [slot, bare, stepped, neither]
        }
    }

    @Test("For every seed slot in both units the two functions are the slot's own value or the exercise's")
    func resolved_forEverySeedSlot_isTheOldPairOfFallbacks() throws {
        let catalog = try Self.catalog()
        var wrong: [String] = []
        var checked = 0
        for slot in try Self.slots() {
            let exercise = try #require(catalog[slot.exerciseID])
            for units in Units.allCases {
                let start = slot.startLoad ?? exercise.startLoad(in: units)
                let step = slot.step ?? exercise.equipment.defaultStep(in: units)
                let isRight = slot.resolvedStartLoad(exercise: exercise, units: units) == start
                    && slot.resolvedStep(exercise: exercise, units: units) == step
                    && step > .zero && start >= .zero
                if !isRight {
                    wrong.append("\(exercise.name) \(units)")
                }
                checked += 1
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(4))")
        #expect(checked == 128)
    }

    @Test("Prescriptions are spec §7.2 worked from the old pair, for every seed slot, week, unit and set of misses")
    func prescriptions_areTheSpecsFormulaOverTheOldPair() throws {
        let catalog = try Self.catalog()
        let weeks = try Fixtures.seedProgram().weeks
        var wrong: [String] = []
        for var slot in try Self.slots() {
            let exercise = try #require(catalog[slot.exerciseID])
            for (units, misses) in [(Units.lb, Set<Int>()), (.kg, []), (.lb, [1, 4]), (.kg, [0, 6])] {
                slot.misses = misses
                let start = slot.startLoad ?? exercise.startLoad(in: units)
                let step = slot.step ?? exercise.equipment.defaultStep(in: units)
                let found = ProgressionRules.prescriptions(for: slot, weeks: weeks, exercise: exercise, units: units)
                for week in weeks {
                    let adv = (0 ..< week.index).count { !misses.contains($0) }
                    let span = Swift.max(1, slot.repsHi - slot.reps + 1)
                    var load = start
                    var reps = slot.reps
                    switch slot.progression {
                    case .linear: load = start.advanced(bySteps: adv, of: step)
                    case .double:
                        load = start.advanced(bySteps: adv / span, of: step)
                        reps += adv % span
                    case .fixed: break
                    }
                    if week.isDeload {
                        load = load.scaled(by: Decimal(85) / 100).rounded(toStep: step)
                    }
                    let one = found[week.index]
                    let isRight = one.load == load && one.reps == reps && one.step == step
                        && one.sets == (week.isDeload ? Swift.max(1, slot.sets - 1) : slot.sets)
                        && one.isHeld == misses.contains(week.index - 1) && one.isDeload == week.isDeload
                        && one == ProgressionRules.prescribe(
                            week: week, weekIndex: week.index, slot: slot, exercise: exercise, units: units
                        )
                    if !isRight {
                        wrong.append("\(exercise.name) \(units) week \(week.index + 1)")
                    }
                }
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(4))")
    }

    @Test("The start load's stepper goes to the next multiple of the old step from the old start, never below zero")
    func steppedStartLoad_usesTheOldPair() throws {
        let catalog = try Self.catalog()
        var wrong: [String] = []
        for slot in try Self.slots() {
            let exercise = try #require(catalog[slot.exerciseID])
            for units in Units.allCases {
                let start = slot.startLoad ?? exercise.startLoad(in: units)
                let step = slot.step ?? exercise.equipment.defaultStep(in: units)
                let count = start.grams / step.grams
                var below = count
                var above = count
                var whole = Decimal()
                NSDecimalRound(&whole, &below, 0, .down)
                below = whole == count ? count - 1 : whole
                NSDecimalRound(&whole, &above, 0, .up)
                above = whole == count ? count + 1 : whole
                let down = DayEditing.stepped(.startLoad, .downward, of: slot, exercise: exercise, units: units)
                let upward = DayEditing.stepped(.startLoad, .upward, of: slot, exercise: exercise, units: units)
                let isRight = down == .startLoad(Weight(grams: Swift.max(0, below) * step.grams))
                    && upward == .startLoad(Weight(grams: above * step.grams))
                if !isRight {
                    wrong.append("\(exercise.name) \(units): \(down) \(upward)")
                }
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(4))")
    }
}
