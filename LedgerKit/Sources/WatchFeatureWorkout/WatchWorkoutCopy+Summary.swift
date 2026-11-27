import Foundation
import LedgerDomain

/// The session list's, the end overlay's and the summary's words (spec §4.3).
nonisolated extension WatchWorkoutCopy {
    // MARK: Session list

    /// "2 OF 5 DONE": the exercises with every set logged, then the workout's exercises.
    static func exercisesDone(_ done: String, of count: String, locale: Locale) -> String {
        String(
            localized: "\(done) OF \(count) DONE",
            bundle: .module,
            locale: locale,
            comment: "Header of the session list: the exercises fully logged, then all the workout's exercises"
        )
    }

    /// "5 × 5 @ 185": a row's sets, reps and load, which the caller formats in the workout's unit.
    static func scheme(sets: Int, reps: Int, load: String, locale: Locale) -> String {
        String(
            localized: "\(sets) × \(reps) @ \(load)",
            bundle: .module,
            locale: locale,
            comment: "A row of the session list: the exercise's sets, then its reps, then its load, which has no unit"
        )
    }

    static var endWorkoutButton: String {
        String(localized: "End workout", bundle: .module, comment: "Button under the session list: asks to end")
    }

    // MARK: End workout

    static var endWorkout: String {
        String(localized: "End workout?", bundle: .module, comment: "Title of the overlay that ends the workout")
    }

    /// "23 of 25 sets logged": the sets done, as text in the lifter's digits, of the workout's set rows, whose
    /// number picks the form.
    static func setsLogged(done: String, of total: Int, locale: Locale) -> String {
        String(
            localized: "\(done) of \(total) sets logged",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "The sets logged in the workout so far, then all its sets"
        )
    }

    /// "24,180 lb moved": the weight lifted so far, the Domain's text.
    static func moved(_ volume: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(volume) lb moved",
                bundle: .module,
                locale: locale,
                comment: "The total weight lifted in the workout so far, in pounds"
            )
        case .kg:
            String(
                localized: "\(volume) kg moved",
                bundle: .module,
                locale: locale,
                comment: "The total weight lifted in the workout so far, in kilograms"
            )
        }
    }

    static var saveWorkout: String {
        String(localized: "Save workout", bundle: .module, comment: "Ends the workout and keeps it in history")
    }

    static var discard: String {
        String(localized: "Discard", bundle: .module, comment: "Ends the workout without saving it")
    }

    static var keepLifting: String {
        String(localized: "Keep lifting", bundle: .module, comment: "Closes the overlay and returns to the list")
    }

    // MARK: Summary

    static var workoutDone: String {
        String(localized: "WORKOUT DONE", bundle: .module, comment: "Eyebrow of the summary of a saved workout")
    }

    static var elapsedCaption: String {
        String(localized: "ELAPSED", bundle: .module, comment: "Caption under the workout's time on the summary")
    }

    /// "18/20": the sets done, then all the workout's sets, each in the lifter's digits.
    static func setsRatio(_ done: String, of total: String, locale: Locale) -> String {
        String(
            localized: "\(done)/\(total)",
            bundle: .module,
            locale: locale,
            comment: "The summary's sets: those logged, then all the workout's sets"
        )
    }

    static var setsCaption: String {
        String(localized: "SETS", bundle: .module, comment: "Caption under the summary's sets")
    }

    /// "LB MOVED" / "KG MOVED", under the volume.
    static func movedCaption(_ units: Units) -> String {
        switch units {
        case .lb: String(localized: "LB MOVED", bundle: .module, comment: "Caption under the volume, in pounds")
        case .kg: String(localized: "KG MOVED", bundle: .module, comment: "Caption under the volume, in kilograms")
        }
    }

    static var averageHeartRateCaption: String {
        String(localized: "AVG BPM", bundle: .module, comment: "Caption under the workout's average heart rate")
    }

    static var newRecordsCaption: String {
        String(localized: "NEW PR", bundle: .module, comment: "Caption under the number of records the workout set")
    }

    static var done: String {
        String(localized: "Done", bundle: .module, comment: "Button that closes the summary")
    }
}
