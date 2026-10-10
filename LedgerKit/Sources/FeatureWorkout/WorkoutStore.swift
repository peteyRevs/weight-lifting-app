import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of the workout's cover (M1 store convention): the workout as the session last published it, the
/// row the lifter chose, the dialogs the cover can show over itself, and the work it starts: the discard, and
/// the changes the page's taps ask for.
///
/// It keeps no workout of its own. `follow()` listens to `WorkoutSessionClient.updates()` for as long as the
/// cover is up, and every state it shows is one the session published; a workout that ends, by this cover's
/// discard or by any other hand, closes the cover through `exit`. Intents are synchronous and only change
/// state; `WorkoutRoot` runs `follow()`, `pump()` and `discard()` from its `.task`s, so nothing here outlives
/// the view.
///
/// **The pump** (F10 S5 criteria 7 and 13 to 15). A tap on the page is queued by `send` and applied by
/// `pump()`, one at a time and in the order the taps were made: each is planned at its turn on the newest
/// workout (the session's answer to the tap before it, which can be ahead of what the stream has shown), so
/// two quick "+" are two steps, and a second tap on a check finds the set logged and does nothing. Nothing is
/// applied twice. Two things drop a tap: when the session refuses a change, the taps queued behind it are
/// dropped with it and the alert says so, because they were made on a page that never came to be; and when
/// the session's updates end, the taps still waiting go with the workout the failed screen replaces.
/// "Discard" drops the taps of the workout it ends. "Minimize" drops none: the cover closes once the taps made before
/// it are applied. Taps wait while the store is not following the session (the cover's tasks have not
/// started, or are starting again), so none is planned on a workout older than the session's.
///
/// **Making one does nothing.** `WorkoutRoot` makes a store each time SwiftUI evaluates the cover's content
/// and `@State` keeps the first, so the initializer must stay empty.
///
/// **Haptics** (F10 S6). An update carries the haptics of its change, and `follow()` plays them: here, from
/// the stream and from nowhere else, so that a change is never felt twice: not from a call's return as
/// well, and not by Today, which reads the same stream. A stream's first update carries none, so a follow
/// that starts again plays nothing a second time. The end of a rest is no change of the workout, and the
/// engine has no haptic for it: `keepRestTime()` plays `.restOver` when the shown rest reaches zero, once
/// for each rest. That, and how the rest's time is kept, is in `WorkoutStore+Rest.swift`.
@MainActor @Observable
final class WorkoutStore {
    typealias Dialog = WorkoutDialog

    /// The live workout: `loading` until the session's first update, `failed` when its updates end.
    private(set) var workout = Loadable<WorkoutState>.idle
    /// (Set by the store alone; not `private(set)` because the pump is the store's extension in its own file.)
    var dialog: Dialog?
    /// True from the tap on "Discard" until the session refuses it; once it succeeds the cover closes.
    private(set) var isDiscarding = false
    /// The discard the root's `.task(id:)` runs: each accepted tap on "Discard" makes the next.
    private(set) var discardAttempt = 0
    private(set) var exit: WorkoutExit?
    /// "Minimize" was tapped while taps were still waiting: the cover closes with this once they are applied.
    /// Until then nothing answers, as while a discard runs.
    var exitWhenDrained: WorkoutExit?
    /// The row the lifter chose, where it is not the engine's cursor; nil leaves the choice to the cursor.
    var selection: WorkoutSelection?
    /// The injected date as it was last read: what the rest panel's time left is read at. Nil until it is
    /// first read, and no panel is drawn until then. (Set by the store alone; the pump is in its own file.)
    var moment: Date?
    @ObservationIgnored private var isDiscardRunning = false
    /// The taps waiting for the pump, oldest first. The one being applied stays at the front until it is done.
    @ObservationIgnored var queue: [WorkoutEdit] = []
    @ObservationIgnored var isDraining = false
    /// Counts the times the queue was emptied as a whole, so a tap that was being applied meanwhile is not
    /// taken off a queue that has since been filled with other taps.
    @ObservationIgnored var queueEpoch = 0
    /// True from the first update of the stream being followed until that stream is left: only then is the
    /// workout on screen the session's, and only then are taps planned.
    @ObservationIgnored var isHearingTheSession = false
    /// Wakes `pump()` when a tap is queued; nil while no pump runs, and the tap then waits for the next.
    @ObservationIgnored var wake: AsyncStream<Void>.Continuation?
    /// The session's answer to the last change, until the stream has shown it: the workout the next tap is
    /// planned on. A stream is not behind a call's return for long, but a second tap can come in between.
    @ObservationIgnored var ahead: WorkoutState?
    /// The rest whose end was played, so that no second wait plays it again. (The store's alone; its rest
    /// is in a file of its own.)
    @ObservationIgnored var restPlayedOver: RestTimer?

