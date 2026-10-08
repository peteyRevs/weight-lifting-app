import Foundation
import LedgerDomain

/// The open exercise's stepper fields: each with its label, the slot's own value, and the two edits of "−"
/// and "+". The value one step away is `DayEditing.stepped`'s; this file adds no limit and no step.
nonisolated extension SlotEditorPresentation {
    /// Sets, reps, start load, target RPE and rest; under double progression the top of the range stands
    /// after reps, which then reads "REP FLOOR".
    static func fields(of slot: Slot, _ exercise: Exercise, _ context: Context) -> [SlotEditorModel.Field] {
        let kinds: [SlotField.Kind] = slot.progression == .double
            ? [.sets, .reps, .repsHi, .startLoad, .rpe, .rest]
            : [.sets, .reps, .startLoad, .rpe, .rest]
        return kinds.map { kind in
            let texts = texts(of: kind, slot, exercise, context)
            return SlotEditorModel.Field(
                kind: kind,
                label: texts.label,
                value: texts.value,
                spokenLabel: texts.spokenLabel,
                decrement: step(kind, .downward, slot, exercise, context),
                increment: step(kind, .upward, slot, exercise, context)
            )
        }
    }

    /// "−" or "+": the field set to the value one step away, which `DayEditing` works out here, once, from
    /// the slot on screen. The store sends the value and does not step again.
    static func step(
        _ kind: SlotField.Kind,
        _ direction: StepDirection,
        _ slot: Slot,
        _ exercise: Exercise,
        _ context: Context
    ) -> DayEditorAction {
        let field = DayEditing.stepped(kind, direction, of: slot, exercise: exercise, units: context.units)
        return context.action(.set(field, slot: slot.id))
    }

    /// A field's drawn label, its value as the slot holds it, and its spoken label.
    struct FieldTexts {
        let label: String
        let value: String
        let spokenLabel: String
    }

    static func texts(
        of kind: SlotField.Kind,
        _ slot: Slot,
        _ exercise: Exercise,
        _ context: Context
    ) -> FieldTexts {
        let number = IntegerFormatStyle<Int>.number.locale(context.locale)
        let units = context.units
        switch kind {
        case .sets:
            return FieldTexts(
                label: ProgramCopy.setsLabel,
                value: slot.sets.formatted(number),
                spokenLabel: ProgramCopy.setsSpoken
            )
        case .reps:
            let isFloor = slot.progression == .double
            return FieldTexts(
                label: isFloor ? ProgramCopy.repFloorLabel : ProgramCopy.repsLabel,
                value: slot.reps.formatted(number),
                spokenLabel: isFloor ? ProgramCopy.repFloorSpoken : ProgramCopy.repsSpoken
            )
        case .repsHi:
            return FieldTexts(
                label: ProgramCopy.topOfRangeLabel,
                value: slot.repsHi.formatted(number),
                spokenLabel: ProgramCopy.topOfRangeSpoken
            )
        case .startLoad:
            let start = slot.resolvedStartLoad(exercise: exercise, units: units).formatted(in: units)
            return FieldTexts(
                label: ProgramCopy.startLoadLabel,
                value: ProgramCopy.load(start, units: units, locale: context.locale),
                spokenLabel: ProgramCopy.startLoadSpoken
            )
        case .rpe:
            return FieldTexts(
                label: ProgramCopy.targetRPELabel,
                value: slot.rpe.label,
                spokenLabel: ProgramCopy.targetRPESpoken
            )
        case .rest:
            return FieldTexts(label: ProgramCopy.rest, value: slot.rest.label, spokenLabel: ProgramCopy.restSpoken)
        }
    }
}
