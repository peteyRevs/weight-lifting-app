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
/// the screen over it comes off, asks again. A source that ends (the workout's read failed, N10) shows "This workout
/// can't be read." with Delete still offered; the next run follows again.
///
/// **Delete asks first, then runs once** (N9). The alert's "Delete" is accepted while no delete runs; it makes the
/// next `deletion`, which is the id of the root's task, and `delete()` calls the repository once. A failure is logged
/// and said in an alert, and the screen stays; once deleted, the screen closes. A route waits until the app has
/// taken it, so a double tap on a row is one route. Making one does nothing: the root's tasks do the work.
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
    /// A confirmed delete has not finished yet.
    @ObservationIgnored private var isDeleting = false

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
        var hasEnded = false
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
        guard !isDeleting, state != .gone else {
            return
        }
        isDeleting = true
        deletion = (deletion ?? 0) + 1
    }

    // MARK: Work the root's tasks run

    func run() async {
        sources = Sources()
        let id = workoutID
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.follow(self.workouts.observeWorkout(id: id)) { $0.workout = .some($1) } }
            group.addTask { await self.follow(self.settings.observe()) { $0.settings = $1 } }
        }
    }

    /// Runs the confirmed delete, once: the repository's `delete(id:)`, then the screen closes. A failure keeps the
    /// screen and says so; a delete cancelled with the screen says nothing.
    func delete() async {
        guard isDeleting else {
            return
        }
        defer { isDeleting = false }
        do {
            try await workouts.delete(id: workoutID)
            close()
        } catch {
            guard !(error is CancellationError && Task.isCancelled) else {
                return
            }
            logger.log.error("A workout could not be deleted: \(String(describing: error), privacy: .public)")
            showsDeleteFailure = true
        }
    }

    /// Keeps each value of an observation with `keep` and rebuilds. One that ends while the task still runs has
    /// failed.
    private func follow<Value: Sendable>(_ values: AsyncStream<Value>, keep: (inout Sources, Value) -> Void) async {
        for await value in values {
            guard !Task.isCancelled else {
                return
            }
            keep(&sources, value)
            rebuild()
        }
        if !Task.isCancelled {
            logger.log.error("A store's observation ended while a workout's detail was on screen")
            sources.hasEnded = true
            rebuild()
        }
    }

    private func rebuild() {
        guard !sources.hasEnded else {
            if state != .gone {
                state = .unreadable(WorkoutDetailPresentation.unreadable)
            }
            return
        }
        guard let found = sources.workout, let current = sources.settings else {
            return
        }
        guard let recorded = found else {
            close()
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
