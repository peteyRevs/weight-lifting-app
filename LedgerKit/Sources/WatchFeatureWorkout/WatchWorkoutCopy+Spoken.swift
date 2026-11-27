import Foundation
import LedgerDomain

/// What VoiceOver reads for the summary's tiles and the session list, and the takeover banner (F18 S6a).
nonisolated extension WatchWorkoutCopy {
    // MARK: Summary, spoken: each tile one phrase

    /// "45 minutes, 30 seconds elapsed": the workout's time, `time` in words.
    static func elapsedSpoken(_ time: String, locale: Locale) -> String {
        String(
            localized: "\(time) elapsed",
            bundle: .module,
            locale: locale,
            comment: "Spoken reading of the summary's time: the workout's length, in words"
        )
    }

    /// "11,100 pounds moved": the summary's volume, the Domain's text.
    static func movedSpoken(_ volume: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(volume) pounds moved",
                bundle: .module,
                locale: locale,
                comment: "Spoken reading of the summary's volume, in pounds"
            )
        case .kg:
            String(
                localized: "\(volume) kilograms moved",
                bundle: .module,
                locale: locale,
                comment: "Spoken reading of the summary's volume, in kilograms"
            )
        }
    }

    /// "Average heart rate, 138 beats per minute".
    static func averageHeartRateSpoken(_ bpm: Int, locale: Locale) -> String {
        String(
            localized: "Average heart rate, \(bpm) beats per minute",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Spoken reading of the summary's average heart rate, from Health"
        )
    }

    static var noAverageHeartRate: String {
        String(
            localized: "No average heart rate",
            bundle: .module,
            comment: "Spoken reading of the summary's average heart rate when Health has none"
        )
    }

    /// "2 new personal records".
    static func newRecordsSpoken(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) new personal records",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Spoken reading of the summary's NEW PR: the records the workout set"
        )
    }

    // MARK: Session list

    /// What VoiceOver reads for the list's "‹", which closes it.
    static var closeList: String {
        String(localized: "Back", bundle: .module, comment: "Spoken name of the session list's back button")
    }

    /// What VoiceOver reads after a row whose sets are all logged, for its "✓".
    static var allSetsLogged: String {
        String(localized: "All sets logged", bundle: .module, comment: "Spoken state of a fully logged list row")
    }

    // MARK: Banners

    /// Spec §9: another app's workout took the Health session; the watch goes on logging.
    static var healthTakenOver: String {
        String(
            localized: "Apple Workout took over · logging continues",
            bundle: .module,
            comment: "Banner while another app's workout holds Health's session; sets still log"
        )
    }
}
