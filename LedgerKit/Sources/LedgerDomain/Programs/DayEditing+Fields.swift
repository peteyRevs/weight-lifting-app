import Foundation

// MARK: - Fields (rules 1–3 and 6)

public extension DayEditing {
    /// Sets one field of a slot. The value is first clamped to the field's range: sets 1…12, reps 1…30, top of
    /// range 2…40, RPE 5…10 on the half, rest 30…300 s on the 15, start load never below zero. Then the top
    /// of the range is kept above reps (rule 2): reps set at or above the top make the top `reps + 1`, and a
    /// top set at or below reps becomes `reps + 1`. An RPE or a rest off its step goes to the nearest step; a
    /// start load is stored as given, on a step or not.
    static func set(_ field: SlotField, slot: SlotID, in day: DayTemplate) -> DayTemplate {
        editing(day, slot: slot) { slots, index in
            slots[index] = applying(field, to: slots[index])
        }
    }

    /// The field one step away from the slot's value: ± 1 for sets, reps and the top of the range, ± 0.5 for
    /// RPE, ± 15 s for rest, and for the start load the next multiple of its step on that side, never below
    /// zero. No range is applied here: a stepper button sends `set(stepped(…))`, and `set` holds the value at
    /// the field's limit. `exercise` and `units` matter to the start load alone.
    static func stepped(
        _ kind: SlotField.Kind,
        _ direction: StepDirection,
        of slot: Slot,
        exercise: Exercise,
        units: Units
    ) -> SlotField {
        let sign = direction == .upward ? 1 : -1
        return switch kind {
        case .sets: .sets(saturatingSum(slot.sets, sign))
        case .reps: .reps(saturatingSum(slot.reps, sign))
        case .repsHi: .repsHi(saturatingSum(slot.repsHi, sign))
        case .rpe: .rpe(slot.rpe.value + Decimal(sign) * RPE.step)
        case .rest: .restSeconds(slot.rest.seconds + sign * RestDuration.stepSeconds)
        case .startLoad: .startLoad(steppedStartLoad(direction, of: slot, exercise: exercise, units: units))
        }
    }

    /// `slot` with `field` set: the clamp, then the coupling of reps and the top of the range.
    private static func applying(_ field: SlotField, to slot: Slot) -> Slot {
        var edited = slot
        switch field {
        case let .sets(value):
            edited.sets = clamped(value, to: Slot.setsRange)
        case let .reps(value):
            edited.reps = clamped(value, to: Slot.repsRange)
            edited.repsHi = max(edited.repsHi, edited.reps + 1)
        case let .repsHi(value):
            edited.repsHi = max(clamped(value, to: Slot.repsHiRange), saturatingSum(edited.reps, 1))
        case let .rpe(value):
            edited.rpe = RPE(clamping: value)
        case let .restSeconds(value):
            edited.rest = RestDuration(clampingSeconds: value)
        case let .startLoad(value):
            edited.startLoad = max(value, .zero)
        }
        return edited
    }

    /// Rule 6: the multiple of the step next to the slot's start load on the side asked for, never below
    /// zero. A load on a multiple moves one step; a load between two multiples (180 lb read in kilograms is
    /// 81.6) goes to the one above or the one below (82.5 or 80). The load and the step fall back to the
    /// exercise's start load and the equipment's step in `units`, as a prescription's do (spec §7.2).
    private static func steppedStartLoad(
        _ direction: StepDirection,
        of slot: Slot,
        exercise: Exercise,
        units: Units
    ) -> Weight {
        let load = slot.resolvedStartLoad(exercise: exercise, units: units)
        let step = slot.resolvedStep(exercise: exercise, units: units)
        let multiple = load.rounded(toStep: step, direction == .upward ? .up : .down)
        let isPastLoad = direction == .upward ? multiple > load : multiple < load
        let next = isPastLoad ? multiple : multiple.advanced(bySteps: direction == .upward ? 1 : -1, of: step)
        return max(next, .zero)
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
