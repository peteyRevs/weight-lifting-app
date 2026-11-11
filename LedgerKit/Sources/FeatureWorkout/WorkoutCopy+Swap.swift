import Foundation
import LedgerDomain

// MARK: - The swap button and the swap sheet (F10 S8b)

nonisolated extension WorkoutCopy {
    /// The card's button, as VoiceOver reads it, and the sheet's title.
    static var swapExercise: String {
        String(
            localized: "Swap exercise",
            bundle: .module,
            comment: "Button that offers other exercises for this one, and the title of the sheet it opens"
        )
    }

    /// The sheet's line under its title (S8 ruling Q6: no equipment filter exists, so the line claims none).
    static var sameMovementPattern: String {
        String(
            localized: "Same movement pattern.",
            bundle: .module,
            comment: "Says what the offered exercises have in common with the one being swapped"
        )
    }

    static var alsoUpdateProgram: String {
        String(
            localized: "Also update program",
            bundle: .module,
            comment: "Switch: the program's day takes the chosen exercise too, when the workout is saved"
        )
    }

    static var use: String {
        String(localized: "Use", bundle: .module, comment: "Swaps this exercise in for the current one")
    }

    /// "Dumbbell · 15 lb", "Kettlebell · 8 kg": the equipment's name, then the load the sets will take, the
    /// Domain's text.
    static func equipmentAndLoad(_ equipment: String, load: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(equipment) · \(load) lb",
                bundle: .module,
                locale: locale,
                comment: "An offered exercise's equipment, then the weight its sets will take, in pounds"
            )
        case .kg:
            String(
                localized: "\(equipment) · \(load) kg",
                bundle: .module,
                locale: locale,
                comment: "An offered exercise's equipment, then the weight its sets will take, in kilograms"
            )
        }
    }

    static var couldNotLoadAlternatives: String {
        String(
            localized: "Couldn't load alternatives.",
            bundle: .module,
            comment: "Shown in the swap sheet when the exercises to offer could not be read"
        )
    }

    static var noAlternatives: String {
        String(
            localized: "No alternatives for this exercise.",
            bundle: .module,
            comment: "Shown in the swap sheet when no other exercise can be offered"
        )
    }

    /// The equipment's name, as the exercise library writes it (standards §7: each module its own entry for a
    /// Domain case).
    static func equipment(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: String(localized: "Barbell", bundle: .module, comment: "Equipment: a barbell")
        case .dumbbell: String(localized: "Dumbbell", bundle: .module, comment: "Equipment: dumbbells")
        case .cable: String(localized: "Cable", bundle: .module, comment: "Equipment: a cable machine")
        case .machine: String(localized: "Machine", bundle: .module, comment: "Equipment: a weight machine")
        case .bodyweight: String(
                localized: "Bodyweight",
                bundle: .module,
                comment: "Equipment: none, the body's weight"
            )
        case .kettlebell: String(localized: "Kettlebell", bundle: .module, comment: "Equipment: a kettlebell")
        case .band: String(localized: "Band", bundle: .module, comment: "Equipment: a resistance band")
        }
    }
}
