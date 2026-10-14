import Foundation

/// "End workout?" (F10 S7): the sheet "Finish" opens, for the workout on screen. Every string is final and
/// so is what answers; the view decides nothing.
nonisolated struct WorkoutFinishModel: Equatable, Sendable {
    let title: String
    /// The sheet's cancel.
    let keepLifting: String
    /// "23 of 25 sets logged · 24,180 lb moved".
    let summary: String
    /// The same two facts as VoiceOver reads them, in one stop: "23 of 25 sets logged, 24,180 lb moved".
    let spokenSummary: String
    let save: String
    let discard: String
    /// Whether "Save workout" answers: a set is logged, and no save is running.
    let canSave: Bool
    /// False while a save runs: no control of the sheet answers, and it cannot be swiped away.
    let isEnabled: Bool
}

/// A save that did not go through: what, what that leaves, and its two buttons. It offers no "Discard"
/// (product default O3): after a failed save the session completes the save before any discard, so a
/// discard would store the workout.
nonisolated struct WorkoutSaveFailedModel: Equatable, Sendable {
    let title: String
    let message: String
    let retry: String
    let close: String
}
