import Foundation
import LedgerDomain

/// FeatureWorkout's copy (standards §7): every string the workout shows or speaks is looked up here, in this
/// module's `Resources/Localizable.xcstrings`, whose keys are the English text. No other file in the module
/// holds a user-facing literal or a localized lookup; the presentation is handed these `String`s. The elapsed
/// time is not copy: it is clock text, drawn by `WorkoutTimeline`.
nonisolated enum WorkoutCopy {
    // MARK: Header

    static var minimize: String {
        String(
            localized: "Minimize",
            bundle: .module,
            comment: "Button that closes the workout screen and keeps the workout running"
        )
    }

    static var finish: String {
        String(localized: "Finish", bundle: .module, comment: "Button that asks how to end the workout")
    }

    /// What VoiceOver reads for the elapsed time. It names the time and does not say it: a spoken time would
    /// be as old as the moment the screen was last drawn.
    static var elapsedTime: String {
        String(localized: "Elapsed time", bundle: .module, comment: "Spoken label of the workout's running time")
    }

    /// What VoiceOver reads for the progress bar; `exercise(_:of:locale:)` is its value.
    static var workoutProgress: String {
        String(localized: "Workout progress", bundle: .module, comment: "Spoken label of the workout's progress bar")
    }

    /// "Exercise 2 of 5": which exercise the lifter is on.
    static func exercise(_ number: Int, of count: Int, locale: Locale) -> String {
        String(
            localized: "Exercise \(number) of \(count)",
            bundle: .module,
            locale: locale,
            comment: "The current exercise's place in the workout, counted from 1, then the number of exercises"
        )
    }

    // MARK: The conflict dialog

    static var workoutInProgress: String {
        String(
            localized: "You have a workout in progress",
            bundle: .module,
            comment: "Title of the dialog shown when starting a workout while another is running"
        )
    }

    static var resumeIt: String {
        String(localized: "Resume it", bundle: .module, comment: "Opens the workout that is already running")
    }

    static var discardAndStartNew: String {
        String(
            localized: "Discard and start new",
            bundle: .module,
            comment: "Discards the workout that is running and starts the one that was asked for"
        )
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module)
    }

    // MARK: The finish dialog

    static var endWorkout: String {
        String(localized: "End workout?", bundle: .module, comment: "Title of the dialog the Finish button opens")
    }

    static var discard: String {
        String(localized: "Discard", bundle: .module, comment: "Ends the workout without saving it")
    }

    static var keepLifting: String {
        String(localized: "Keep lifting", bundle: .module, comment: "Closes the dialog and returns to the workout")
    }

    // MARK: Failures

    static var okay: String {
        String(localized: "OK", bundle: .module)
    }

    static var close: String {
        String(
            localized: "Close",
            bundle: .module,
            comment: "Closes the workout screen when the workout cannot be shown"
        )
    }

    static var tryAgain: String {
        String(localized: "Try again.", bundle: .module)
    }

    static var couldNotStart: String {
        String(localized: "Couldn't start this workout", bundle: .module)
    }

    static var dayHasNoExercises: String {
        String(localized: "This day has no exercises yet.", bundle: .module)
    }

    static var dayNotInProgram: String {
        String(localized: "This day is no longer in your program.", bundle: .module)
    }

    static var blockEnded: String {
        String(localized: "Your program's block has ended.", bundle: .module)
    }

    static var nothingChanged: String {
        String(localized: "Nothing was changed. Try again.", bundle: .module)
    }

    static var couldNotStartNew: String {
        String(localized: "Couldn't start the new workout", bundle: .module)
    }

    static var liveWorkoutKept: String {
        String(localized: "Your workout in progress was kept.", bundle: .module)
    }

    static var liveWorkoutDiscarded: String {
        String(localized: "Your workout in progress was discarded.", bundle: .module)
    }

    static var couldNotOpen: String {
        String(localized: "Couldn't open this workout", bundle: .module)
    }

    static var closeAndTryAgain: String {
        String(localized: "Close this screen and try again.", bundle: .module)
    }

    static var couldNotDiscard: String {
        String(localized: "Couldn't discard this workout", bundle: .module)
    }

    static var stillInProgress: String {
        String(localized: "It's still in progress. Try again.", bundle: .module)
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
