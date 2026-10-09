import Foundation

/// What a tap on the cover asks for. The views send one of these and decide nothing; `WorkoutStore.send` is
/// the one place that decides what it changes.
nonisolated enum WorkoutAction: Equatable, Sendable {
    /// "Minimize", and the failed screen's "Close".
    case minimize
    /// "Finish": asks, with the finish dialog.
    case finish
    /// The finish dialog's "Keep lifting", and the dialog going away by any other means.
    case keepLifting
    /// The finish dialog's "Discard".
    case discard
    /// The "OK" of a discard, or of a change, that failed.
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
}

/// What the cover can show over itself; one at a time.
nonisolated enum WorkoutDialog: Equatable, Sendable {
    /// "End workout?".
    case finish
    /// The discard was refused: the workout is still live.
    case discardFailed
    /// A change the page asked for was refused: the page shows the workout as the session last said.
    case editFailed
}
