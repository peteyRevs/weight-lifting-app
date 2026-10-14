import Foundation
import LedgerDesign

/// What the cover draws: one of three states. Built by `WorkoutPresentation.screen`, drawn by `WorkoutScreen`.
nonisolated enum WorkoutScreenModel: Equatable, Sendable {
    /// The session has not said yet: the ground alone.
    case loading
    case workout(WorkoutModel)
    /// The workout cannot be shown; the one control closes the cover.
    case failed(WorkoutFailedModel)
}

/// A live workout on screen: the pinned header, and the page that scrolls under it. The rest panel is not
/// of this model: it changes each second of a rest, and is the store's `restPanel` (`RestPanelModel`).
nonisolated struct WorkoutModel: Equatable, Sendable {
    let header: WorkoutHeaderModel
    let page: WorkoutPageModel
}

/// The cover's pinned header (v2 "Active workout"): Minimize, the elapsed time, Finish, the workout's name and
/// one progress segment per exercise.
nonisolated struct WorkoutHeaderModel: Equatable, Sendable {
    let minimize: String
    let finish: String
    /// False while a discard or a save runs, or the cover is closing: neither button answers.
    let isEnabled: Bool
    /// When the workout started: the elapsed time counts from here (`WorkoutTimeline`).
    let startedAt: Date
    /// What VoiceOver reads for the elapsed time: its name, without a time.
    let elapsedLabel: String
    /// The workout's name, as stored: data, not copy.
    let title: String
    /// One per exercise, as long as its set count (rule 36).
    let segments: [ProgressSegment]
    let progressLabel: String
    /// "Exercise 2 of 5"; empty when the workout's cursor names no row.
    let progressValue: String
}

nonisolated struct WorkoutFailedModel: Equatable, Sendable {
    let title: String
    let message: String
    let close: String
}

/// "You have a workout in progress": the three choices.
nonisolated struct WorkoutConflictDialogModel: Equatable, Sendable {
    let title: String
    let resume: String
    let replace: String
    let cancel: String
}

/// Something failed: what, what that leaves, and the one button that closes the alert.
nonisolated struct WorkoutAlertModel: Equatable, Sendable {
    let title: String
    let message: String
    let dismiss: String
}
