import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of one exercise's history (F12 S2; the M1 store convention, as `LibraryStore`).
///
/// **It follows three sources and reads two queries.** `run()` follows the exercises (a rename, N13), the settings
/// (units and the first day of the week) and the exercise's own sessions, for as long as the root's task runs; on
/// every change of the sessions (a workout of the exercise finished, edited or deleted, the newest or an older one,
/// F12-S2-3) it reads the sessions and records again, together. Every change marks one channel that keeps only the
/// newest mark, and one loop rebuilds the model.
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
        /// The sessions and the record workouts, as last read; nil when the sessions have changed since.
        var read: (sessions: [ExerciseSession], records: Set<WorkoutID>)?
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
                await self.follow(self.stats.observeExerciseSessions(exerciseID: id), mark) { kept, _ in
                    kept.read = nil
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
        guard let found = sources.exercise, let current = sources.settings else {
            return
        }
        guard let exercise = found else {
            logger.log.error("An exercise's history was asked for an exercise that is not stored")
            state = .failed
            return
        }
        guard let read = await readHistory() else {
            return
        }
        let model = ExerciseHistoryPresentation.make(ExerciseHistoryInput(
            exercise: exercise,
            sessions: read.sessions,
            records: read.records,
            units: current.units,
            weekStart: current.weekStart,
            now: date.now,
            calendar: calendar,
            locale: locale
        ))
        if state != .loaded(model) {
            state = .loaded(model)
        }
    }

    /// The sessions and records as last read, or read now. Nil when the read failed, which is logged and shown,
    /// or the run was cancelled meanwhile. A read that a change of the sessions overtook is shown and not kept:
    /// the change has marked the channel, so the next turn reads again.
    private func readHistory() async -> (sessions: [ExerciseSession], records: Set<WorkoutID>)? {
        if let kept = sources.read {
            return kept
        }
        let generation = sources.generation
        do {
            let sessions = try await stats.exerciseSessions(exerciseID: exerciseID)
            let records = try await stats.personalRecords(exerciseID: exerciseID)
            guard !Task.isCancelled else {
                return nil
            }
            let read = (sessions: sessions, records: Set(records.map(\.workoutID)))
            if sources.generation == generation {
                sources.read = read
            }
            return read
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
