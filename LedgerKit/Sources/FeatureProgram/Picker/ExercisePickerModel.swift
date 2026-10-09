import LedgerDomain

/// Everything the exercise library sheet draws and speaks, as `ExercisePickerPresentation.make(_:)` builds
/// it. Every string is final and every control carries the `ExercisePickerAction` its tap means: the views
/// draw the model and decide nothing.
nonisolated struct ExercisePickerModel: Equatable, Sendable {
    /// "Exercise library".
    let title: String
    /// "Cancel": closes the sheet.
    let cancel: Control
    let search: Search
    /// "All, Chest, Back, Shoulders, Legs, Arms".
    let muscles: ChipRow
    /// "All, Barbell, Dumbbell, Cable, Machine, Bodyweight".
    let equipment: ChipRow
    let content: Content
    let foot: Foot

    /// A button: its title, and the action of its tap.
    struct Control: Equatable, Sendable {
        let title: String
        let action: ExercisePickerAction
    }

    struct Search: Equatable, Sendable {
        /// "Search exercises": the field's placeholder and its spoken label.
        let placeholder: String
        /// The field's text, as the input holds it. A view sends `ExercisePickerAction.setQuery(_:)` with
        /// the text as it is typed.
        let query: String
    }

    /// What stands under the chips.
    enum Content: Equatable, Sendable {
        /// The exercises that pass the filter, in `ExerciseSearch`'s order. Never empty.
        case rows([Row])
        /// No exercise passes the filter, or none is stored.
        case nothingMatches(Empty)
    }

    struct Empty: Equatable, Sendable {
        /// "Nothing matches that filter."
        let message: String
        /// "Clear filters".
        let clear: Control
    }

    /// The button pinned under the list.
    struct Foot: Equatable, Sendable {
        /// "Select exercises to add", "Add 1 exercise", "Add 3 exercises". It is what VoiceOver reads too.
        let title: String
        /// Adds the picks, in the order picked. Nil with no pick: the button is disabled.
        let action: ExercisePickerAction?
    }
}

// MARK: - The chips

nonisolated extension ExercisePickerModel {
    /// One row of filter chips. Exactly one chip is selected.
    struct ChipRow: Equatable, Sendable {
        /// "Muscle", "Equipment": what VoiceOver calls the row. It is not drawn.
        let spokenLabel: String
        let chips: [Chip]
    }

    struct Chip: Equatable, Sendable, Identifiable {
        /// The chip's place in its row, 0 for "All".
        let id: Int
        /// "All", "Chest", "Barbell".
        let title: String
        /// "Muscle: Chest": the chip with its row's name, since both rows have an "All".
        let spokenLabel: String
        let isSelected: Bool
        /// Sets the row's filter to this chip. The selected chip carries it too: it changes nothing.
        let action: ExercisePickerAction
    }
}

// MARK: - The exercises

nonisolated extension ExercisePickerModel {
    /// One exercise that passes the filter. To VoiceOver its label is `name` and its value `line`; that it is
    /// picked is said by the selected state, which the view sets from `isPicked`.
    struct Row: Equatable, Sendable, Identifiable {
        let id: ExerciseID
        /// The exercise's name, as stored.
        let name: String
        /// "Machine · Back": the equipment, then the primary muscle.
        let detail: String
        /// "already in this day" when the day holds the exercise, else nil: apart from `detail`, for a
        /// view that draws the mark in its own style.
        let inDayMark: String?
        /// `detail`, then the mark when there is one: "Machine · Back · already in this day".
        let line: String
        let isPicked: Bool
        /// "2": the exercise's place among the picks, counted from 1. Nil when it is not picked.
        let pickMark: String?
        /// Picks the exercise, or takes it out of the picks when it is picked.
        let action: ExercisePickerAction
    }
}
