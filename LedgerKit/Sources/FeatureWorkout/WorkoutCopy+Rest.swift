import Foundation
import LedgerDomain

// MARK: - The rest panel (F10 S6)

nonisolated extension WorkoutCopy {
    /// The line over the next set while a rest runs. The prototype reads "Resting · watch buzzes at
    /// zero"; the watch's part waits for the watch (F17, F18).
    static var resting: String {
        String(localized: "Resting", bundle: .module, comment: "Shown on the rest timer while time is left")
    }

    static var restOver: String {
        String(localized: "Rest over", bundle: .module, comment: "Shown on the rest timer when it has reached zero")
    }

    static var extendRest: String {
        String(localized: "+30s", bundle: .module, comment: "Button that adds 30 seconds to the rest timer")
    }

    /// What VoiceOver reads for "+30s".
    static var extendRestLabel: String {
        String(localized: "Add 30 seconds", bundle: .module, comment: "Spoken label of the +30s button")
    }

    static var skipRest: String {
        String(localized: "Skip rest", bundle: .module, comment: "Button that ends the rest timer")
    }

    /// "Set 3 · 180 lb × 5", "Set 3 · 82.5 kg × 5"; for a drop set, which has no number (`number` nil),
    /// "Drop set · 150 lb × 5". The weight is the Domain's text; the locale is passed because the keys
    /// carry values (standards §7).
    static func nextSet(number: Int?, weight: String, reps: Int, units: Units, locale: Locale) -> String {
        switch (number, units) {
        case let (number?, .lb):
            String(
                localized: "Set \(number) · \(weight) lb × \(reps)",
                bundle: .module,
                locale: locale,
                comment: "The set that comes after the rest: its number, its weight in pounds, its reps"
            )
        case let (number?, .kg):
            String(
                localized: "Set \(number) · \(weight) kg × \(reps)",
                bundle: .module,
                locale: locale,
                comment: "The set that comes after the rest: its number, its weight in kilograms, its reps"
            )
        case (nil, .lb):
            String(
                localized: "Drop set · \(weight) lb × \(reps)",
                bundle: .module,
                locale: locale,
                comment: "The drop set that comes after the rest: its weight in pounds, its reps"
            )
        case (nil, .kg):
            String(
                localized: "Drop set · \(weight) kg × \(reps)",
                bundle: .module,
                locale: locale,
                comment: "The drop set that comes after the rest: its weight in kilograms, its reps"
            )
        }
    }
}
