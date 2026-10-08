import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

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
    /// The "OK" of a discard that failed.
    case dismissFailure
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

/// The store of the workout's cover (M1 store convention): the workout as the session last published it, the
/// two dialogs the cover can show over itself, and the one piece of work it starts, the discard.
///
/// It keeps no workout of its own. `follow()` listens to `WorkoutSessionClient.updates()` for as long as the
/// cover is up, and every state it shows is one the session published; a workout that ends, by this cover's
/// discard or by any other hand, closes the cover through `exit`. Intents are synchronous and only change
/// state; `WorkoutRoot` runs `follow()` and `discard()` from its `.task`s, so nothing here outlives the view.
///
/// **Making one does nothing.** `WorkoutRoot` makes a store each time SwiftUI evaluates the cover's content
/// and `@State` keeps the first, so the initializer must stay empty.
///
/// **Haptics.** An update carries the haptics of its change. This slice plays none. When S6 does, they are
/// played here, from the stream and from nowhere else, so that a change is never felt twice: not from a
/// call's return as well, and not by Today, which reads the same stream.
@MainActor @Observable
final class WorkoutStore {
    nonisolated enum Dialog: Equatable, Sendable {
        /// "End workout?".
        case finish
        /// The discard was refused: the workout is still live.
        case discardFailed
    }

    /// The live workout: `loading` until the session's first update, `failed` when its updates end.
    private(set) var workout = Loadable<WorkoutState>.idle
    private(set) var dialog: Dialog?
    /// True from the tap on "Discard" until the session refuses it; once it succeeds the cover closes.
    private(set) var isDiscarding = false
    /// The discard the root's `.task(id:)` runs: each accepted tap on "Discard" makes the next.
    private(set) var discardAttempt = 0
    private(set) var exit: WorkoutExit?
    @ObservationIgnored private var isDiscardRunning = false

    @ObservationIgnored @Dependency(\.workoutSession) private var session
    @ObservationIgnored @Dependency(\.date) private var date
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8); a disabled logger stays disabled.
    private var logger: LedgerLogger {
        injectedLogger.category("workout")
    }

    /// What the screen draws.
    var model: WorkoutScreenModel {
        WorkoutPresentation.screen(workout, isBusy: isDiscarding || exit != nil, locale: locale)
    }

    // MARK: Intents

    func send(_ action: WorkoutAction) {
        // Nothing answers once the cover is closing, or while a discard runs.
        guard exit == nil, !isDiscarding else {
            return
        }
        switch action {
        case .minimize:
            leave(.route(.minimized))
        case .finish:
            if case .loaded = workout {
                dialog = .finish
            }
        case .keepLifting:
            if dialog == .finish {
                dialog = nil
            }
        case .discard:
            // Not tied to the dialog's flag: its dismissal and its button's action arrive in either order.
            if case .loaded = workout {
                dialog = nil
                isDiscarding = true
                discardAttempt += 1
            }
        case .dismissFailure:
            if dialog == .discardFailed {
                dialog = nil
            }
        }
    }

    private func leave(_ reason: WorkoutExit) {
        guard exit == nil else {
            return
        }
        dialog = nil
        exit = reason
    }

    // MARK: Work the root's tasks run

    /// Shows the session's workout for as long as the cover is up: the workout as it stands, then every
    /// change. An update whose workout is no longer live ends it: finished closes the cover as saved,
    /// discarded as discarded, and no workout at all (which only the first update can say) closes it with
    /// nothing to tell. A dialog that was showing goes with the cover.
    ///
    /// The stream ends when the task is cancelled, because the cover went away: that is no failure. If it
    /// ends otherwise the store has lost its source and says so (`failed`), rather than leave a workout on
    /// screen that no longer follows the session.
    func follow() async {
        if case .idle = workout {
            workout = .loading
        }
        for await update in await session.updates() {
            guard let live = update.live else {
                leave(Self.exit(for: update.state))
                return
            }
            workout = .loaded(live)
        }
        guard !Task.isCancelled, exit == nil else {
            return
        }
        logger.log.error("The session's updates ended while the workout's cover was up")
        workout = .failed(WorkoutStoreError.updatesEnded)
    }

    private static func exit(for ended: WorkoutState?) -> WorkoutExit {
        guard let ended else {
            return .nothingToShow
        }
        return .route(ended.phase == .finished ? .saved(ended.id) : .discarded)
    }

    /// Runs the current discard, once: ends the workout through the session, at the injected date, and
    /// closes the cover when the session has dropped it.
    ///
    /// - A refusal is logged and shown (`discardFailed`), and the workout stays as the session shows it.
    /// - `noLiveWorkout` is no failure: the workout ended by another hand first, and the update that says
    ///   how (saved or discarded) closes the cover.
    /// - A discard cancelled because the cover went away is no failure either. The session's host completes
    ///   the call in a task of its own.
    func discard() async {
        guard isDiscarding, exit == nil, !isDiscardRunning else {
            return
        }
        isDiscardRunning = true
        defer { isDiscardRunning = false }
        do {
            try await session.discard(endedAt: date.now)
            leave(.route(.discarded))
        } catch WorkoutSessionError.noLiveWorkout {
            isDiscarding = false
        } catch {
            isDiscarding = false
            guard !(error is CancellationError && Task.isCancelled) else {
                return
            }
            logger.log.error("The workout could not be discarded: \(String(describing: error), privacy: .public)")
            if exit == nil {
                dialog = .discardFailed
            }
        }
    }
}
