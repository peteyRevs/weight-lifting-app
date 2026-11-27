import Foundation
import LedgerDomain

/// The set-ready and rest screens' controls, and what VoiceOver reads for them (F18 criterion 14).
nonisolated extension WatchWorkoutCopy {
    // MARK: Set ready

    /// "REPS", after the reps' number.
    static var repsCaption: String {
        String(localized: "REPS", bundle: .module, comment: "Caption after the reps of the set to log")
    }

    static var doneSet: String {
        String(localized: "Done set", bundle: .module, comment: "Button on the set screen: logs the set as it reads")
    }

    static var decreaseReps: String {
        String(localized: "Decrease reps", bundle: .module, comment: "Spoken name of the set screen's minus button")
    }

    static var increaseReps: String {
        String(localized: "Increase reps", bundle: .module, comment: "Spoken name of the set screen's plus button")
    }

    /// What VoiceOver calls the workout's running time on the set screen, before the time.
    static var elapsedLabel: String {
        String(localized: "Elapsed time", bundle: .module, comment: "Spoken name of the workout's running time")
    }

    // MARK: Rest

    static var extendRest: String {
        String(localized: "+30s", bundle: .module, comment: "Button on the rest screen: 30 seconds more rest")
    }

    /// What VoiceOver reads for "+30s".
    static var extendRestLabel: String {
        String(localized: "Add 30 seconds", bundle: .module, comment: "Spoken name of the rest screen's +30s button")
    }

    static var skipRest: String {
        String(localized: "Skip", bundle: .module, comment: "Button on the rest screen: ends the rest now")
    }

    /// "Rest, 42 seconds remaining": what VoiceOver reads for the ring, `time` in words.
    static func restRemaining(_ time: String, locale: Locale) -> String {
        String(
            localized: "Rest, \(time) remaining",
            bundle: .module,
            locale: locale,
            comment: "Spoken reading of the rest ring: the time left, in words"
        )
    }

    /// What VoiceOver reads for the ring once the rest is over.
    static var restOver: String {
        String(localized: "Rest over", bundle: .module, comment: "Spoken reading of the rest ring at zero")
    }
}
