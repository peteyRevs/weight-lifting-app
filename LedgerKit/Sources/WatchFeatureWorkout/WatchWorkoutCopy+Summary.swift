import Foundation
import LedgerDomain

/// The summary's words (spec §4.3 "Watch — summary").
nonisolated extension WatchWorkoutCopy {
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
