import Foundation
import LedgerDomain

/// The names of the Domain's equipment and muscle groups, as the Library shows them on a row and on a chip
/// (`LibraryCopy`; standards §7: each module holds its own entry for a Domain case). The casing is the exercise
/// library's, "Barbell · Chest" (Pete's question 6, A: one vocabulary in the app).
nonisolated extension LibraryCopy {
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

    /// A muscle chip's text. "Legs" and "Arms" each stand for several muscle groups; the others are the group's
    /// own name.
    static func muscleFilter(_ filter: ExerciseSearch.MuscleFilter) -> String {
        switch filter {
        case .chest: muscle(.chest)
        case .back: muscle(.back)
        case .shoulders: muscle(.shoulders)
        case .legs: String(localized: "Legs", bundle: .module, comment: "Filter chip: every muscle of the legs")
        case .arms: String(localized: "Arms", bundle: .module, comment: "Filter chip: every muscle of the arms")
        }
    }

    /// The name of an exercise's primary muscle, on its row; three of them are filter chips too. The lint's limit
    /// of ten branches is waived on the line: the eleven groups each have their lookup.
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
}