    @ObservationIgnored @Dependency(\.workoutSession) var session
    @ObservationIgnored @Dependency(\.date) var date
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.uuid) var uuid
    @ObservationIgnored @Dependency(\.haptics) var haptics
    @ObservationIgnored @Dependency(\.continuousClock) var clock
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8); a disabled logger stays disabled.
    var logger: LedgerLogger {
        injectedLogger.category("workout")
    }

    /// What the screen draws.
    var model: WorkoutScreenModel {
        WorkoutPresentation.screen(
            workout,
            selection: selection,
            now: moment,
            isBusy: isDiscarding || exit != nil || exitWhenDrained != nil,
            locale: locale,
            calendar: calendar
        )
    }

    // MARK: Intents

    func send(_ action: WorkoutAction) {
        // Nothing answers once the cover is closing, or while a discard runs.
        guard exit == nil, exitWhenDrained == nil, !isDiscarding else {
            return
        }
        switch action {
        case .minimize:
            minimize()
        case .finish:
            show(.finish)
        case .keepLifting:
            dismiss([.finish])
        case .discard:
            startDiscard()
        case .dismissFailure:
            dismiss([.discardFailed, .editFailed])
        case let .edit(edit):
            enqueue(edit)
        }
    }

    /// Whether a workout is on screen: only then is there something to finish, discard or change.
    var isShowingWorkout: Bool {
        if case .loaded = workout {
            return true
        }
        return false
    }

    private func show(_ asked: Dialog) {
        if isShowingWorkout {
            dialog = asked
        }
    }

    /// Takes the dialog down when it is one of `dialogs`.
    private func dismiss(_ dialogs: [Dialog]) {
        if let shown = dialog, dialogs.contains(shown) {
            dialog = nil
        }
    }

    /// Not tied to the dialog's flag: its dismissal and its button's action arrive in either order.
    private func startDiscard() {
        guard isShowingWorkout else {
            return
        }
        dialog = nil
        // A tap that was still waiting is not applied to a workout that is being discarded.
        emptyQueue()
        isDiscarding = true
        discardAttempt += 1
    }

    func leave(_ reason: WorkoutExit) {
        guard exit == nil else {
            return
        }
        dialog = nil
        emptyQueue()
        exitWhenDrained = nil
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
    ///
    /// A follow that starts again starts from the session's workout as it stands (criterion 15): an answer
    /// kept from before is forgotten, and the taps that waited are planned only once this stream's first
    /// update has arrived.
    func follow() async {
        if case .idle = workout {
            workout = .loading
        }
        ahead = nil
        isHearingTheSession = false
        defer { isHearingTheSession = false }
        for await update in await session.updates() {
            guard let live = update.live else {
                leave(Self.exit(for: update.state))
                await play(update.haptics)
                return
            }
            if live == ahead {
                // The stream has caught up with the last change: from here it is the newest again.
                ahead = nil
            }
            workout = .loaded(live)
            if !isHearingTheSession {
                isHearingTheSession = true
                wake?.yield()
            }
            await play(update.haptics)
        }
        guard !Task.isCancelled, exit == nil else {
            return
        }
        logger.log.error("The session's updates ended while the workout's cover was up")
        // The store has lost its source: the taps still waiting are given up with it, and so is a "Minimize"
        // that waited for them, so that the failed screen's "Close" closes the cover (F10-S5-7).
        emptyQueue()
        exitWhenDrained = nil
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
