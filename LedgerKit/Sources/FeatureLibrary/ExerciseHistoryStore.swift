import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of one exercise's history (F12 S2; the M1 store convention, as `LibraryStore`).
///
/// **It follows three sources and reads one query.** `run()` follows the exercises (a rename, N13), the settings
/// (units and the first day of the week) and the exercise's own sessions, for as long as the root's task runs; the
/// sessions it keeps as they are observed, and on every change of them (a workout of the exercise finished, edited
/// or deleted, the newest or an older one, F12-S2-3) it reads the records again (F12-S2-R1-3). Every change marks
/// one channel that keeps only the newest mark, and one loop rebuilds the model, off the main actor.
///
/// **A failure is shown**: a source that ends, a read that fails, or an exercise that is not stored. It is
/// logged, and the next change or the next run reads again. A route waits until the app has taken it, so a double
/// tap is one route. Making one does nothing: the root's task does the work.
@MainActor @Observable
final class ExerciseHistoryStore {
    enum State: Equatable {
        case loading
        case loaded(ExerciseHistoryModel)
        case failed
    }

    let exerciseID: ExerciseID
    private(set) var state = State.loading
    /// The route the root hands the app next; nil once the app's handler has returned.
    private(set) var pendingRoute: LibraryPendingRoute?

    @ObservationIgnored private var sources = Sources()
    @ObservationIgnored private var routeNumber = 0

    @ObservationIgnored @Dependency(\.exerciseRepository) private var exercises
    @ObservationIgnored @Dependency(\.settingsRepository) private var settings
    @ObservationIgnored @Dependency(\.statsQueries) private var stats
    @ObservationIgnored @Dependency(\.date) private var date
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    private var logger: LedgerLogger {
        injectedLogger.category("library")
    }

    init(exercise: ExerciseID) {
        exerciseID = exercise
    }

    /// What the sources last said in this run; each nil until it has spoken.
    private struct Sources {
        var exercise: Exercise??
        var settings: Settings?
        /// The exercise's sessions, as last observed.
        var sessions: [ExerciseSession]?
        /// The record workouts, as last read; nil when the sessions have changed since.
        var records: Set<WorkoutID>?
        /// Counts the changes of the sessions, so that a read one of them overtook is shown and not kept.
        var generation = 0
        var hasEnded = false
    }

    // MARK: Intents

    /// A session's tap. One route waits at a time.
    func send(_ route: LibraryRoute) {
        guard pendingRoute == nil else {
            return
        }
        routeNumber += 1
        pendingRoute = LibraryPendingRoute(number: routeNumber, route: route)
    }

    /// Hands the waiting route to `handler`, once, and forgets it when the handler has returned.
    func deliverRoute(to handler: (LibraryRoute) -> Void) {
        guard let pending = pendingRoute else {
            return
        }
        handler(pending.route)
        pendingRoute = nil
    }

    // MARK: Work

    func run() async {
        sources = Sources()
        let (marks, mark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = exerciseID
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.follow(self.exercises.observeAll(), mark) { kept, all in
                    kept.exercise = .some(all.first { $0.id == id })
                }
            }
            group.addTask { await self.follow(self.settings.observe(), mark) { $0.settings = $1 } }
            group.addTask {
                await self.follow(self.stats.observeExerciseSessions(exerciseID: id), mark) { kept, sessions in
                    kept.sessions = sessions
                    kept.records = nil
                    kept.generation += 1
                }
            }
            for await _ in marks {
                await rebuild()
            }
        }
    }

    /// Keeps each value of an observation with `keep` and marks the change. One that ends while the task still
    /// runs has failed.
    private func follow<Value: Sendable>(
        _ values: AsyncStream<Value>,
        _ mark: AsyncStream<Void>.Continuation,
        keep: (inout Sources, Value) -> Void
    ) async {
        for await value in values {
            guard !Task.isCancelled else {
                return
            }
            keep(&sources, value)
            mark.yield()
        }
        if !Task.isCancelled {
            logger.log.error("A store's observation ended while an exercise's history was on screen")
            sources.hasEnded = true
            mark.yield()
        }
    }

    private func rebuild() async {
        guard !sources.hasEnded else {
            state = .failed
            return
        }
        guard let found = sources.exercise, let current = sources.settings, let sessions = sources.sessions else {
            return
        }
        guard let exercise = found else {
            logger.log.error("An exercise's history was asked for an exercise that is not stored")
            state = .failed
            return
        }
        guard let records = await readRecords() else {
            return
        }
        let model = await Self.model(ExerciseHistoryInput(
            exercise: exercise,
            sessions: sessions,
            records: records,
            units: current.units,
            weekStart: current.weekStart,
            now: date.now,
            calendar: calendar,
            locale: locale
        ))
        guard !Task.isCancelled else {
            return
        }
        if state != .loaded(model) {
            state = .loaded(model)
        }
    }

    /// The model, built off the main actor: 2,000 sets of as many weights take more than a frame (F12-S2-R1-2). A
    /// model that a change overtook while it was built is shown, and the change's turn builds the next.
    @concurrent
    private nonisolated static func model(_ input: ExerciseHistoryInput) async -> ExerciseHistoryModel {
        ExerciseHistoryPresentation.make(input)
    }

    /// The record workouts as last read, or read now. Nil when the read failed, which is logged and shown, or the
    /// run was cancelled meanwhile. A read that a change of the sessions overtook is shown and not kept: the change
    /// has marked the channel, so the next turn reads again.
    private func readRecords() async -> Set<WorkoutID>? {
        if let kept = sources.records {
            return kept
        }
        let generation = sources.generation
        do {
            let records = try await Set(stats.personalRecords(exerciseID: exerciseID).map(\.workoutID))
            guard !Task.isCancelled else {
                return nil
            }
            if sources.generation == generation {
                sources.records = records
            }
            return records
        } catch {
            guard !Task.isCancelled else {
                return nil
            }
            logger.log.error("An exercise's history could not be read: \(String(describing: error), privacy: .public)")
            state = .failed
            return nil
        }
    }
}
