import Foundation
import LedgerDomain

/// A save the lifter asked for: the workout, and its end, which is the time of the tap on "Save workout".
nonisolated struct PendingSave: Equatable, Sendable {
    let id: WorkoutID
    let endedAt: Date
    /// Whether the session was asked to finish the workout: from then on the host completes the save,
    /// whatever becomes of the call.
    var wasSent = false
}

/// The save of `WorkoutStore` (F10 S7): "Save workout" on the "End workout?" sheet, and "Try again" after
/// a save that did not go through. In a file of its own for its length; the members of the store it uses
/// are the store's alone.
///
/// **No logged set is lost.** The taps made before "Save workout" are applied first, in order, each once
/// (the pump's rules), and the session is asked to finish only when none waits and the last has answered.
/// A change that is refused meanwhile withdraws the save and shows its alert: a workout is never saved
/// without a change the lifter believes was made. Nothing here times out: a call that never returns is
/// waited for, as under "Minimize".
extension WorkoutStore {
    /// The "End workout?" sheet of the workout on screen; nil while none is shown.
    var finishSheet: WorkoutFinishModel? {
        guard case let .loaded(state) = workout else {
            return nil
        }
        return WorkoutPresentation.finishSheet(state, isSaving: isSaving, canDiscard: canDiscard, locale: locale)
    }

    /// "Discard" is offered until this store has asked the session to finish the workout
    /// (`hasAskedToFinish`): a tap on "Discard" never ends as saved.
    var canDiscard: Bool {
        !hasAskedToFinish
    }

    /// "Save workout". With no set logged it does nothing, whatever the button looked like. The end of the
    /// workout is the injected date, read here, once (the time of a tap is the time it was tapped).
    func startSave() {
        guard case let .loaded(state) = workout, state.doneSets > 0, dialog == nil || dialog == .finish else {
            return
        }
        // The sheet stays up while the save runs, with nothing on it answering.
        dialog = .finish
        begin(PendingSave(id: state.id, endedAt: date.now))
    }

    /// "Try again": the save that failed, again, ended when the first attempt said. It answers the failed
    /// save's alert and nothing else: once the alert is closed the store keeps nothing of a waiting end.
    func retrySave() {
        guard dialog == .saveFailed, let failed = pendingSave else {
            return
        }
        dialog = nil
        begin(PendingSave(id: failed.id, endedAt: failed.endedAt))
    }

    private func begin(_ save: PendingSave) {
        pendingSave = save
        isSaving = true
        saveAttempt += 1
        wake?.yield()
    }

    /// Runs the current save: applies the taps that waited, then ends the workout through the session at
    /// the moment "Save workout" was tapped, and closes the cover when the session says it is in history.
    ///
    /// - With no set logged once the taps are applied (the last logged set's un-log was waiting), nothing
    ///   is saved, and the sheet shows that.
    /// - A refusal, and an answer that is not a finished workout, is logged and shown (`saveFailed`); the
    ///   workout stays as the session shows it.
    /// - `noLiveWorkout` is no failure: the workout ended by another hand first, or by an earlier run of
    ///   this save, and the update that says how closes the cover.
    /// - A save cancelled because the cover's tasks ended is no failure either, and is not withdrawn: the
    ///   host completes the call in a task of its own, and the task that starts again runs the same save.
    ///   Where its answer never reaches this store, the next stream's first update says that nothing is
    ///   live, and `follow()` closes the cover as saved.
    func save() async {
        guard isSaving, exit == nil, let save = pendingSave else {
            return
        }
        saveRun += 1
        let run = saveRun
        guard await tapsAreApplied(run) else {
            return
        }
        guard let newest = ahead ?? finishableWorkout, newest.doneSets > 0 else {
            isSaving = false
            return
        }
        pendingSave?.wasSent = true
        hasAskedToFinish = true
        askedEnds.insert(save.endedAt)
        await finish(save, run: run)
    }

    /// Asks the session to finish the workout at `save`'s end, and shows what it answers. An ending update
    /// at an end this cover asked for shows the receipt as soon as it comes (`isSavedHere`); one at another
    /// end, while the call is out, waits for it (`deferredEnd`, `follow()`): a finished answer is this
    /// cover's save, whatever end the session kept, and shows the receipt; any other answer leaves the
    /// waiting update to be judged by the ends this cover asked for. So the order of the answer and the
    /// update never changes the outcome (F10 S7b, fix round 1).
    private func finish(_ save: PendingSave, run: Int) async {
        finishesInFlight += 1
        defer { finishesInFlight -= 1 }
        do {
            let ended = try await session.finish(endedAt: save.endedAt)
            guard ended.phase == .finished else {
                throw WorkoutStoreError.notFinished
            }
            // The workout this save ended: its receipt shows, and "Done" closes the cover (F10 S7b).
            deferredEnd = nil
            showReceipt(ended)
        } catch WorkoutSessionError.noLiveWorkout {
            // The ending update, waiting or still to come, says how it ended; `isSaving` stays until then.
            settleDeferredEnd()
        } catch {
            guard !settleDeferredEnd(), !(error is CancellationError && Task.isCancelled), run == saveRun,
                  exit == nil
            else {
                return
            }
            logger.log.error("The workout could not be saved: \(String(describing: error), privacy: .public)")
            isSaving = false
            dialog = .saveFailed
        }
    }

    /// Judges the ending update that waited for `finish`'s answer, if one did, as any ending update is
    /// judged: true when it decided the cover's outcome.
    @discardableResult
    func settleDeferredEnd() -> Bool {
        guard let ended = deferredEnd, exit == nil, saved == nil else {
            return false
        }
        deferredEnd = nil
        if isSavedHere(ended) {
            showReceipt(ended)
        } else {
            leave(.route(.saved(ended.id)))
        }
        return true
    }

    /// The workout on screen, when one is.
    private var finishableWorkout: WorkoutState? {
        if case let .loaded(state) = workout {
            return state
        }
        return nil
    }

    /// Waits until every tap made before the save is applied and the last has answered, applying them
    /// itself where no pump does. False when there is nothing left to wait for: the save was withdrawn (a
    /// change was refused, the session's updates ended), the cover is closing, a later run took over, or
    /// the task was cancelled.
    private func tapsAreApplied(_ run: Int) async -> Bool {
        let (signals, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        settled = (run, wake)
        defer {
            if settled?.run == run {
                settled = nil
            }
        }
        wake.yield()
        for await _ in signals {
            await drain()
            guard isSaving, exit == nil, run == saveRun else {
                return false
            }
            if queue.isEmpty, !isDraining {
                return true
            }
        }
        return false
    }
}
