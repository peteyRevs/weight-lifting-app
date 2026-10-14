import Foundation
import LedgerDomain

/// Pure functions from what the store and the launcher hold to what the views draw (M1 store convention).
/// Every string is resolved here, through `WorkoutCopy`; the views are handed models and decide nothing. No
/// function reads a clock, a calendar, a locale or a time zone of its own.
nonisolated enum WorkoutPresentation {
    /// The cover's state. `isBusy` disables the header's buttons and the page's controls; `selection` is the
    /// row the lifter chose, where it is not the engine's cursor.
    static func screen(
        _ workout: Loadable<WorkoutState>,
        selection: WorkoutSelection? = nil,
        isBusy: Bool,
        locale: Locale,
        calendar: Calendar
    ) -> WorkoutScreenModel {
        switch workout {
        case .idle, .loading:
            .loading
        case let .loaded(state):
            .workout(WorkoutModel(
                header: header(state, isBusy: isBusy, locale: locale, selection: selection),
                page: page(
                    state,
                    selection: selection,
                    isBusy: isBusy,
                    Context(locale: locale, calendar: calendar)
                )
            ))
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

    /// The discard was refused: the workout is still live.
    static var discardFailedAlert: WorkoutAlertModel {
        WorkoutAlertModel(
            title: WorkoutCopy.couldNotDiscard,
            message: WorkoutCopy.stillInProgress,
            dismiss: WorkoutCopy.okay
        )
    }

    /// A change the page asked for was refused. The line claims nothing about what was saved: a tap can be
    /// two changes, and the first may have gone through.
    static var editFailedAlert: WorkoutAlertModel {
        WorkoutAlertModel(
            title: WorkoutCopy.couldNotSaveChange,
            message: WorkoutCopy.tryAgain,
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
