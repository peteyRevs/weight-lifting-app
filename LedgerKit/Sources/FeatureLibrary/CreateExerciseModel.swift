import Foundation
import LedgerDomain

/// What a tap on the exercise sheet means, as a value (F12 S3): the store applies it and decides nothing. Each says
/// what becomes true, so one applied twice gives what one gives. "Cancel" is no action: the sheet's presenter takes
/// it down, and nothing is stored.
nonisolated enum CreateExerciseAction: Hashable, Sendable {
    /// The name field holds this text, as typed.
    case setName(String)
    case setEquipment(Equipment)
    /// The primary muscle is this one; it is never also a secondary one.
    case setPrimaryMuscle(MuscleGroup)
    /// This secondary muscle is chosen, or not.
    case setSecondaryMuscle(MuscleGroup, isOn: Bool)
    case setPattern(MovementPattern)
    /// "Save": stores the exercise once, unless a save is under way or done.
    case save
}

/// Why the sheet could not store the exercise: a rule of the name or the muscles, or a save that failed.
nonisolated enum CreateExerciseProblem: Equatable, Sendable {
    case invalid(CustomExerciseError)
    case failed
}

/// What `CreateExercisePresentation.make(_:)` reads: the store's draft and where its save stands.
nonisolated struct CreateExerciseInput: Sendable {
    var draft: CustomExerciseDraft
    /// The sheet edits a stored exercise ("Edit exercise") rather than creating one ("New exercise").
    var isEdit = false
    var isSaving = false
    var problem: CreateExerciseProblem?
    /// How many times Save has found a problem (finding S3-6).
    var problemNumber = 0
    var locale: Locale
}

/// Everything the exercise sheet draws and speaks (F12 S3). Every string is final, and every control carries the
/// action its tap means: the views draw the model and decide nothing.
nonisolated struct CreateExerciseModel: Equatable, Sendable {
    /// "New exercise" or "Edit exercise".
    let title: String
    let cancel: String
    let name: Name
    /// Equipment, primary muscle, secondary muscles and movement pattern, in that order.
    let groups: [ChipGroup]
    let foot: Foot
    /// Counts the problems Save has found, so that each one, the same as the last or not, is announced and the name's
    /// is scrolled into view (finding S3-6).
    let problemNumber: Int
    /// The line Save last found, under the name or over Save: what VoiceOver is told; nil with none.
    var announcement: String? {
        name.problem ?? foot.problem
    }

    /// The name field: its heading, which is also its placeholder and spoken label, the text as typed, and the rule
    /// Save found it breaks.
    struct Name: Equatable, Sendable {
        let label: String
        let text: String
        let problem: String?
    }

    enum Field: Hashable, Sendable {
        case equipment, primaryMuscle, secondaryMuscles, pattern
    }

    /// One field of chips under its heading. One chip is chosen, or any number when `allowsMany`.
    struct ChipGroup: Equatable, Sendable, Identifiable {
        let id: Field
        let title: String
        /// The secondary muscles: each chip is on or off by itself.
        let allowsMany: Bool
        let chips: [Chip]
    }

    struct Chip: Equatable, Sendable, Identifiable {
        /// The value the chip stands for, its raw value ("chest"): a chip keeps its identity when the primary muscle
        /// takes another out of the secondary muscles' row (finding S3-7).
        let id: String
        let title: String
        /// "Primary muscle: Chest": the chip with its field's name.
        let spokenLabel: String
        let isSelected: Bool
        let action: CreateExerciseAction
    }

    /// "Save", with the line of a save that failed over it. Its action is nil while a save runs.
    struct Foot: Equatable, Sendable {
        let title: String
        let problem: String?
        let action: CreateExerciseAction?
    }
}
