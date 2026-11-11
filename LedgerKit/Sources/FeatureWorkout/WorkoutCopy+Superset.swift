import Foundation
import LedgerDomain

// MARK: - A superset drawn as one block (F10 S9)

nonisolated extension WorkoutCopy {
    /// "Superset · block 4 of 4": the block's place among the workout's blocks, a solo exercise counted as a
    /// block of one.
    static func supersetBlock(_ number: Int, of count: Int, locale: Locale) -> String {
        String(
            localized: "Superset · block \(number) of \(count)",
            bundle: .module,
            locale: locale,
            comment: "A superset's place among the workout's blocks, counted from 1, then the number of blocks"
        )
    }

    /// "Round 2 of 3".
    static func round(_ number: Int, of count: Int, locale: Locale) -> String {
        String(
            localized: "Round \(number) of \(count)",
            bundle: .module,
            locale: locale,
            comment: "The superset's round being lifted, counted from 1, then the number of rounds"
        )
    }

    /// "Rest 1:15 after B", or with the time in words for VoiceOver: "Rest 1 minute, 15 seconds after B".
    static func restAfter(_ duration: String, letter: String, locale: Locale) -> String {
        String(
            localized: "Rest \(duration) after \(letter)",
            bundle: .module,
            locale: locale,
            comment: "A superset's rest: its length, then the letter of the member after which it starts"
        )
    }

    /// "3 × 12 @ 100 lb": a member's target on its legend row, without the effort.
    static func legendTarget(sets: Int, reps: Int, load: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(sets) × \(reps) @ \(load) lb",
                bundle: .module,
                locale: locale,
                comment: "A superset member's target: sets, reps, then the load in pounds"
            )
        case .kg:
            String(
                localized: "\(sets) × \(reps) @ \(load) kg",
                bundle: .module,
                locale: locale,
                comment: "A superset member's target: sets, reps, then the load in kilograms"
            )
        }
    }

    /// "Swap Lat Pulldown": what VoiceOver reads for a member's swap button.
    static func swapMember(_ name: String, locale: Locale) -> String {
        String(
            localized: "Swap \(name)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of the button that offers other exercises for this superset member"
        )
    }

    /// "Lat Pulldown, set 2": how VoiceOver names a superset row, the member's name first.
    static func spokenMemberSet(_ name: String, _ number: Int, locale: Locale) -> String {
        String(
            localized: "\(name), set \(number)",
            bundle: .module,
            locale: locale,
            comment: "Spoken name of a superset's row: the member's name, then the set's number, counted from 1"
        )
    }

    /// "Cable Lateral Raise, drop set".
    static func spokenMemberDropSet(_ name: String, locale: Locale) -> String {
        String(
            localized: "\(name), drop set",
            bundle: .module,
            locale: locale,
            comment: "Spoken name of a superset's drop set row: the member's name first"
        )
    }

    /// "Log set A2": the check of a superset row that is not logged, named by its label.
    static func logRow(_ label: String, locale: Locale) -> String {
        String(
            localized: "Log set \(label)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of the button that logs a superset's set: its label, the member's letter first"
        )
    }

    /// "Undo set A2".
    static func undoRow(_ label: String, locale: Locale) -> String {
        String(
            localized: "Undo set \(label)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of the button that un-logs a superset's set: its label, the member's letter first"
        )
    }

    /// "A2 · 100 lb × 12": the superset row that comes after the rest.
    static func nextRow(_ label: String, weight: String, reps: Int, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(label) · \(weight) lb × \(reps)",
                bundle: .module,
                locale: locale,
                comment: "The superset row that comes after the rest: its label, its weight in pounds, its reps"
            )
        case .kg:
            String(
                localized: "\(label) · \(weight) kg × \(reps)",
                bundle: .module,
                locale: locale,
                comment: "The superset row that comes after the rest: its label, its weight in kilograms, its reps"
            )
        }
    }
}
