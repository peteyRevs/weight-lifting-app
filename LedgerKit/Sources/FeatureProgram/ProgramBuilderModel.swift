import LedgerDomain

/// Everything the Program builder draws and speaks, as `ProgramPresentation.make(_:)` builds it. Every string
/// is final and every control carries the `ProgramBuilderAction` its tap means: the views draw the model and
/// decide nothing.
nonisolated struct ProgramBuilderModel: Equatable, Sendable {
    let header: Header
    let block: Block
    let week: SelectedWeek
    let days: TrainingDays
    /// The notice the store is showing, as its text; nil when there is none.
    let notice: String?

    struct Header: Equatable, Sendable {
        /// "MY PROGRAM".
        let eyebrow: String
        /// The program's name as stored. It seeds the name field and is not what the field shows while the
        /// lifter types: the field shows a draft that the view itself keeps (`NameField`; the store keeps
        /// none), and sends `ProgramBuilderAction.rename(_:)` with the draft's text. The stored name is the
        /// cleaned one, so a field bound to it would lose a trailing space and could not be emptied.
        let name: String
        /// "Program name": the field's placeholder and its spoken label.
        let namePlaceholder: String
    }

    /// A button: its title, and the action of its tap. A nil action is a disabled button.
    struct Control: Equatable, Sendable {
        let title: String
        let action: ProgramBuilderAction?
    }
}

// MARK: - The block

nonisolated extension ProgramBuilderModel {
    /// The block's length and its weeks.
    struct Block: Equatable, Sendable {
        /// "BLOCK · 8 WEEKS".
        let title: String
        /// "Block length" and "8 weeks": what VoiceOver reads for "−" and "+" as one adjustable element.
        let spokenLabel: String
        let spokenValue: String
        /// "−": the edit that removes the last week, or the notice that says why it cannot go.
        let removeWeek: ProgramBuilderAction
        /// "+".
        let addWeek: ProgramBuilderAction
        /// One per week, in the block's order.
        let chips: [WeekChip]
    }

    struct WeekChip: Equatable, Sendable {
        /// "W1".
        let title: String
        /// "4 DAYS", or "DELOAD" for a deload week.
        let subtitle: String
        let isDeload: Bool
        let isSelected: Bool
        /// "Week 1".
        let spokenLabel: String
        /// "4 days", or "Deload".
        let spokenValue: String
        /// Selects this week.
        let action: ProgramBuilderAction
    }
}

// MARK: - The selected week

nonisolated extension ProgramBuilderModel {
    struct SelectedWeek: Equatable, Sendable {
        /// "WEEK 3", or "WEEK 3 · DELOAD".
        let title: String
        /// "Tap to assign"; nil in a program with no training day, where the strip offers nothing.
        let hint: String?
        /// The seven weekdays, from the settings' week start.
        let cells: [Cell]
        /// "Copy week 2"; "First week", disabled, on the first week.
        let copyPrevious: Control
        /// "Apply to later weeks"; nil on the last week, which has none.
        let applyToLater: Control?
        let deload: Toggle
    }

    /// One weekday of the schedule strip.
    struct Cell: Equatable, Sendable {
        /// Which weekday the cell is: its identity in the strip.
        let weekday: Weekday
        /// "T": the weekday's letter in the injected calendar and locale.
        let letter: String
        /// The scheduled day's tag, as in "UA", or "REST".
        let label: String
        let isRest: Bool
        /// "Tuesday".
        let spokenLabel: String
        /// "Rest", or the scheduled day's short title, as in "Upper A".
        let spokenValue: String
        /// What the tap does, for VoiceOver; nil when the cell offers nothing.
        let spokenHint: String?
        /// What the weekday becomes on a tap: the next day of its cycle, or rest after the last. Nil in a
        /// program with no training day, where there is nothing to assign: the cell is drawn, not a button.
        let action: ProgramBuilderAction?
    }

    /// A button that is on or off; VoiceOver reads it as selected when on.
    struct Toggle: Equatable, Sendable {
        let title: String
        let isOn: Bool
        let action: ProgramBuilderAction
    }
}

// MARK: - The training days

nonisolated extension ProgramBuilderModel {
    struct TrainingDays: Equatable, Sendable {
        /// "TRAINING DAYS".
        let title: String
        /// "4 days · 58 sets a week".
        let summary: String
        /// "Shared by every week. The schedule above decides which day you train, and when."
        let helper: String
        /// One per day, in the program's order.
        let cards: [DayCard]
        /// "+ Add training day".
        let addDay: Control
    }

    struct DayCard: Equatable, Sendable, Identifiable {
        let id: DayTemplateID
        /// "UA".
        let tag: String
        /// "Upper A — Push focus".
        let name: String
        /// "5 exercises · 18 sets · ~39 min", or "No exercises yet".
        let meta: String
        /// The short names of the first four exercises, then "+2" for the rest. Not spoken. A chip is
        /// identified by its place: two can read the same (an exercise twice, two that are not stored).
        let chips: [String]
        /// The name and the meta line again: what VoiceOver reads as the card's label and value.
        let spokenLabel: String
        let spokenValue: String
        /// Opens the Day editor on this day.
        let action: ProgramBuilderAction
    }
}
