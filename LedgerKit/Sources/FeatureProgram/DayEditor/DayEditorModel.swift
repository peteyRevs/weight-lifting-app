import LedgerDomain

/// Everything the Day editor draws and speaks, as `DayEditorPresentation.make(_:)` builds it. Every string is
/// final and every control carries the `DayEditorAction` its tap means: the views draw the model and decide
/// nothing.
nonisolated enum DayEditorModel: Equatable, Sendable {
    /// The program holds the day.
    case editing(Content)
    /// The program no longer holds the day (it was deleted here or elsewhere): there is nothing to draw, and
    /// the store emits `ProgramRoute.closeDay`.
    case dayIsGone

    struct Content: Equatable, Sendable, Identifiable {
        /// The day's id: what the name field hands `DayEditorAction.rename(_:day:)`.
        let id: DayTemplateID
        let header: Header
        /// The day's exercises in their superset groups, in order; an exercise on its own is a group of one.
        let groups: [Group]
        /// "+ Add exercise from library".
        let addExercise: Control
        let deleteDay: DeleteDay
    }

    /// A button: its title, and the action of its tap. A control that could do nothing is not in the model.
    struct Control: Equatable, Sendable {
        let title: String
        let action: DayEditorAction
    }

    struct Header: Equatable, Sendable {
        /// "Program": back to the builder.
        let back: Control
        /// "DAY 1 OF 4".
        let position: String
        /// "Done": back to the builder.
        let done: Control
        /// The day's name as stored. It seeds the name field and is not what the field shows while the lifter
        /// types: a view binds the field to a draft the store keeps, and sends
        /// `DayEditorAction.rename(_:day:)` with the draft's text.
        let name: String
        /// "Day name": the field's placeholder and its spoken label.
        let nameLabel: String
        /// "UA". Not editable.
        let tag: String
        /// "Week 1 · 5 exercises · 18 sets · ~39 min": the shown week's prescription, so a deload week counts
        /// its own sets and minutes. "Week 1 · No exercises yet" for a day with no exercise.
        let meta: String
    }
}

// MARK: - The exercises

nonisolated extension DayEditorModel {
    /// One superset, or one exercise on its own.
    struct Group: Equatable, Sendable, Identifiable {
        /// Nil for an exercise on its own.
        let header: SupersetHeader?
        /// Never empty.
        let rows: [Row]

        /// The id of the group's first slot.
        var id: SlotID? {
            rows.first?.id
        }
    }

    struct SupersetHeader: Equatable, Sendable {
        /// "SUPERSET".
        let title: String
        /// "2 exercises back to back · rest after B".
        let note: String
        /// "Superset": what VoiceOver reads as the heading; the note is its value.
        let spokenLabel: String
    }

    /// One exercise of the day, closed or open.
    struct Row: Equatable, Sendable, Identifiable {
        /// The slot's id.
        let id: SlotID
        /// "1", or "4A" in a superset.
        let index: String
        /// The exercise's name, or a dash when it is not stored.
        let name: String
        /// "Barbell · +5/wk · RPE 8 · 2:30 rest"; the last part is "no rest" for every member of a superset but
        /// the last. Without the equipment and the progression when the exercise is not stored.
        let sub: String
        /// "5×5": the shown week's sets and reps.
        let scheme: String
        /// "185 lb": the shown week's load in the lifter's unit. Nil when the exercise is not stored.
        let load: String?
        /// Whether the slot ends on a drop set: the sub line then says "drop".
        let hasDropSet: Bool
        let isOpen: Bool
        /// "4A, Lat Pulldown".
        let spokenLabel: String
        /// The scheme, the load and the sub line, as "3×12 · 100 lb · Cable · Reps 12–14 · RPE 9 · no rest".
        let spokenValue: String
        /// Opens the row's panel, or closes it when it is open.
        let action: DayEditorAction
        /// The panel under the row: not nil exactly when the row is open.
        let panel: SlotEditorModel?
    }
}

// MARK: - Delete day

nonisolated extension DayEditorModel {
    struct DeleteDay: Equatable, Sendable {
        /// "Delete day": the button at the foot. It presents the confirmation.
        let title: String
        let confirmation: Confirmation
    }

    struct Confirmation: Equatable, Sendable {
        /// "Delete Lower B?".
        let title: String
        /// "It's scheduled in 8 weeks. Those days become rest."; nil for a day no week schedules.
        let message: String?
        /// "Delete": the edit that removes the day. The next model is `dayIsGone`.
        let confirm: Control
        /// "Cancel": dismisses the confirmation and changes nothing.
        let cancel: String
    }
}
