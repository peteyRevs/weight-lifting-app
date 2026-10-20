import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of the workout's cover (M1 store convention): the workout as the session last published it, the
/// row the lifter chose, the dialogs the cover can show over itself, and the work it starts: the discard, the
/// save (`WorkoutStore+Finish.swift`), and the changes the page's taps ask for.
///
/// It keeps no workout of its own. `follow()` listens to `WorkoutSessionClient.updates()` for as long as the
/// cover is up, and every state it shows is one the session published; a workout that ends, by this cover's
/// discard or by any other hand, closes the cover through `exit`. Intents are synchronous and only change
/// state; `WorkoutRoot` runs `follow()`, `pump()`, `discard()` and `save()` from its `.task`s, so nothing
/// here outlives the view.
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
    /// True from the accepted tap on "Save workout" until the save fails or is withdrawn; once it succeeds
    /// the cover closes. (Set by the store alone; the save is in its own file.)
    var isSaving = false
    /// The save the root's `.task(id:)` runs: each accepted "Save workout" and "Try again" makes the next.
    var saveAttempt = 0
    private(set) var exit: WorkoutExit?
    /// "Minimize" was tapped while taps were still waiting: the cover closes with this once they are applied.
    /// Until then nothing answers, as while a discard runs.
    var exitWhenDrained: WorkoutExit?
    /// The row the lifter chose, where it is not the engine's cursor; nil leaves the choice to the cursor.
    var selection: WorkoutSelection?
    /// The injected date as it was last read: what the rest panel's time left is read at. Nil until it is
    /// first read, and no panel is drawn until then. Only `restPanel` reads it, so that a tick of a rest
    /// draws the panel again and nothing else. (Set by the store alone; the pump is in its own file.)
    var moment: Date?
    @ObservationIgnored private var isDiscardRunning = false
    /// The taps waiting for the pump, oldest first, each with the moment it was made at. The one being
    /// applied stays at the front until it is done.
    @ObservationIgnored var queue: [WorkoutTap] = []
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
    /// The rest that was announced when it was first shown, so that no second wait announces it again.
    @ObservationIgnored var restAnnounced: RestTimer?
    /// The save that is running, or the one that last failed, which "Try again" runs again.
    @ObservationIgnored var pendingSave: PendingSave?
    /// Counts the runs of `save()`, so that one a later run has replaced decides nothing.
    @ObservationIgnored var saveRun = 0
    /// Whether this store has asked the session to finish the workout. From then on "Discard" is not
    /// offered: the host keeps an end it could not save and completes it before any discard, so a discard
    /// would save the workout (F10 S7a, fix round 1). Never set back.
    var hasAskedToFinish = false
    /// How many times `drain()` was entered: for the tests that bound the save's wait.
    @ObservationIgnored var drainPasses = 0
    /// Wakes the run of `save()` that waits for the taps made before it; nil while none waits.
    @ObservationIgnored var settled: (run: Int, wake: AsyncStream<Void>.Continuation)?
    /// The workout this cover saved, as the session ended it: its receipt shows until "Done" (F10 S7b).
    /// Set once. (Set by the store alone; the receipt is in its own file.)
    var saved: WorkoutState?
    /// The bests the workout is judged against, read once (`readBests()`); a failed read is not retried.
    var bests = Loadable<PersonalRecords.Bests>.idle
    /// Every end this cover asked the session to finish the workout at, in its life: an ending update at one
    /// of them is this cover's save (`isSavedHere`).
    @ObservationIgnored var askedEnds: Set<Date> = []
    /// How many calls to `finish` this cover has out; while one is, an ending update waits for its answer.
    @ObservationIgnored var finishesInFlight = 0
    /// The ending update of the workout being saved that arrived while `finish` was out.
    @ObservationIgnored var deferredEnd: WorkoutState?
    /// The records the workout holds that were played, or held when the bests arrived: none is played twice.
    @ObservationIgnored var heldRecords: Set<HeldRecord> = []

    @ObservationIgnored @Dependency(\.workoutSession) var session
    @ObservationIgnored @Dependency(\.date) var date
    @ObservationIgnored @Dependency(\.locale) var locale
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @Dependency(\.uuid) var uuid
    @ObservationIgnored @Dependency(\.haptics) var haptics
    @ObservationIgnored @Dependency(\.announcements) var announcements
    @ObservationIgnored @Dependency(\.continuousClock) var clock
    @ObservationIgnored @Dependency(\.statsQueries) var stats
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8); a disabled logger stays disabled.
    var logger: LedgerLogger {
        injectedLogger.category("workout")
    }

    /// What the screen draws, but for the rest panel (`restPanel`): the receipt once this cover saved the
    /// workout, else the workout as the session shows it.
    var model: WorkoutScreenModel {
        if let receipt {
            return .receipt(receipt)
        }
        return WorkoutPresentation.screen(
            workout,
            selection: selection,
            isBusy: isBusy,
            locale: locale,
            calendar: calendar
        )
    }

    /// "Discard" (`send`, in `WorkoutStore+Intents.swift`). Not tied to the dialog's flag: its dismissal and
    /// its button's action arrive in either order.
    func startDiscard() {
        guard isShowingWorkout, canDiscard else {
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
        settled?.wake.yield()
    }
}

