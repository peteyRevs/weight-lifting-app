import Foundation

/// WatchFeatureWorkout's copy (standards §7): every string the watch's workout shows or speaks is looked up here, in
/// this module's `Resources/Localizable.xcstrings`, whose keys are the English text. No other file in the module
/// holds a user-facing literal or a localized lookup; the presentation is handed these `String`s.
nonisolated enum WatchWorkoutCopy {
    /// F17 criterion 12, the watch's half: one line under the set label while the iPhone is out of reach. Logging
    /// goes on, and nothing is disabled. The phone's line is `WorkoutCopy.watchNotConnected`, in FeatureWorkout.
    static var iPhoneNotConnected: String {
        String(
            localized: "iPhone not connected — logging continues",
            bundle: .module,
            comment: "Line under the set label while the iPhone is out of reach; every control still works"
        )
    }
}
