import Foundation
import LedgerDomain

/// FeatureLibrary's copy (standards §7): every text the Library shows or speaks is looked up here, in this module's
/// `Resources/Localizable.xcstrings`, whose keys are the English text. No other file of the module holds a
/// user-facing literal or a lookup; `LibraryPresentation` is handed these `String`s and joins fragments with
/// " · ". A member whose key carries a value takes the locale its caller was given. The names of equipment and
/// muscles are in `LibraryCopy+Names.swift`.
///
/// Not here: exercise names, which are data, and weights, which the Domain formats.
nonisolated enum LibraryCopy {
    // MARK: Header and search

    static var title: String {
        String(localized: "Library", bundle: .module, comment: "Title of the Library tab's screen")
    }

    static var newExercise: String {
        String(
            localized: "New exercise",
            bundle: .module,
            comment: "Button in the Library's header, and under No exercises yet: creates an exercise of one's own"
        )
    }

    /// "Search 224 exercises": every stored exercise, whatever the filter.
    static func searchExercises(_ count: Int, locale: Locale) -> String {
        String(
            localized: "Search \(count) exercises",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Placeholder and spoken label of the Library's search field, with the number of exercises"
        )
    }

    // MARK: Filter chips

    static var allChip: String {
        String(
            localized: "All",
            bundle: .module,
            comment: "First filter chip of the Library, in the muscle row and in the equipment row: no filter"
        )
    }

    static var muscleRow: String {
        String(localized: "Muscle", bundle: .module, comment: "Spoken name of the Library's muscle chips")
    }

    static var equipmentRow: String {
        String(localized: "Equipment", bundle: .module, comment: "Spoken name of the Library's equipment chips")
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

    // MARK: Sections and rows

    static var recentlyLogged: String {
        String(
            localized: "RECENTLY LOGGED",
            bundle: .module,
            comment: "Heading of the Library's exercises logged last, latest first"
        )
    }

    static var allExercises: String {
        String(localized: "ALL EXERCISES", bundle: .module, comment: "Heading of the Library's every exercise, A to Z")
    }

    /// "34 sessions": how many workouts hold the exercise, on its row in RECENTLY LOGGED.
    static func sessions(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) sessions",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "On a recently logged exercise's row: how many workouts it was done in"
        )
    }

    static var custom: String {
        String(
            localized: "Custom",
            bundle: .module,
            comment: "On an exercise's row, after its equipment and muscle: the lifter made it"
        )
    }

    /// The PR column of an exercise with no best set.
    static var noRecord: String {
        String(localized: "—", bundle: .module, comment: "In place of the best weight of an exercise never logged")
    }

    /// "PR 195 pounds": the best set's weight, as VoiceOver reads it at the end of a row.
    static func spokenRecord(_ weight: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "PR \(weight) pounds",
                bundle: .module,
                locale: locale,
                comment: "Spoken best weight, in pounds"
            )
        case .kg:
            String(
                localized: "PR \(weight) kilograms",
                bundle: .module,
                locale: locale,
                comment: "Spoken best weight, in kilograms"
            )
        }
    }

    // MARK: Messages

    static var nothingMatches: String {
        String(
            localized: "Nothing matches that filter.",
            bundle: .module,
            comment: "Shown in the Library when the search and the two chip rows leave no exercise"
        )
    }

    static var clearFilters: String {
        String(
            localized: "Clear filters",
            bundle: .module,
            comment: "Button under: Nothing matches that filter. It empties the search and sets both chip rows to All"
        )
    }

    static var noExercisesYet: String {
        String(
            localized: "No exercises yet.",
            bundle: .module,
            comment: "Shown in the Library when no exercise is stored at all"
        )
    }

    static var failedTitle: String {
        String(
            localized: "Can't show the library right now",
            bundle: .module,
            comment: "Title shown in place of the Library when its data cannot be read"
        )
    }

    static var failedBody: String {
        String(
            localized: "Your exercises and workouts are still on this iPhone. Open the app again to try once more.",
            bundle: .module,
            comment: "Under the title shown when the Library's data cannot be read"
        )
    }
}

// MARK: - Counted texts

nonisolated extension Locale {
    /// The locale every counted text of the module is looked up with: the Domain's `forCountedText(in:)`, the one
    /// place that decides it, with this module's catalog.
    var forCountedText: Locale {
        forCountedText(in: .module)
    }
}
