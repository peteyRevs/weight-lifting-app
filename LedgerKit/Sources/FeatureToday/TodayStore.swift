import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// Why the store cannot show today.
nonisolated enum TodayStoreError: Error, Equatable {
    /// A store's observation ended while Today was on screen. A store never ends one unless its read failed
    /// (`ValueObservation.stream(in:)` logs the error and finishes the stream).
    case observationEnded
}

/// A route on its way to the app: `TodayRoot`'s `.task(id:)` hands it on. The number tells one tap from the
/// next when both ask for the same route.
nonisolated struct TodayPendingRoute: Hashable, Sendable {
    let number: Int
    let route: TodayRoute
}

/// The store of the Today screen (M1 store convention): what the screen draws, made by
/// `TodayPresentation.make` from what the stores and the live workout's session hold now.
///
/// **It follows five sources and reads two more.** `run()` observes the active program, the settings, the
/// exercises, the workouts finished last and the session's updates for as long as `TodayRoot`'s task runs.
/// The week's finished workouts and the volume of the week before are plain reads, made again whenever a
/// source that can change them has (`TodayHistory`). Every change marks one channel that keeps only the newest
/// mark, and one loop rebuilds the model, so a finish that moves three sources at once costs one or two
/// rebuilds and never two at a time.
///
/// **It owns no task and keeps no time.** The intents are synchronous and only change state; the observing is
/// a task group inside `run()`, which ends with the root's task. "Resume" counts in the view, from the
/// workout's start: one model serves until a source changes.
///
/// **Once loaded it is never loading again.** A later change goes from one loaded model to the next, and a new
/// `run()` (the tab came back, the app became active) keeps the model on screen until its own first one is
/// ready: the off-schedule sheet's list is read from the state on screen, so a pass through `loading` would
/// close it under the lifter's finger.
///
/// **A read that fails is shown** (`failed`), also over a model that was loaded: a stale day that looks
/// current would be worse. It is logged, and the next change or the next `run()` reads again.
///
/// **Making one does nothing.** `TodayRoot` makes a store each time SwiftUI makes the root and `@State` keeps
/// the first, so the initializer stays empty.
@MainActor @Observable
final class TodayStore {
    private(set) var state = Loadable<TodayModel>.idle
    /// The route `TodayRoot` hands the app next; nil once the app's handler has returned.
    private(set) var pendingRoute: TodayPendingRoute?

    @ObservationIgnored private var routeNumber = 0
    /// What the sources last said in this `run()`.
    @ObservationIgnored private var sources = TodaySources()

    @ObservationIgnored @Dependency(\.programRepository) private var programs
    @ObservationIgnored @Dependency(\.settingsRepository) private var settings
    @ObservationIgnored @Dependency(\.exerciseRepository) private var exercises
    @ObservationIgnored @Dependency(\.workoutRepository) private var workouts
    @ObservationIgnored @Dependency(\.statsQueries) private var stats
    @ObservationIgnored @Dependency(\.workoutSession) private var session
    @ObservationIgnored @Dependency(\.date) private var date
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8); a disabled logger stays disabled.
    private var logger: LedgerLogger {
        injectedLogger.category("today")
    }

    private typealias Mark = AsyncStream<Void>.Continuation

    // MARK: Intents

    /// A tap that asks the app to go somewhere. One route waits at a time: a tap that arrives before the app
    /// was handed the one before is dropped, so a double tap is one route.
    func send(_ route: TodayRoute) {
        guard pendingRoute == nil else {
            return
        }
        routeNumber += 1
        pendingRoute = TodayPendingRoute(number: routeNumber, route: route)
    }

    /// Hands the waiting route to `handler`, once, and forgets it when the handler has returned.
    func deliverRoute(to handler: (TodayRoute) -> Void) {
        guard let pending = pendingRoute else {
            return
        }
        handler(pending.route)
        pendingRoute = nil
    }

    // MARK: Work the root's task runs

    /// Shows today for as long as the task runs: the first model once every source has said what it holds,
    /// then a new one after each change. It returns when its task is cancelled.
    ///
    /// A run that starts while a model is on screen leaves it there until its own first model is ready, and
    /// reads everything again, which is how Today catches what no observation reports: a new day, and an
    /// older workout edited or deleted in History.
    func run() async {
        sources = TodaySources()
        if case .idle = state {
            state = .loading
        }
        let (marks, mark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followProgram(mark) }
            group.addTask { await self.followSettings(mark) }
            group.addTask { await self.followExercises(mark) }
            group.addTask { await self.followRecentWorkouts(mark) }
            group.addTask { await self.followSession(mark) }
            for await _ in marks {
                await rebuild()
            }
        }
    }
}

