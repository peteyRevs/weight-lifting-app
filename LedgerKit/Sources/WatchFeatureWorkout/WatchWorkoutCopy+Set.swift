import Foundation
import LedgerDomain

/// The set-ready and rest screens' words.
nonisolated extension WatchWorkoutCopy {
    // MARK: Set ready

    /// "SET 2 OF 5": the shown row, counted from 1 among its exercise's rows, then their number.
    static func set(_ number: Int, of count: Int, locale: Locale) -> String {
        String(
            localized: "SET \(number) OF \(count)",
            bundle: .module,
            locale: locale,
            comment: "Eyebrow of the set to log: its place, counted from 1, then the exercise's number of sets"
        )
    }

    /// "LB" / "KG", beside the weight.
    static func unit(_ units: Units) -> String {
        switch units {
        case .lb: String(localized: "LB", bundle: .module, comment: "Unit beside the weight, in pounds")
        case .kg: String(localized: "KG", bundle: .module, comment: "Unit beside the weight, in kilograms")
        }
    }

    /// "× 5".
    static func reps(_ count: Int, locale: Locale) -> String {
        String(localized: "× \(count)", bundle: .module, locale: locale, comment: "The reps of the set to log")
    }

    /// "RPE 8".
    static func rpe(_ value: String, locale: Locale) -> String {
        String(
            localized: "RPE \(value)",
            bundle: .module,
            locale: locale,
            comment: "The effort the set aims for, from 5 to 10"
        )
    }

    /// What stands for the heart rate when there is none to show: no sample yet, or Health is not allowed.
    static var noHeartRate: String {
        String(localized: "—", bundle: .module, comment: "Stands for the heart rate when there is none to show")
    }

    static var allowHealth: String {
        String(
            localized: "Allow Health in iPhone Settings",
            bundle: .module,
            comment: "Line on the set screen when the lifter has not let the app read heart rate"
        )
    }

    // MARK: Rest

    static var rest: String {
        String(localized: "REST", bundle: .module, comment: "Title of the rest screen while the countdown runs")
    }

    static var goTitle: String {
        String(localized: "GO", bundle: .module, comment: "Title of the rest screen for a moment once the rest is over")
    }

    /// "Next: 185 lb × 5".
    static func next(weight: String, reps: Int, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "Next: \(weight) lb × \(reps)",
                bundle: .module,
                locale: locale,
                comment: "The set that comes after the rest: its weight in pounds, then its reps"
            )
        case .kg:
            String(
                localized: "Next: \(weight) kg × \(reps)",
                bundle: .module,
                locale: locale,
                comment: "The set that comes after the rest: its weight in kilograms, then its reps"
            )
        }
    }

    static var nextExercise: String {
        String(localized: "Next exercise", bundle: .module, comment: "Line on the rest screen when no set is left")
    }
}
