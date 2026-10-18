import Foundation
import LedgerDomain

/// FeatureOnboarding's copy (standards §7): every string the screen shows or speaks is looked up here, in this
/// module's `Resources/Localizable.xcstrings`, whose keys are the English text (product spec §6.7, with the body
/// of step 1 reworded so that it does not name the product). No other file in the module holds a user-facing
/// literal or a localized lookup; the presentation is handed these `String`s. A translator's comment is written
/// here, and the catalog's copy of it matches.
///
/// Program names, day names and the lines under them are the Domain's data (`ProgramTemplates.preview(days:)`),
/// shown as given: they are not entries here. The options of steps 1 and 2 are in `OnboardingCopy+Options.swift`.
nonisolated enum OnboardingCopy {
    // MARK: Step 1, the goal

    static var goalTitle: String {
        String(localized: "What are you training for?", bundle: .module, comment: "Setup, step 1 of 3: the title")
    }

    static var goalBody: String {
        String(
            localized: "This sets how your loads progress week to week.",
            bundle: .module,
            comment: "Setup, step 1 of 3: the line under the title"
        )
    }

    // MARK: Step 2, the days

    static var daysTitle: String {
        String(localized: "How many days a week?", bundle: .module, comment: "Setup, step 2 of 3: the title")
    }

    static var daysBody: String {
        String(
            localized: "Pick the number you will actually hit, not the one you want to hit.",
            bundle: .module,
            comment: "Setup, step 2 of 3: the line under the title"
        )
    }

    // MARK: Step 3, the program

    static var programTitle: String {
        String(localized: "Your program", bundle: .module, comment: "Setup, step 3 of 3: the title")
    }

    /// "Upper / Lower, 8 weeks, pounds. Editable any time.": the program's name (the Domain's data), how many
    /// weeks it runs, which picks the plural form (in the catalog's language: `forCountedText`), and
    /// `unitName(_:)`.
    static func programBody(name: String, weeks: Int, unit: String, locale: Locale) -> String {
        String(
            localized: "\(name), \(weeks) weeks, \(unit). Editable any time.",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Setup, step 3 of 3, under the title: the program's name, its weeks, the unit of its loads"
        )
    }

    /// The unit as `programBody` names it.
    static func unitName(_ units: Units) -> String {
        switch units {
        case .lb:
            String(
                localized: "pounds",
                bundle: .module,
                comment: "The unit of a program's loads, inside the sentence of setup's step 3"
            )
        case .kg:
            String(
                localized: "kilograms",
                bundle: .module,
                comment: "The unit of a program's loads, inside the sentence of setup's step 3"
            )
        }
    }

    // MARK: Buttons

    static var continueTitle: String {
        String(localized: "Continue", bundle: .module, comment: "Setup, steps 1 and 2: goes to the next step")
    }

    static var startTraining: String {
        String(localized: "Start training", bundle: .module, comment: "Setup, step 3: saves the program shown")
    }

    static var skipSetup: String {
        String(
            localized: "Skip setup",
            bundle: .module,
            comment: "Setup, every step: saves the default program without asking anything more"
        )
    }

    static var back: String {
        String(localized: "Back", bundle: .module, comment: "Setup, steps 2 and 3: returns to the step before")
    }

    static var retry: String {
        String(localized: "Retry", bundle: .module, comment: "Setup: tries to save the program again")
    }

    // MARK: Failure

    static var saveFailed: String {
        String(
            localized: "Couldn't save your program. Try again.",
            bundle: .module,
            comment: "Setup: shown above the Retry button when the program could not be saved"
        )
    }

    // MARK: Spoken

    /// What VoiceOver reads for the progress bars: "Step 1 of 3".
    static func step(_ number: Int, of count: Int, locale: Locale) -> String {
        String(
            localized: "Step \(number) of \(count)",
            bundle: .module,
            locale: locale,
            comment: "Setup: what VoiceOver reads for the progress bars at the top"
        )
    }
}

// MARK: - Counted texts

nonisolated extension Locale {
    /// The locale every counted text of the module is looked up with: the Domain's `forCountedText(in:)`,
    /// the one place that decides it, with this module's catalog. The plural form is the catalog's
    /// language's; the digits and their grouping stay the lifter's.
    var forCountedText: Locale {
        forCountedText(in: .module)
    }
}
