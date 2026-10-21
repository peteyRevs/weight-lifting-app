import Foundation
import LedgerDomain

/// The texts of the exercise library sheet: its title, the search field, the filter chips, an exercise's
/// row, the empty state and the foot (`ProgramCopy`; standards §7). The equipment names and "Cancel" are in
/// `ProgramCopy+DayEditor.swift`; an exercise's name is data.
nonisolated extension ProgramCopy {
    // MARK: Header and search

    static var exerciseLibrary: String {
        String(
            localized: "Exercise library",
            bundle: .module,
            comment: "Title of the sheet that adds exercises to a day"
        )
    }

    static var searchExercises: String {
        String(
            localized: "Search exercises",
            bundle: .module,
            comment: "Placeholder and spoken label of the exercise library's search field"
        )
    }

    static var search: String {
        String(
            localized: "Search",
            bundle: .module,
            comment: "The exercise library's search field's placeholder where Search exercises does not fit the field"
        )
    }

    // MARK: Filter chips

    static var allChip: String {
        String(
            localized: "All",
            bundle: .module,
            comment: "First filter chip of the exercise library, in the muscle row and in the equipment row: no filter"
        )
    }

    static var muscleRow: String {
        String(localized: "Muscle", bundle: .module, comment: "Spoken name of the exercise library's muscle chips")
    }

    static var equipmentRow: String {
        String(
            localized: "Equipment",
            bundle: .module,
            comment: "Spoken name of the exercise library's equipment chips"
        )
    }

    /// "Muscle: Chest", "Equipment: All".
    static func spokenChip(row: String, title: String, locale: Locale) -> String {
        String(
            localized: "\(row): \(title)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of a filter chip: Muscle or Equipment, then the chip's own text"
        )
    }

    /// A muscle chip's text. "Legs" and "Arms" each stand for several muscle groups; the others are the
    /// group's own name.
    static func muscleFilter(_ filter: ExerciseSearch.MuscleFilter) -> String {
        switch filter {
        case .chest: muscle(.chest)
        case .back: muscle(.back)
        case .shoulders: muscle(.shoulders)
        case .legs: String(localized: "Legs", bundle: .module, comment: "Filter chip: every muscle of the legs")
        case .arms: String(localized: "Arms", bundle: .module, comment: "Filter chip: every muscle of the arms")
        }
    }

    /// The name of an exercise's primary muscle, on its row; three of them are filter chips too. The lint's
    /// limit of ten branches is waived on the line: the eleven groups each have their lookup.
    static func muscle(_ group: MuscleGroup) -> String { // swiftlint:disable:this cyclomatic_complexity - §7 lookups
        switch group {
        case .chest: String(localized: "Chest", bundle: .module, comment: "Muscle group, also a filter chip")
        case .back: String(localized: "Back", bundle: .module, comment: "Muscle group, also a filter chip")
        case .shoulders: String(localized: "Shoulders", bundle: .module, comment: "Muscle group, also a filter chip")
        case .quads: String(localized: "Quads", bundle: .module, comment: "Muscle group: the quadriceps")
        case .hamstrings: String(localized: "Hamstrings", bundle: .module, comment: "Muscle group")
        case .glutes: String(localized: "Glutes", bundle: .module, comment: "Muscle group")
        case .calves: String(localized: "Calves", bundle: .module, comment: "Muscle group")
        case .biceps: String(localized: "Biceps", bundle: .module, comment: "Muscle group")
        case .triceps: String(localized: "Triceps", bundle: .module, comment: "Muscle group")
        case .forearms: String(localized: "Forearms", bundle: .module, comment: "Muscle group")
        case .core: String(localized: "Core", bundle: .module, comment: "Muscle group: the abdominals and lower back")
        }
    }

    // MARK: An exercise's row

    static var alreadyInThisDay: String {
        String(
            localized: "already in this day",
            bundle: .module,
            comment: "On an exercise's row in the library, after its equipment and muscle: the day holds it already"
        )
    }

    // MARK: Nothing matches

    static var nothingMatches: String {
        String(
            localized: "Nothing matches that filter.",
            bundle: .module,
            comment: "Shown in the exercise library when the search and the two chip rows leave no exercise"
        )
    }

    static var clearFilters: String {
        String(
            localized: "Clear filters",
            bundle: .module,
            comment: "Button under: Nothing matches that filter. It empties the search and sets both chip rows to All"
        )
    }

    // MARK: The foot

    static var selectExercisesToAdd: String {
        String(
            localized: "Select exercises to add",
            bundle: .module,
            comment: "The exercise library's button while no exercise is picked; it is disabled"
        )
    }

    /// "Add 1 exercise", "Add 3 exercises".
    static func addExercises(_ count: Int, locale: Locale) -> String {
        String(
            localized: "Add \(count) exercises",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "The exercise library's button: adds the picked exercises to the day"
        )
    }
}
