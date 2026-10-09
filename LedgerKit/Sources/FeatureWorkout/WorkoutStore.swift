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
/// **The pump** (F10 S5 criterion 7). A tap on the page is queued by `send` and applied by `pump()`, one at a
/// time and in the order the taps were made: each is planned on the workout as the tap before it left it
/// (the session's answer to that tap, which can be ahead of what the stream has shown), so two quick "+"
/// are two steps, and a second tap on a check finds the set logged and does nothing. Nothing is applied
/// twice and nothing is dropped, with one exception: when the session refuses a change, the taps queued
/// behind it are dropped with it, because they were made on a page that never came to be.
///
/// **Making one does nothing.** `WorkoutRoot` makes a store each time SwiftUI evaluates the cover's content
/// and `@State` keeps the first, so the initializer must stay empty.
///
/// **Haptics.** An update carries the haptics of its change. This slice plays none. When S6 does, they are
/// played here, from the stream and from nowhere else, so that a change is never felt twice: not from a
/// call's return as well, and not by Today, which reads the same stream.
@MainActor @Observable
final class WorkoutStore {
    typealias Dialog = WorkoutDialog

    /// The live workout: `loading` until the session's first update, `failed` when its updates end.
    private(set) var workout = Loadable<WorkoutState>.idle
    private(set) var dialog: Dialog?
    /// True from the tap on "Discard" until the session refuses it; once it succeeds the cover closes.
    private(set) var isDiscarding = false
    /// The discard the root's `.task(id:)` runs: each accepted tap on "Discard" makes the next.
    private(set) var discardAttempt = 0
    private(set) var exit: WorkoutExit?
    /// The row the lifter chose, where it is not the engine's cursor; nil leaves the choice to the cursor.
    private(set) var selection: WorkoutSelection?
    @ObservationIgnored private var isDiscardRunning = false
    /// The taps waiting for the pump, oldest first. The one being applied stays at the front until it is done.
    @ObservationIgnored private var queue: [WorkoutEdit] = []
    @ObservationIgnored private var isDraining = false
    /// Wakes `pump()` when a tap is queued; nil while no pump runs, and the tap then waits for the next.
    @ObservationIgnored private var wake: AsyncStream<Void>.Continuation?
    /// The session's answer to the last change, until the stream has shown it: the workout the next tap is
    /// planned on. A stream is not behind a call's return for long, but a second tap can come in between.
    @ObservationIgnored private var ahead: WorkoutState?

    @ObservationIgnored @Dependency(\.workoutSession) private var session
    @ObservationIgnored @Dependency(\.date) private var date
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8); a disabled logger stays disabled.
    private var logger: LedgerLogger {
        injectedLogger.category("workout")
    }

    /// What the screen draws.
    var model: WorkoutScreenModel {
        WorkoutPresentation.screen(
            workout,
            selection: selection,
            isBusy: isDiscarding || exit != nil,
            locale: locale,
            calendar: calendar
        )
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
    private var isShowingWorkout: Bool {
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
        queue = []
        isDiscarding = true
        discardAttempt += 1
    }

    /// Queues a tap of the page and wakes the pump.
    private func enqueue(_ edit: WorkoutEdit) {
        guard isShowingWorkout else {
            return
        }
        queue.append(edit)
        wake?.yield()
    }

    private func leave(_ reason: WorkoutExit) {
        guard exit == nil else {
            return
        }
        dialog = nil
        queue = []
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
            if live == ahead {
                // The stream has caught up with the last change: from here it is the newest again.
                ahead = nil
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

// MARK: - The pump

extension WorkoutStore {
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

    /// Applies every waiting tap, oldest first, and those made meanwhile, until none waits. One drain runs
    /// at a time: a second call while one is running returns at once, and the first applies its taps too.
    func drain() async {
        guard !isDraining else {
            return
        }
        isDraining = true
        defer { isDraining = false }
        while let edit = queue.first, exit == nil, !isDiscarding {
            let isApplied = await apply(edit)
            // The tap leaves the queue once it is done. A refusal takes the taps behind it too, and a
            // closing cover has already emptied the queue.
            queue = isApplied ? Array(queue.dropFirst()) : []
        }
    }

    /// Applies one tap: its events, in order, each on the session's answer to the one before. False when
    /// the session refused one.
    ///
    /// - A refusal is logged and shown (`editFailed`); the page keeps showing what the stream last said.
    /// - `noLiveWorkout` is no failure: the workout ended by another hand, and the update that says how
    ///   closes the cover.
    /// - A call cancelled because the cover went away is no failure either.
    private func apply(_ edit: WorkoutEdit) async -> Bool {
        guard case let .loaded(shown) = workout else {
            return false
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
            return true
        } catch WorkoutSessionError.noLiveWorkout {
            ahead = nil
            return false
        } catch {
            ahead = nil
            guard !(error is CancellationError && Task.isCancelled) else {
                return false
            }
            logger.log.error("A change to the workout was refused: \(String(describing: error), privacy: .public)")
            if exit == nil {
                dialog = .editFailed
            }
            return false
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
