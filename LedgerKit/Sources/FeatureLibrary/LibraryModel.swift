import LedgerDomain

/// Everything the Library draws and speaks, as `LibraryPresentation.make(_:filter:)` builds it. Every string is
/// final and every control carries the `LibraryAction` its tap means: the views draw the model and decide nothing.
nonisolated struct LibraryModel: Equatable, Sendable {
    /// "Library": the screen's heading.
    let title: String
    /// "New exercise", in the header.
    let newExercise: Control
    let search: Search
    /// "All, Chest, Back, Shoulders, Legs, Arms".
    let muscles: ChipRow
    /// "All, Barbell, Dumbbell, Cable, Machine, Bodyweight".
    let equipment: ChipRow
    let content: Content

    /// A button: its title, and the action of its tap.
    struct Control: Equatable, Sendable {
        let title: String
        let action: LibraryAction
    }

    struct Search: Equatable, Sendable {
        /// "Search 224 exercises", counting every live exercise: the field's placeholder and its spoken label.
        let placeholder: String
        /// The field's text, as the store holds it.
        let query: String
    }

    /// What stands under the chips.
    enum Content: Equatable, Sendable {
        /// RECENTLY LOGGED, when an exercise of it passes the filter, then ALL EXERCISES. Never empty.
        case sections([Section])
        /// No exercise passes the filter: "Nothing matches that filter." and "Clear filters".
        case nothingMatches(Message)
        /// No exercise is stored at all (the catalog failed to seed and none is the lifter's own): "No
        /// exercises yet." and "New exercise" (Pete's question 8, A).
        case noExercises(Message)
    }

    struct Message: Equatable, Sendable {
        let text: String
        let control: Control
    }

    /// The two sections, in this order.
    enum SectionKind: Hashable, Sendable {
        case recent, all
    }

    struct Section: Equatable, Sendable, Identifiable {
        let id: SectionKind
        /// "RECENTLY LOGGED", "ALL EXERCISES": a heading.
        let title: String
        /// Never empty.
        let rows: [Row]
    }

    /// One exercise, one button. To VoiceOver its label is `name` and its value `spokenValue`.
    struct Row: Equatable, Sendable, Identifiable {
        let id: ExerciseID
        /// The exercise's name, as stored.
        let name: String
        /// "Barbell · Chest · 34 sessions" in RECENTLY LOGGED, "Barbell · Chest" in ALL EXERCISES, and
        /// " · Custom" after either for the lifter's own exercise.
        let meta: String
        /// The best set's weight in the lifter's units ("195"), or "—" with none.
        let record: String
        /// "Barbell, Chest, 34 sessions, PR 195 pounds": the meta's parts, then the PR when there is one.
        let spokenValue: String
        /// Opens the exercise's history.
        let action: LibraryAction
    }

    /// One row of filter chips. Exactly one chip is selected.
    struct ChipRow: Equatable, Sendable {
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
        let action: LibraryAction
    }
}
