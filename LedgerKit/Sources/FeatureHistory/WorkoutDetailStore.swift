import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of a past workout's detail (F13 S2; the M1 store convention, as `ExerciseHistoryStore`).
///
/// **It follows two sources** for as long as `WorkoutDetailRoot`'s task runs: the workout with its records, where
/// they are stored (`WorkoutRepository.observeWorkout(id:)`, N8), so an edit of it, or of an earlier workout that
/// moves its records, reaches the screen; and the settings, whose units it is drawn in. A detail is a few dozen rows,
/// so each change rebuilds the model at once, on the main actor.
///
/// **The workout gone closes the screen.** A nil value (deleted here or elsewhere, N9) asks the app to pop the detail
/// (`HistoryRoute.closeWorkout`), which it does only while the detail is on top; a run that finds it gone again, when
/// the screen over it comes off, asks again. The workout's own observation that ends (its read failed, N10) shows
/// "This workout can't be read." with Delete still offered; the next run follows again. The settings' observation
/// that ends (a settings row this version can't read) blames nothing: the detail keeps the last settings it saw, or
/// the defaults, as `GRDBSettingsRepository.observe()` asks of every feature (F13-S2-1).
///
/// **Delete asks first, then runs once** (N9, F13-S2-3). The alert's "Delete" is accepted while no delete is waiting
/// or running; it makes the next `deletion`, which is the id of the root's task, and `delete()` calls the repository
/// once for it. A run cancelled before its write (the view went away) confirms the delete again under the next
/// `deletion`, so the root's task runs it once the view is up, even when the view came back while the cancelled run
/// still waited for the writer (review S2-R1-1); a run while another is in flight does nothing. A failure
/// is logged and said in an alert, and the screen stays; once deleted, the screen closes. A route waits until the app
/// has taken it, so a double tap on a row is one route. Making one does nothing: the root's tasks do the work.
@MainActor @Observable
final class WorkoutDetailStore {
    enum State: Equatable {
        case loading
        case loaded(WorkoutDetailModel)
        case unreadable(WorkoutDetailModel.Unreadable)
        /// The workout is no longer stored: the screen draws nothing while the app pops it.
        case gone
    }

    let workoutID: WorkoutID
    private(set) var state = State.loading
    /// The route the root hands the app next; nil once the app's handler has returned.
    private(set) var pendingRoute: HistoryPendingRoute?
    /// The delete the root's `.task(id:)` runs; nil until "Delete" is first confirmed.
    private(set) var deletion: Int?
    /// The alert that says a delete failed is up.
    var showsDeleteFailure = false

    @ObservationIgnored private var sources = Sources()
    @ObservationIgnored private var routeNumber = 0
    @ObservationIgnored private var deleting = Deleting.idle

    @ObservationIgnored @Dependency(\.workoutRepository) private var workouts
    @ObservationIgnored @Dependency(\.settingsRepository) private var settings
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    private var logger: LedgerLogger {
        injectedLogger.category("history")
    }

    init(workout: WorkoutID) {
        workoutID = workout
    }

    /// What the sources last said in this run; each nil until it has spoken.
    private struct Sources {
        /// The workout with its records; `.some(nil)` once it is not stored.
        var workout: RecordedWorkout??
        var settings: Settings?
        /// The workout's own observation ended by itself: it can't be read (N10).
        var workoutHasEnded = false
    }

    /// Where the confirmed delete stands: nothing confirmed (or done: the detail is then `.gone`), confirmed and not
    /// yet written (also after a run that was cancelled before its write), or being written.
    private enum Deleting {
        case idle, confirmed, running
    }

    // MARK: Intents

    /// A row's tap: its exercise's history. One route waits at a time.
    func send(_ route: HistoryRoute) {
        guard pendingRoute == nil else {
            return
        }
        routeNumber += 1
        pendingRoute = HistoryPendingRoute(number: routeNumber, route: route)
    }

    /// Hands the waiting route to `handler`, once, and forgets it when the handler has returned.
    func deliverRoute(to handler: (HistoryRoute) -> Void) {
        guard let pending = pendingRoute else {
            return
        }
        handler(pending.route)
        pendingRoute = nil
    }

    /// The alert's "Delete": accepted while no delete runs and the workout is still there.
    func confirmDelete() {
        guard deleting == .idle, state != .gone else {
            return
        }
        deleting = .confirmed
        deletion = (deletion ?? 0) + 1
    }

    // MARK: Work the root's tasks run

    func run() async {
        sources = Sources()
        let id = workoutID
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.follow(self.workouts.observeWorkout(id: id)) { $0.workout = .some($1) } ended: {
                    $0.workoutHasEnded = true
                }
            }
            group.addTask {
                // Settings that can't be read fall back to the last seen, or the defaults (F13-S2-1).
                await self.follow(self.settings.observe()) { $0.settings = $1 } ended: {
                    $0.settings = $0.settings ?? .default
                }
            }
        }
    }

    /// Runs the confirmed delete, once: the repository's `delete(id:)`, then the screen closes. A failure keeps the
    /// screen and says so, and a later "Delete" may try again. A run cancelled with the screen before its write keeps
    /// the delete confirmed under a new `deletion`, for the root's next task.
    func delete() async {
        guard deleting == .confirmed else {
            return
        }
        deleting = .running
        do {
            try await workouts.delete(id: workoutID)
            deleting = .idle
            close()
        } catch {
            guard !(error is CancellationError && Task.isCancelled) else {
                deleting = .confirmed
                deletion = (deletion ?? 0) + 1
                return
            }
            deleting = .idle
            logger.log.error("A workout could not be deleted: \(String(describing: error), privacy: .public)")
            showsDeleteFailure = true
        }
    }

    /// Keeps each value of an observation with `keep` and rebuilds. One that ends while the task still runs has
    /// failed: `ended` says what that leaves.
    private func follow<Value: Sendable>(
        _ values: AsyncStream<Value>,
        keep: (inout Sources, Value) -> Void,
        ended: (inout Sources) -> Void
    ) async {
        for await value in values {
            guard !Task.isCancelled else {
                return
            }
            keep(&sources, value)
            rebuild()
        }
        if !Task.isCancelled {
            logger.log.error("A store's observation ended while a workout's detail was on screen")
            ended(&sources)
            rebuild()
        }
    }

    /// The workout gone closes the screen whatever else has happened (F13-S2-2); its observation ended says it can't
    /// be read; otherwise, once both sources have spoken, the receipt.
    private func rebuild() {
        if case .some(.none) = sources.workout {
            close()
            return
        }
        guard !sources.workoutHasEnded else {
            if state != .gone {
                state = .unreadable(WorkoutDetailPresentation.unreadable)
            }
            return
        }
        guard let found = sources.workout, let recorded = found, let current = sources.settings else {
            return
        }
        let model = WorkoutDetailPresentation.make(WorkoutDetailInput(
            recorded: recorded,
            units: current.units,
            calendar: calendar,
            locale: locale
        ))
        if state != .loaded(model) {
            state = .loaded(model)
        }
    }

    /// The workout is gone: nothing more is drawn, and the app is asked to pop the detail, in place of any route
    /// still waiting (a row's history has nothing to open over).
    private func close() {
        state = .gone
        let close = HistoryRoute.closeWorkout(workoutID)
        guard pendingRoute?.route != close else {
            return
        }
        routeNumber += 1
        pendingRoute = HistoryPendingRoute(number: routeNumber, route: close)
    }
}
