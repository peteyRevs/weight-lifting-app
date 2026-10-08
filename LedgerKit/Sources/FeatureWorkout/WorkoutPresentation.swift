import Foundation
import LedgerDomain

/// Pure functions from what the store and the launcher hold to what the views draw (M1 store convention).
/// Every string is resolved here, through `WorkoutCopy`; the views are handed models and decide nothing. No
/// function reads a clock, a calendar, a locale or a time zone of its own.
nonisolated enum WorkoutPresentation {
    /// The cover's state. `isBusy` disables the header's buttons.
    static func screen(_ workout: Loadable<WorkoutState>, isBusy: Bool, locale: Locale) -> WorkoutScreenModel {
        switch workout {
        case .idle, .loading:
            .loading
        case let .loaded(state):
            .workout(WorkoutModel(header: header(state, isBusy: isBusy, locale: locale)))
        case .failed:
            .failed(WorkoutFailedModel(
                title: WorkoutCopy.couldNotOpen,
                message: WorkoutCopy.closeAndTryAgain,
                close: WorkoutCopy.close
            ))
        }
    }

    static var conflictDialog: WorkoutConflictDialogModel {
        WorkoutConflictDialogModel(
            title: WorkoutCopy.workoutInProgress,
            resume: WorkoutCopy.resumeIt,
            replace: WorkoutCopy.discardAndStartNew,
            cancel: WorkoutCopy.cancel
        )
    }

    static var finishDialog: WorkoutFinishDialogModel {
        WorkoutFinishDialogModel(
            title: WorkoutCopy.endWorkout,
            discard: WorkoutCopy.discard,
            keepLifting: WorkoutCopy.keepLifting
        )
    }

    /// The discard was refused: the workout is still live.
    static var discardFailedAlert: WorkoutAlertModel {
        WorkoutAlertModel(
            title: WorkoutCopy.couldNotDiscard,
            message: WorkoutCopy.stillInProgress,
            dismiss: WorkoutCopy.okay
        )
    }

    /// What the launcher says when it opened nothing: what failed, and what that leaves live.
    static func alert(for failure: WorkoutLaunchFailure) -> WorkoutAlertModel {
        let (title, message) = switch failure {
        case let .notStarted(reason): (WorkoutCopy.couldNotStart, line(for: reason))
        case let .notReplaced(aftermath): (WorkoutCopy.couldNotStartNew, line(for: aftermath))
        case .notOpened: (WorkoutCopy.couldNotOpen, WorkoutCopy.tryAgain)
        }
        return WorkoutAlertModel(title: title, message: message, dismiss: WorkoutCopy.okay)
    }

    private static func line(for reason: WorkoutLaunchFailure.Reason) -> String {
        switch reason {
        case .emptyDay: WorkoutCopy.dayHasNoExercises
        case .dayNotInProgram: WorkoutCopy.dayNotInProgram
        case .blockEnded: WorkoutCopy.blockEnded
        case .other: WorkoutCopy.nothingChanged
        case .unknown: WorkoutCopy.tryAgain
        }
    }

    private static func line(for aftermath: WorkoutLaunchFailure.Aftermath) -> String {
        switch aftermath {
        case .liveKept: WorkoutCopy.liveWorkoutKept
        case .nothingLive: WorkoutCopy.liveWorkoutDiscarded
        case .unknown: WorkoutCopy.tryAgain
        }
    }
}
