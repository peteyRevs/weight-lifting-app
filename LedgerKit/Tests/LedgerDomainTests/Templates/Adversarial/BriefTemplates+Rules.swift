import Foundation
@testable import LedgerDomain
import Testing

// The rules a generated block is read through, written out from the spec so the downstream suites have
// expected values that do not come from `ProgressionRules`, `SessionBuilder` or `TimeEstimate`.

extension BriefTemplates {
    /// A template exercise's equipment (spec §6.2) and start load per unit (product decision #21's policy).
    struct CatalogRow: Sendable {
        var equipment: Equipment
        var pounds: Decimal
        var kilograms: Decimal

        func load(in units: Units) -> Decimal {
            units == .lb ? pounds : kilograms
        }
    }

    /// The 22 exercises the templates name. Loads by decision #21: barbell compounds the empty bar (45 / 20),
    /// the deadlift 95 / 40, an EZ-bar curl 25 / 10; dumbbells 15 / 7.5 compound and 10 / 5 isolation; cable
    /// 30 / 15 compound, 20 / 10 isolation, 10 / 5 small raises; machine 40 / 20, 20 / 10 and 10 / 5 likewise;
    /// weighted dips and pull-ups +10 / +5.
    static let catalogRows: [String: CatalogRow] = [
        "Barbell Bench Press": CatalogRow(equipment: .barbell, pounds: 45, kilograms: 20),
        "Incline DB Press": CatalogRow(equipment: .dumbbell, pounds: 15, kilograms: dec("7.5")),
        "Low-to-High Cable Fly": CatalogRow(equipment: .cable, pounds: 20, kilograms: 10),
        "Weighted Dip": CatalogRow(equipment: .bodyweight, pounds: 10, kilograms: 5),
        "Barbell Row": CatalogRow(equipment: .barbell, pounds: 45, kilograms: 20),
        "Chest-Supported Row": CatalogRow(equipment: .machine, pounds: 40, kilograms: 20),
        "Lat Pulldown": CatalogRow(equipment: .cable, pounds: 30, kilograms: 15),
        "Weighted Pull-Up": CatalogRow(equipment: .bodyweight, pounds: 10, kilograms: 5),
        "Overhead Press": CatalogRow(equipment: .barbell, pounds: 45, kilograms: 20),
        "Cable Lateral Raise": CatalogRow(equipment: .cable, pounds: 10, kilograms: 5),
        "Rear Delt Fly": CatalogRow(equipment: .machine, pounds: 10, kilograms: 5),
        "Back Squat": CatalogRow(equipment: .barbell, pounds: 45, kilograms: 20),
        "Front Squat": CatalogRow(equipment: .barbell, pounds: 45, kilograms: 20),
        "Romanian Deadlift": CatalogRow(equipment: .barbell, pounds: 45, kilograms: 20),
        "Deadlift": CatalogRow(equipment: .barbell, pounds: 95, kilograms: 40),
        "Leg Press": CatalogRow(equipment: .machine, pounds: 40, kilograms: 20),
        "Seated Leg Curl": CatalogRow(equipment: .machine, pounds: 20, kilograms: 10),
        "Standing Calf Raise": CatalogRow(equipment: .machine, pounds: 20, kilograms: 10),
        "Barbell Curl": CatalogRow(equipment: .barbell, pounds: 25, kilograms: 10),
        "Incline DB Curl": CatalogRow(equipment: .dumbbell, pounds: 10, kilograms: 5),
        "Cable Triceps Pushdown": CatalogRow(equipment: .cable, pounds: 20, kilograms: 10),
        "Overhead Cable Extension": CatalogRow(equipment: .cable, pounds: 20, kilograms: 10)
    ]

    /// Decisions #9 and #22: lb 5 for a barbell or kettlebell and 2.5 otherwise; kg 2.5 for a barbell, 2 for a
    /// kettlebell and 1.25 otherwise. In `units`' own numbers.
    static func step(_ equipment: Equipment, in units: Units) -> Decimal {
        switch (units, equipment) {
        case (.lb, .barbell), (.lb, .kettlebell): 5
        case (.lb, _), (.kg, .barbell): dec("2.5")
        case (.kg, .kettlebell): 2
        case (.kg, _): dec("1.25")
        }
    }

    static func weight(_ value: Decimal, in units: Units) -> Weight {
        units == .lb ? .pounds(value) : .kilograms(value)
    }

    /// Every exercise name a split's days use.
    static func exerciseNames(_ days: DaysPerWeek) -> Set<String> {
        Set(split(days).days.flatMap(\.lifts).map(\.exercise))
    }
}

// MARK: - Spec §7.2 and decision #3

extension BriefTemplates {
    /// What week `weekIndex` asks of a slot that has never been missed, in `units`' own numbers.
    struct ExpectedPrescription: Equatable, Sendable {
        var load: Decimal
        var sets: Int
        var reps: Int
        var rpe: Decimal
        var rest: Int
        var step: Decimal
    }

    /// Spec §7.2 with no misses, so `adv = weekIndex`. Linear adds a step a week; double climbs `reps` to
    /// `repsHi` and then adds a step; fixed holds. The deload week (decision #3) takes 85 % of the load rounded
    /// to the step (a tie away from zero, ADR-007), one set fewer (at least 1) and RPE − 2 (at least 5).
    static func prescription(
        _ slot: ExpectedSlot,
        weekIndex: Int,
        isDeload: Bool,
        units: Units
    ) throws -> ExpectedPrescription {
        let row = try #require(catalogRows[slot.exercise], "\(slot.exercise) is not a template exercise")
        let step = step(row.equipment, in: units)
        let start = row.load(in: units)
        let scheme = slot.scheme
        var load = start
        var reps = scheme.reps
        switch scheme.progression {
        case .linear:
            load = start + step * Decimal(weekIndex)
        case .double:
            let span = scheme.repsHi - scheme.reps + 1
            load = start + step * Decimal(weekIndex / span)
            reps = scheme.reps + weekIndex % span
        case .fixed:
            break
        }
        guard isDeload else {
            return ExpectedPrescription(
                load: load, sets: scheme.sets, reps: reps, rpe: scheme.rpe, rest: scheme.rest, step: step
            )
        }
        return ExpectedPrescription(
            load: reduced(load, step: step),
            sets: max(1, scheme.sets - 1),
            reps: reps,
            rpe: max(5, scheme.rpe - 2),
            rest: scheme.rest,
            step: step
        )
    }

    /// Rules 12 and 15: 85 % of `load`, to the nearest `step` (a tie away from zero).
    static func reduced(_ load: Decimal, step: Decimal) -> Decimal {
        decimalRounded(load * dec("0.85") / step) * step
    }

    /// Decision #14: every set takes 42 s of work; a slot on its own rests after each set, and slots joined
    /// as a superset rest once a round, for the longest of their rests. A drop set is one more set, and one
    /// more round. Whole minutes, half up (rule 37's `round`).
    static func minutes(_ slots: [ExpectedSlot], sets: [Int]) -> Int {
        var seconds = 0
        var block: [Int] = []
        func close() {
            let rounds = (block.map { sets[$0] }.max() ?? 0) + (block.map { slots[$0].drop }.max() ?? 0)
            seconds += rounds * (block.map { slots[$0].scheme.rest }.max() ?? 0)
            block = []
        }
        for index in slots.indices {
            if !slots[index].superset {
                close()
            }
            block.append(index)
            seconds += (sets[index] + slots[index].drop) * 42
        }
        close()
        return (seconds + 30) / 60
    }
}
