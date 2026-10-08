import Foundation
import LedgerDomain

/// The panel under the open exercise: the progression and its note, the drop set, and the slot's actions. The
/// stepper fields are in `+Fields`, the shown week's line and the loads of every week in `+Preview`.
///
/// It holds no limit, no step and no rule of a superset. A stepper's two actions carry the value
/// `DayEditing.stepped` gives for the slot on screen, which `DayEditing.set` holds within the field's range; a
/// move and a superset action are in the model only when `DayEditing`, asked, would change the day.
nonisolated enum SlotEditorPresentation {
    typealias Context = DayEditorPresentation.Context
    typealias Shown = DayEditorPresentation.Shown
    typealias Control = DayEditorModel.Control

    static func panel(of slot: Slot, _ shown: Shown?, _ context: Context) -> SlotEditorModel {
        SlotEditorModel(
            details: shown.map { details(of: slot, $0, context) },
            supersetActions: supersetActions(of: slot, context),
            moveUp: move(slot, .upward, title: ProgramCopy.moveUp, context),
            moveDown: move(slot, .downward, title: ProgramCopy.moveDown, context),
            remove: Control(
                title: ProgramCopy.remove,
                action: context.action(.remove(slot: slot.id), closesPanel: true)
            )
        )
    }

    static func details(of slot: Slot, _ shown: Shown, _ context: Context) -> SlotEditorModel.Details {
        SlotEditorModel.Details(
            week: weekLine(shown.prescription, context),
            fields: fields(of: slot, shown.exercise, context),
            progression: progression(of: slot, shown.exercise, context),
            dropSet: dropSet(of: slot, context),
            strip: strip(shown.weeks, context)
        )
    }

    // MARK: - Progression and drop set

    static func progression(
        of slot: Slot,
        _ exercise: Exercise,
        _ context: Context
    ) -> SlotEditorModel.ProgressionPicker {
        let chips = Progression.allCases.map { option in
            let isSelected = option == slot.progression
            return SlotEditorModel.Chip(
                progression: option,
                title: ProgramCopy.progression(option),
                isSelected: isSelected,
                action: isSelected ? nil : context.action(.setProgression(option, slot: slot.id))
            )
        }
        return SlotEditorModel.ProgressionPicker(
            title: ProgramCopy.progressionTitle,
            chips: chips,
            note: progressionNote(of: slot, exercise, context)
        )
    }

    /// What the slot's progression does, with the load it starts from and the step it adds, as the slot
    /// resolves them in the lifter's unit.
    static func progressionNote(of slot: Slot, _ exercise: Exercise, _ context: Context) -> String {
        let units = context.units
        let locale = context.locale
        let start = slot.resolvedStartLoad(exercise: exercise, units: units).formatted(in: units)
        let step = slot.resolvedStep(exercise: exercise, units: units).formatted(in: units)
        return switch slot.progression {
        case .linear:
            ProgramCopy.linearNote(step: step, start: start, units: units, locale: locale)
        case .double:
            ProgramCopy.doubleNote(top: slot.repsHi, step: step, floor: slot.reps, units: units, locale: locale)
        case .fixed:
            ProgramCopy.fixedNote(start: start, units: units, locale: locale)
        }
    }

    static func dropSet(of slot: Slot, _ context: Context) -> SlotEditorModel.DropSet {
        let isOn = slot.dropSets > 0
        return SlotEditorModel.DropSet(
            title: ProgramCopy.dropSet,
            note: isOn ? ProgramCopy.dropSetNoteOn : ProgramCopy.dropSetNoteOff,
            isOn: isOn,
            action: context.action(.setDropSet(!isOn, slot: slot.id))
        )
    }

    // MARK: - The slot's actions

    /// "Break out" takes the slot out of the superset it is joined to; "Superset with next" joins the slot
    /// after it, so its edit names that slot. Each is offered when it would change the day's groups, and both
    /// close the panel.
    static func supersetActions(of slot: Slot, _ context: Context) -> [Control] {
        var controls: [Control] = []
        let breakOut = SlotEdit.setSuperset(false, slot: slot.id)
        if context.rearranges(breakOut) {
            controls.append(Control(title: ProgramCopy.breakOut, action: context.action(breakOut, closesPanel: true)))
        }
        let slots = context.day.slots
        if let place = slots.firstIndex(where: { $0.id == slot.id }), slots.indices.contains(place + 1) {
            let join = SlotEdit.setSuperset(true, slot: slots[place + 1].id)
            if context.rearranges(join) {
                let action = context.action(join, closesPanel: true)
                controls.append(Control(title: ProgramCopy.supersetWithNext, action: action))
            }
        }
        return controls
    }

    /// "Move up" or "Move down", when the Domain's move would change the day; the panel stays open on the
    /// moved exercise.
    static func move(_ slot: Slot, _ direction: MoveDirection, title: String, _ context: Context) -> Control? {
        let edit = SlotEdit.move(direction, slot: slot.id)
        return context.rearranges(edit) ? Control(title: title, action: context.action(edit)) : nil
    }
}
