import LedgerDomain

/// What the launcher shows over the tabs. One value, so the cover, the conflict dialog and a failure can
/// never be up together.
nonisolated enum WorkoutLaunchPhase: Equatable, Sendable {
    /// Nothing of the workout is shown.
    case idle
    /// An accepted request is being answered; nothing is shown yet, and no other request is accepted.
    case working
    /// The cover is up. Which workout it shows is the session's to say (`WorkoutStore`).
    case cover
    /// Another day's workout is live: the lifter is asked what to do about the day they asked for.
    case conflict(WorkoutSource)
    case failed(WorkoutLaunchFailure)
}

/// Why nothing was opened, by what the session holds afterwards.
nonisolated enum WorkoutLaunchFailure: Equatable, Sendable {
    /// Why a start was refused: one line of copy each.
    nonisolated enum Reason: Equatable, Sendable {
        /// The day has no exercise.
        case emptyDay
        /// The day, or its program, is no longer the active program's.
        case dayNotInProgram
        /// The week asked for is past the end of the block.
        case blockEnded
        /// A store or the session failed.
        case other
    }

    /// What became of the workout that was to be replaced.
    nonisolated enum Aftermath: Equatable, Sendable {
        /// It is still live: the new day could not be built, or the discard failed.
        case liveKept
        /// It was discarded, and the new one could not be started.
        case nothingLive
        /// The session could not be read afterwards.
        case unknown
    }

    /// A start that changed nothing: whatever was live before still is.
    case notStarted(Reason)
    /// "Discard and start new" did not end with the new workout live.
    case notReplaced(Aftermath)
    /// A resume could not read the session.
    case notOpened
}

/// What the lifter answers the launcher's dialogs with. The views send one and decide nothing.
nonisolated enum WorkoutLaunchAction: Equatable, Sendable {
    /// The conflict's "Resume it".
    case resumeLive
    /// The conflict's "Discard and start new", for the day that was asked for.
    case replaceLive(WorkoutSource)
    /// The conflict's "Cancel", and the dialog going away by any other means.
    case cancelConflict
    /// A failure's "OK".
    case dismissFailure
    /// The cover's content says it is done (`WorkoutStore.exit`).
    case coverClosed
}

/// One accepted request: the work the cover modifier's `.task(id:)` runs. Each accepted request makes the
/// next one, so the task's id changes exactly when there is new work.
nonisolated struct WorkoutLaunchRequest: Hashable, Sendable {
    nonisolated enum Job: Hashable, Sendable {
        case start(WorkoutSource)
        case resume
        /// "Discard and start new".
        case replace(WorkoutSource)
        #if DEBUG
            /// The Debug menu's "Start sample workout" (`WorkoutLauncher.startSample()`).
            case sample
        #endif
    }

    let number: Int
    let job: Job
}
