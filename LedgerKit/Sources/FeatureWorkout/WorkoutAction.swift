import Foundation
import LedgerDomain

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
    /// The system took this dialog's presentation down by itself: it goes, and no other dialog with it.
    case dismissed(WorkoutDialog)
    /// A tap on the page that changes the workout: queued, and applied in its turn by the store's pump.
    case edit(WorkoutEdit)
    /// The receipt's "Done": the cover closes as saved. Nothing else answers while the receipt shows, but a row.
    case done
    /// A row of the receipt (F12 S3, N18): the cover closes as saved, and the app shows the exercise's history.
    case openExercise(ExerciseID)
    /// The card's "Swap exercise" and the swap sheet's own controls (F10 S8b).
    case swap(WorkoutSwapIntent)
}

/// What the swap button and the swap sheet ask for (F10 S8b). "Use" is a tap that changes the workout, and goes
/// through the tap queue as `WorkoutEdit.swap`.
nonisolated enum WorkoutSwapIntent: Equatable, Sendable {
    /// The card's "Swap exercise": opens the sheet for the exercise the card showed, named by its place and its
    /// id, and only while the shown exercise is still that one (F10 S8b, review SF1).
    case open(exerciseIndex: Int, exerciseID: ExerciseID)
    /// The sheet's "Cancel", its swipe down and VoiceOver's escape: it goes, and nothing changes.
    case cancel
    /// The sheet's "Also update program" switch, turned on or off.
    case updateProgram(Bool)
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
    /// "Swap exercise" (F10 S8b): the alternatives to the shown exercise.
    case swap
}
