import Foundation

/// What a tap on the cover asks for. The views send one of these and decide nothing; `WorkoutStore.send` is
/// the one place that decides what it changes.
nonisolated enum WorkoutAction: Equatable, Sendable {
    /// "Minimize", and the failed screen's "Close".
    case minimize
    /// "Finish": asks, with the "End workout?" sheet.
    case finish
    /// The sheet's "Keep lifting", and the sheet going away by any other means.
    case keepLifting
    /// The sheet's "Save workout".
    case save
    /// The sheet's "Discard": one tap, with no second question (product default O2).
    case discard
    /// "Try again" on a save that did not go through.
    case retrySave
    /// The "OK" of a discard, or of a change, that failed; the "Close" of a save that did.
    case dismissFailure
    /// A tap on the page that changes the workout: queued, and applied in its turn by the store's pump.
    case edit(WorkoutEdit)
}

/// Why the cover closes. Set once; `WorkoutRoot` hands it to the launcher.
nonisolated enum WorkoutExit: Equatable, Sendable {
    /// The app is told why (`WorkoutRoute`).
    case route(WorkoutRoute)
    /// The cover opened and no workout was live: there is nothing to tell the app.
    case nothingToShow
}

/// Why the store cannot show the workout.
nonisolated enum WorkoutStoreError: Error, Equatable {
    /// The session's updates ended while the cover was up. A host never ends a stream; the key's stub does.
    case updatesEnded
    /// The session answered a save with a workout that is not finished.
    case notFinished
}

/// What the cover can show over itself; one at a time.
nonisolated enum WorkoutDialog: Equatable, Sendable {
    /// "End workout?".
    case finish
    /// The discard was refused: the workout is still live.
    case discardFailed
    /// A change the page asked for was refused: the page shows the workout as the session last said.
    case editFailed
    /// The save did not go through: the workout is as the session shows it.
    case saveFailed
}
