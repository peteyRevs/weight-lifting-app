import Foundation
import LedgerDomain

/// The words of an exercise's history (F12 S2), in this module's catalog with the Library's. A weight is the
/// Domain's `formatted(in:)` or a whole number, handed in as text.
nonisolated extension LibraryCopy {
    // MARK: Stats

    static var estimateCaption: String {
        String(localized: "1RM est", bundle: .module, comment: "Under an exercise's estimated one-rep max")
    }

    static var bestSetCaption: String {
        String(localized: "best set", bundle: .module, comment: "Under an exercise's heaviest set, as 195×5")
    }

    static var sessionsCaption: String {
        String(localized: "sessions", bundle: .module, comment: "Under how many workouts an exercise was done in")
    }

    /// "×5": the reps after the best set's weight.
    static func reps(_ reps: Int, locale: Locale) -> String {
        String(localized: "×\(reps)", bundle: .module, locale: locale, comment: "Reps after a set's weight: 195×5")
    }

    // MARK: Chart

    static var chartTitle: String {
        String(
            localized: "ESTIMATED 1RM · 8 WEEKS",
            bundle: .module,
            comment: "Heading of an exercise's chart of its best estimated one-rep max in each of the last 8 weeks"
        )
    }

    /// "W1" … "W8", oldest first.
    static func week(_ number: Int, locale: Locale) -> String {
        String(localized: "W\(number)", bundle: .module, locale: locale, comment: "A week under the chart, W1 oldest")
    }

    static var noChart: String {
        String(
            localized: "Log a session to start the chart.",
            bundle: .module,
            comment: "In place of an exercise's chart when none of its last 8 weeks has an estimate"
        )
    }

    static var spokenChartTitle: String {
        String(localized: "Estimated 1RM by week", bundle: .module, comment: "VoiceOver's name for the chart")
    }

    static var weekAxis: String {
        String(localized: "Week", bundle: .module, comment: "VoiceOver's name for the chart's axis of weeks")
    }

    static func unitAxis(_ units: Units) -> String {
        switch units {
        case .lb: String(localized: "Pounds", bundle: .module, comment: "VoiceOver's name for the chart's values")
        case .kg: String(localized: "Kilograms", bundle: .module, comment: "VoiceOver's name for the chart's values")
        }
    }

    /// "+22 lb", "−3 kg", "0 lb": a change of weight, `weight` being its size without a sign.
    static func change(_ weight: String, sign: Int, units: Units, locale: Locale) -> String {
        switch (units, sign.signum()) {
        case (.lb, 1): String(localized: "+\(weight) lb", bundle: .module, locale: locale, comment: "A gain in pounds")
        case (.lb, -1): String(localized: "−\(weight) lb", bundle: .module, locale: locale, comment: "A loss in pounds")
        case (.lb, _): String(localized: "\(weight) lb", bundle: .module, locale: locale, comment: "No change, pounds")
        case (.kg, 1): String(localized: "+\(weight) kg", bundle: .module, locale: locale, comment: "A gain in kilos")
        case (.kg, -1): String(localized: "−\(weight) kg", bundle: .module, locale: locale, comment: "A loss in kilos")
        case (.kg, _): String(localized: "\(weight) kg", bundle: .module, locale: locale, comment: "No change, kilos")
        }
    }

    // MARK: Session log

    static var sessionLog: String {
        String(localized: "SESSION LOG", bundle: .module, comment: "Heading of an exercise's sessions, newest first")
    }

    static var noSessions: String {
        String(localized: "No sessions yet.", bundle: .module, comment: "In place of the session log of an exercise")
    }

    static var record: String {
        String(localized: "PR", bundle: .module, comment: "Tag of a session that set a personal record")
    }

    /// "180×5": one set of the log.
    static func set(_ weight: String, reps: Int, locale: Locale) -> String {
        String(localized: "\(weight)×\(reps)", bundle: .module, locale: locale, comment: "A set: its weight × its reps")
    }

    static var historyFailedTitle: String {
        String(
            localized: "Can't show this exercise's history right now",
            bundle: .module,
            comment: "Title shown in place of an exercise's history when its data cannot be read"
        )
    }
}
