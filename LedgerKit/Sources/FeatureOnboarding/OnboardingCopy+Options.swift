import Foundation
import LedgerDomain

/// The picks of steps 1 and 2: each option's label and the line under it (product spec §6.7). Every case has its
/// own lookup, because a key is a literal the catalog can be compared with (standards §7).
nonisolated extension OnboardingCopy {
    // MARK: Step 1, the goals

    /// An option's label on step 1.
    static func title(of goal: TrainingGoal) -> String {
        switch goal {
        case .strength:
            String(localized: "Get stronger", bundle: .module, comment: "Setup, step 1: a training goal")
        case .hypertrophy:
            String(localized: "Build muscle", bundle: .module, comment: "Setup, step 1: a training goal")
        case .both:
            String(localized: "Both, honestly", bundle: .module, comment: "Setup, step 1: a training goal")
        case .consistency:
            String(localized: "Stay consistent", bundle: .module, comment: "Setup, step 1: a training goal")
        }
    }

    /// The line under an option's label on step 1.
    static func detail(of goal: TrainingGoal) -> String {
        switch goal {
        case .strength:
            String(
                localized: "Low reps, linear load increases",
                bundle: .module,
                comment: "Setup, step 1: the line under Get stronger"
            )
        case .hypertrophy:
            String(
                localized: "Moderate reps, volume tracking",
                bundle: .module,
                comment: "Setup, step 1: the line under Build muscle"
            )
        case .both:
            String(
                localized: "Barbell strength + accessory volume",
                bundle: .module,
                comment: "Setup, step 1: the line under Both, honestly"
            )
        case .consistency:
            String(
                localized: "Habit first, numbers second",
                bundle: .module,
                comment: "Setup, step 1: the line under Stay consistent"
            )
        }
    }

    // MARK: Step 2, the days a week

    /// An option's label on step 2.
    static func title(of days: DaysPerWeek) -> String {
        switch days {
        case .three:
            String(localized: "3 days", bundle: .module, comment: "Setup, step 2: training days a week")
        case .four:
            String(localized: "4 days", bundle: .module, comment: "Setup, step 2: training days a week")
        case .five:
            String(localized: "5 days", bundle: .module, comment: "Setup, step 2: training days a week")
        case .six:
            String(localized: "6 days", bundle: .module, comment: "Setup, step 2: training days a week")
        }
    }

    /// The line under an option's label on step 2: the split that number of days gets.
    static func detail(of days: DaysPerWeek) -> String {
        switch days {
        case .three:
            String(
                localized: "Full body each session",
                bundle: .module,
                comment: "Setup, step 2: the program 3 days a week gets"
            )
        case .four:
            String(
                localized: "Upper / lower split",
                bundle: .module,
                comment: "Setup, step 2: the program 4 days a week gets"
            )
        case .five:
            String(
                localized: "Push, pull, legs + accessories",
                bundle: .module,
                comment: "Setup, step 2: the program 5 days a week gets"
            )
        case .six:
            String(
                localized: "Body-part split",
                bundle: .module,
                comment: "Setup, step 2: the program 6 days a week gets"
            )
        }
    }
}
