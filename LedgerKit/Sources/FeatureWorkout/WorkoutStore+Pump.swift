import Foundation
import LedgerDomain

/// The pump of `WorkoutStore` (F10 S5 criteria 7 and 13 to 15; the type's comment says what it promises):
/// the queue of the page's taps, and the work that applies them. In a file of its own for its length; the
/// members of the store it uses are the store's alone.
extension WorkoutStore {
    /// The workout goes on after a Minimize, so the taps made before it are applied first (criterion 14):
    /// with none waiting the cover closes at once, otherwise when the pump has applied them. A change that
    /// is refused meanwhile keeps the cover up, so that its alert is seen.
    func minimize() {
        guard isShowingWorkout, !queue.isEmpty else {
            leave(.route(.minimized))
            return
        }
        dialog = nil
        exitWhenDrained = .route(.minimized)
        wake?.yield()
    }

    /// Queues a tap of the page and wakes the pump.
    func enqueue(_ edit: WorkoutEdit) {
        guard isShowingWorkout else {
            return
        }
        queue.append(edit)
        wake?.yield()
    }

    func emptyQueue() {
        queue = []
        queueEpoch += 1
    }

    /// Applies the page's taps for as long as the cover is up: those already waiting, then each as it is
    /// made. It ends when its task is cancelled, because the cover went away; a tap made with no pump
    /// running waits for the next one.
    func pump() async {
        let (signals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        continuation.yield()
        for await _ in signals {
            await drain()
        }
    }

    /// Applies every waiting tap, oldest first, and those made meanwhile, until none waits; then closes the
    /// cover if "Minimize" was waiting for that. One drain runs at a time: a second call while one is
    /// running returns at once, and the first applies its taps too. Nothing is applied while the store is
    /// not hearing the session, while a discard runs, or once the cover is closing.
    func drain() async {
        guard !isDraining else {
            return
        }
        isDraining = true
        defer { isDraining = false }
        while let edit = queue.first, isHearingTheSession, exit == nil, !isDiscarding {
            let epoch = queueEpoch
            let outcome = await apply(edit)
            if outcome == .refused {
                // The taps behind a refused change were made on a page that never came to be.
                emptyQueue()
                exitWhenDrained = nil
            } else if epoch == queueEpoch {
                // The tap is done, or was sent and its call cancelled with the cover: it is not sent again.
                queue.removeFirst()
            }
            if outcome == .interrupted {
                return
            }
        }
        if let waiting = exitWhenDrained, queue.isEmpty {
            leave(waiting)
        }
    }

    /// How one tap ended.
    private enum Outcome {
        /// Every event of its plan was applied.
        case applied
        /// The session refused one: shown as `editFailed`.
        case refused
        /// The workout ended by another hand, or the call was cancelled because the cover went away:
        /// neither is a failure, and the drain stops there.
        case interrupted
    }

    /// Applies one tap: its events, in order, each on the session's answer to the one before.
    ///
    /// - A refusal is logged and shown (`editFailed`); the page keeps showing what the stream last said.
    /// - `noLiveWorkout` is no failure: the workout ended by another hand, and the update that says how
    ///   closes the cover.
    /// - A call cancelled because the cover went away is no failure either: the session's host completes
    ///   a call in a task of its own, so the tap counts as sent.
    private func apply(_ edit: WorkoutEdit) async -> Outcome {
        guard case let .loaded(shown) = workout else {
            return .interrupted
        }
        let plan = WorkoutEditPlan.make(edit, in: ahead ?? shown, selection: selection, now: date.now) {
            SetID(uuid())
        }
        do {
            for event in plan.events {
                let answer = try await session.apply(event)
                ahead = isShown(answer) ? nil : answer
            }
            selection = plan.selection
            return .applied
        } catch WorkoutSessionError.noLiveWorkout {
            ahead = nil
            return .interrupted
        } catch {
            ahead = nil
            guard !(error is CancellationError && Task.isCancelled) else {
                return .interrupted
            }
            logger.log.error("A change to the workout was refused: \(String(describing: error), privacy: .public)")
            if exit == nil {
                dialog = .editFailed
            }
            return .refused
        }
    }

    /// Whether the stream has already shown `state`.
    private func isShown(_ state: WorkoutState) -> Bool {
        if case let .loaded(shown) = workout {
            return shown == state
        }
        return false
    }
}