// MARK: - The five sources

extension TodayStore {
    private func followProgram(_ mark: Mark) async {
        await follow(programs.observeActive(), mark) { kept, program in
            kept.program = .some(program)
            kept.forgetHistory()
        }
    }

    private func followSettings(_ mark: Mark) async {
        await follow(settings.observe(), mark) { kept, value in
            kept.settings = value
            kept.forgetHistory()
        }
    }

    /// The exercises name the card's rows; no read depends on them.
    private func followExercises(_ mark: Mark) async {
        await follow(exercises.observeAll(), mark) { kept, all in
            kept.exercises = Dictionary(all.map { ($0.id, $0) }) { first, _ in first }
        }
    }

    /// A workout was finished, edited or deleted: the week's workouts and volumes may have changed with it.
    private func followRecentWorkouts(_ mark: Mark) async {
        await follow(workouts.observeRecent(limit: TodayHistory.recentLimit), mark) { kept, recent in
            kept.recentWorkouts = recent
            kept.forgetHistory()
        }
    }

    /// The session's workout as each update gives it: live, or ended in the one update that ends it. The
    /// first update arrives at once with the workout as it stands. A change to a live workout (a set logged
    /// under the cover) needs no read; the update that ends one does, because the workout is stored by then.
    ///
    /// Today reads `state` alone and never plays an update's haptics (F10's ruling: one subscriber plays
    /// them, on the workout's side). A session whose updates end is one with nothing live, as the key's stub
    /// is: the stream is not a store's observation, and Today works without it.
    private func followSession(_ mark: Mark) async {
        for await update in await session.updates() {
            guard !Task.isCancelled else {
                return
            }
            sources.session = .some(update.state)
            if update.live == nil {
                sources.forgetHistory()
            }
            mark.yield()
        }
        if !Task.isCancelled, sources.session == nil {
            sources.session = .some(nil)
            mark.yield()
        }
    }

    /// Keeps each value of a store's observation with `keep` and marks the change. An observation that ends
    /// while the task still runs has failed.
    private func follow<Value: Sendable>(
        _ values: AsyncStream<Value>,
        _ mark: Mark,
        keep: (inout TodaySources, Value) -> Void
    ) async {
        for await value in values {
            guard !Task.isCancelled else {
                return
            }
            keep(&sources, value)
            mark.yield()
        }
        if !Task.isCancelled {
            sources.hasEnded = true
            mark.yield()
        }
    }
}

// MARK: - The model

extension TodayStore {
    /// Makes the model from what the sources last said, once all five have spoken, reading the week's
    /// history first when it is not known. A model equal to the one on screen is not published again.
    private func rebuild() async {
        guard !sources.hasEnded else {
            logger.log.error("A store's observation ended while Today was on screen")
            state = .failed(TodayStoreError.observationEnded)
            return
        }
        guard let known = sources.known else {
            return
        }
        let now = date.now
        guard let history = await history(for: known, at: now) else {
            return
        }
        let model = TodayPresentation.make(known.input(history, now: now, calendar: calendar, locale: locale))
        if case let .loaded(shown) = state, shown == model {
            return
        }
        state = .loaded(model)
    }

    /// The plain reads for `known` at `now`: as last made, or made now. Nil when the read failed, which is
    /// logged and shown, and when the run's task was cancelled meanwhile, which shows nothing: the root went
    /// away, or a new run has taken over.
    private func history(for known: TodaySources.Known, at now: Date) async -> TodayHistory? {
        if let kept = sources.history {
            return kept
        }
        let staleCount = sources.staleCount
        let ranges = TodayHistory.ranges(program: known.program, settings: known.settings, now: now, calendar: calendar)
        do {
            let read = try await TodayHistory.read(ranges, workouts: workouts, stats: stats)
            guard !Task.isCancelled else {
                return nil
            }
            sources.keep(read, readSince: staleCount)
            return read
        } catch {
            guard !Task.isCancelled else {
                return nil
            }
            logger.log.error("Today could not be read: \(String(describing: error), privacy: .public)")
            state = .failed(error)
            return nil
        }
    }
}
