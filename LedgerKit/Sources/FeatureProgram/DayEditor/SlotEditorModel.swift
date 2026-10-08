import LedgerDomain

/// The panel under the open exercise, as `SlotEditorPresentation` builds it: the shown week's prescription,
/// the stepper fields, the progression, the drop set, the loads of every week, and the slot's actions. A
/// control that could do nothing is absent, but a stepper, which offers both directions at its limit.
nonisolated struct SlotEditorModel: Equatable, Sendable {
    /// What needs the exercise to be written. Nil for a slot whose exercise is not stored, which can still be
    /// moved, joined, broken out and removed.
    let details: Details?
    /// "Break out" when the slot is joined to the one before it, "Superset with next" when the one after it
    /// can be joined to it: none, either, or both in this order.
    let supersetActions: [DayEditorModel.Control]
    /// "Move up"; nil when nothing stands above the slot or its superset.
    let moveUp: DayEditorModel.Control?
    /// "Move down"; nil when nothing stands below.
    let moveDown: DayEditorModel.Control?
    /// "Remove".
    let remove: DayEditorModel.Control

    struct Details: Equatable, Sendable {
        let week: WeekLine
        /// Sets, reps, the top of the range under double progression, start load, target RPE, rest.
        let fields: [Field]
        let progression: ProgressionPicker
        let dropSet: DropSet
        let strip: WeekStrip
    }
}

// MARK: - The fields

nonisolated extension SlotEditorModel {
    /// One stepper: to VoiceOver one adjustable element, `spokenLabel` with `value`.
    struct Field: Equatable, Sendable, Identifiable {
        /// Which field it is: its identity among the steppers.
        let kind: SlotField.Kind
        /// "SETS", "REPS" or "REP FLOOR", "TOP OF RANGE", "START LOAD", "TARGET RPE", "REST".
        let label: String
        /// The slot's own value: "5", "50 lb", "8.5", "2:30".
        let value: String
        /// "Sets", "Reps" or "Rep floor", "Top of range", "Start load", "Target RPE", "Rest".
        let spokenLabel: String
        /// "−" and "+": each sets the field to the value one step away. Both are offered at the field's limit
        /// too, where the Domain holds the value.
        let decrement: DayEditorAction
        let increment: DayEditorAction

        var id: SlotField.Kind {
            kind
        }
    }

    struct ProgressionPicker: Equatable, Sendable {
        /// "PROGRESSION".
        let title: String
        /// "Linear", "Double", "Fixed": a radio group.
        let chips: [Chip]
        /// What the chosen progression does, as in "Adds a rep each week up to 12, then +2.5 lb back at 10."
        let note: String
    }

    struct Chip: Equatable, Sendable, Identifiable {
        let progression: Progression
        let title: String
        let isSelected: Bool
        /// Chooses this progression; nil on the selected chip, which has nothing to change.
        let action: DayEditorAction?

        var id: Progression {
            progression
        }
    }

    struct DropSet: Equatable, Sendable {
        /// "Drop set".
        let title: String
        /// "One extra set at −15% after the last working set.", or its wording when on.
        let note: String
        let isOn: Bool
        /// Turns the drop set to the other state.
        let action: DayEditorAction
    }
}

// MARK: - The prescription, week by week

nonisolated extension SlotEditorModel {
    /// The shown week's prescription.
    struct WeekLine: Equatable, Sendable {
        /// "WEEK 3", "WEEK 8 · DELOAD", or "WEEK 4 · HELD" when the week before was missed.
        let eyebrow: String
        let isDeload: Bool
        let isHeld: Bool
        /// "5 × 5 @ 185 lb · RPE 8".
        let line: String
    }

    /// The load of every week of the block.
    struct WeekStrip: Equatable, Sendable {
        /// "W1 50 · W2 50 · W3 50 · W4 52.5 · … · W8 47.5 (deload)": the entries, joined.
        let text: String
        /// One per week, in the block's order.
        let entries: [Entry]
    }

    struct Entry: Equatable, Sendable {
        /// "W4 52.5", "W8 47.5 (deload)", "W5 190 (held)".
        let text: String
        let isDeload: Bool
        let isHeld: Bool
        /// Whether this is the week the editor shows.
        let isShown: Bool
    }
}
