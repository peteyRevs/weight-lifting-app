import Foundation

/// Week-by-week prescriptions (spec §7.2, rules 9–12; decision #3).
public enum ProgressionRules {
    /// Rules 12 and 15: deload and drop-set loads are × 0.85 (built exactly, not from a float literal).
    static let reductionFactor = Decimal(sign: .plus, exponent: -2, significand: 85)

    /// Spec §7.2. `adv` = count of `i < weekIndex` with `i ∉ slot.misses`;
    /// `held` = `(weekIndex − 1) ∈ misses`.
    /// - linear (rule 9): `load = start + step × adv`, `reps = slot.reps`.
    /// - double (rule 10): `span = max(1, repsHi − reps + 1)`, `load = start + step × ⌊adv / span⌋`,
    ///   `reps = slot.reps + adv mod span`.
    /// - fixed (rule 11): `load = start`, `reps = slot.reps`.
    /// - deload week (rule 12, decision #3): `load = (load × 0.85).rounded(toStep: step)`,
    ///   `sets = max(1, sets − 1)`, `rpe = max(5, rpe − 2)`.
    ///
    /// `start = slot.startLoad ?? exercise.startLoad(in: units)` and
    /// `step = slot.step ?? exercise.equipment.defaultStep(in: units)` (rule 1, decision #9).
    /// `weekIndex` drives advancement and HELD; `week` supplies only `isDeload`. Pass the block's
    /// week at `weekIndex` (`week.index == weekIndex`); the pair is not cross-checked.
    public static func prescribe(
        week: Week,
        weekIndex: Int,
        slot: Slot,
        exercise: Exercise,
        units: Units
    ) -> Prescription {
        let advancement = (0 ..< max(0, weekIndex)).count { !slot.misses.contains($0) }
        let start = slot.startLoad ?? exercise.startLoad(in: units)
        let step = slot.step ?? exercise.equipment.defaultStep(in: units)
        var load: Weight
        var reps = slot.reps
        switch slot.progression {
        case .linear:
            load = start.advanced(bySteps: advancement, of: step)
        case .double:
            let span = max(1, slot.repsHi - slot.reps + 1)
            load = start.advanced(bySteps: advancement / span, of: step)
            reps = slot.reps + advancement % span
        case .fixed:
            load = start
        }
        var sets = slot.sets
        var rpe = slot.rpe
        if week.isDeload {
            load = load.scaled(by: reductionFactor).rounded(toStep: step)
            sets = max(1, sets - 1)
            rpe = rpe.deloaded()
        }
        return Prescription(
            load: load,
            sets: sets,
            reps: reps,
            rpe: rpe,
            rest: slot.rest,
            step: step,
            progression: slot.progression,
            isHeld: slot.misses.contains(weekIndex - 1),
            isDeload: week.isDeload
        )
    }
}
