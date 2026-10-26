import Foundation
import LedgerDomain

/// The words of the sheet that creates or edits the lifter's own exercise (F12 S3), and the history's "Edit", in this
/// module's catalog with the Library's. The sheet's "New exercise" is the Library's button's own words
/// (`LibraryCopy.newExercise`), and its Equipment field the chips' row name (`LibraryCopy.equipmentRow`).
nonisolated extension LibraryCopy {
    // MARK: The sheet

    static var editExercise: String {
        String(localized: "Edit exercise", bundle: .module, comment: "Title of the sheet that edits one's own exercise")
    }

    static var edit: String {
        String(
            localized: "Edit",
            bundle: .module,
            comment: "Button in the bar of one's own exercise's history: opens the sheet that edits it"
        )
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Closes the exercise sheet without saving")
    }

    static var save: String {
        String(localized: "Save", bundle: .module, comment: "Saves the exercise the sheet holds")
    }

    // MARK: Fields

    static var nameField: String {
        String(localized: "Name", bundle: .module, comment: "Heading and placeholder of the exercise's name field")
    }

    static var primaryMuscleField: String {
        String(localized: "Primary muscle", bundle: .module, comment: "Heading of the chips of the main muscle worked")
    }

    static var secondaryMusclesField: String {
        String(
            localized: "Secondary muscles",
            bundle: .module,
            comment: "Heading of the chips of the other muscles worked; any number can be chosen"
        )
    }

    static var patternField: String {
        String(localized: "Movement pattern", bundle: .module, comment: "Heading of the chips of how the body moves")
    }

    // MARK: Problems

    static var enterAName: String {
        String(localized: "Enter a name.", bundle: .module, comment: "Under the name field when Save found it blank")
    }

    static var nameLength: String {
        String(
            localized: "Name must be 2–40 characters.",
            bundle: .module,
            comment: "Under the name field when Save found it too short or too long"
        )
    }

    static var nameHasControlCharacter: String {
        String(
            localized: "That name holds a character that can't be saved.",
            bundle: .module,
            comment: "Under the name field when Save found a tab, a line break or another control character in it"
        )
    }

    static var duplicateName: String {
        String(
            localized: "An exercise with that name already exists.",
            bundle: .module,
            comment: "Under the name field when Save found another exercise with the name"
        )
    }

    static var saveFailed: String {
        String(
            localized: "Couldn't save the exercise. Try again.",
            bundle: .module,
            comment: "Over Save when the exercise could not be stored"
        )
    }

    // MARK: Movement patterns

    /// A movement pattern's chip. The core's is the muscle group's word (`muscle(.core)`), one key in English.
    static func pattern(_ pattern: MovementPattern) -> String {
        switch pattern {
        case .horizontalPush: String(localized: "Horizontal push", bundle: .module, comment: "Movement pattern")
        case .horizontalPull: String(localized: "Horizontal pull", bundle: .module, comment: "Movement pattern")
        case .verticalPush: String(localized: "Vertical push", bundle: .module, comment: "Movement pattern")
        case .verticalPull: String(localized: "Vertical pull", bundle: .module, comment: "Movement pattern")
        case .squat: String(localized: "Squat", bundle: .module, comment: "Movement pattern")
        case .hinge: String(localized: "Hinge", bundle: .module, comment: "Movement pattern: a hip hinge")
        case .lunge: String(localized: "Lunge", bundle: .module, comment: "Movement pattern")
        case .carry: String(localized: "Carry", bundle: .module, comment: "Movement pattern: a loaded carry")
        case .isolation: String(
                localized: "Isolation",
                bundle: .module,
                comment: "Movement pattern: one joint, one muscle"
            )
        case .core: muscle(.core)
        }
    }
}