// MARK: - Work the root's tasks run

extension WorkoutStore {
    /// Shows the session's workout for as long as the cover is up: the workout as it stands, then every
    /// change. An update whose workout is no longer live ends it: finished closes the cover as saved,
    /// discarded as discarded, and no workout at all (which only the first update can say) closes it with
    /// nothing to tell. A dialog that was showing goes with the cover. The workout this cover's save ended
    /// shows its receipt instead, and the cover stays up (F10 S7b, `WorkoutStore+Receipt.swift`).
    ///
    /// The stream ends when the task is cancelled, because the cover went away: that is no failure. If it
    /// ends otherwise the store has lost its source and says so (`failed`), rather than leave a workout on
    /// screen that no longer follows the session.
    ///
    /// A follow that starts again starts from the session's workout as it stands (criterion 15): an answer
    /// kept from before is forgotten, and the taps that waited are planned only once this stream's first
    /// update has arrived. That first update carries no haptics, so what changed on the page between the
    /// follow before and this one is played here, as the engine says a change between two states is felt
    /// (`missedHaptics`): a set logged just before the cover's tasks started again is felt, once.
    func follow() async {
        if case .idle = workout {
            workout = .loading
        }
        ahead = nil
        isHearingTheSession = false
        defer { isHearingTheSession = false }
        for await update in await session.updates() {
            guard let live = update.live else {
                if let ended = update.state, isSavedHere(ended) {
                    showReceipt(ended)
                } else if let ended = update.state, waitsForTheAnswer(ended) {
                    // An end this cover did not ask for, with `finish` still out: its answer decides
                    // (`WorkoutStore+Finish.swift`).
                    deferredEnd = ended
                } else if saved == nil {
                    // A receipt already up stays up: only "Done" closes the cover then.
                    leave(exit(for: update.state))
                }
                await play(update.haptics)
                return
            }
            if live == ahead {
                // The stream has caught up with the last change: from here it is the newest again.
                ahead = nil
            }
            let missed = isHearingTheSession ? [] : missedHaptics(before: live)
            workout = .loaded(live)
            if !isHearingTheSession {
                isHearingTheSession = true
                wake?.yield()
                settled?.wake.yield()
            }
            await play(missed + update.haptics + recordHaptics(in: live))
        }
        guard !Task.isCancelled, exit == nil else {
            return
        }
        logger.log.error("The session's updates ended while the workout's cover was up")
        // The store has lost its source: the taps still waiting are given up with it, and so is a "Minimize"
        // that waited for them, so that the failed screen's "Close" closes the cover (F10-S5-7). So are a
        // save that waited for them, and the sheet, which has no workout to ask about.
        emptyQueue()
        exitWhenDrained = nil
        isSaving = false
        dismiss([.finish])
        workout = .failed(WorkoutStoreError.updatesEnded)
        settled?.wake.yield()
    }

    /// Why the cover closes on an update whose workout is not live. No workout at all, which only a
    /// stream's first update can say, has nothing to tell, but in one case: this store asked the session
    /// to save the workout and never heard the answer (the cover's tasks started again meanwhile). The
    /// host completes that call in a task of its own, so the workout is the one being saved.
    private func exit(for ended: WorkoutState?) -> WorkoutExit {
        guard let ended else {
            if isSaving, let save = pendingSave, save.wasSent {
                return .route(.saved(save.id))
            }
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
