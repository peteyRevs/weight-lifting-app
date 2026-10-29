import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// A route on its way to the app: `HistoryRoot`'s `.task(id:)` hands it on. The number tells one tap from the next
/// when both ask for the same route.
nonisolated struct HistoryPendingRoute: Hashable, Sendable {
    let number: Int
    let route: HistoryRoute
}

/// The store of the History tab (F13 S1; the M1 store convention, as `LibraryStore`): the model the sources give,
/// and the route waiting for the app.
///
/// **Work** runs from `HistoryRoot`'s task: `run()` follows the workouts and the settings (`+Sources`). A source that
/// ends (an observation whose read failed among them) is logged and shows the failed state; the next run follows
/// again.
///
/// **Once loaded it is never loading again.** A new run (the tab came back, the app became active) keeps the model on
/// screen until its own first one is ready.
///
/// **A route waits until the app has taken it**, so a double tap is one route. **Making one does nothing**:
/// `HistoryRoot` makes a store each time SwiftUI makes the root and `@State` keeps the first.
@MainActor @Observable
final class HistoryStore {
    /// What the root draws.
    enum State: Equatable {
        case loading
        case loaded(HistoryModel)
        /// A source ended.
        case failed
    }

    private(set) var state = State.loading
    /// The route the root hands the app next; nil once the app's handler has returned.
    private(set) var pendingRoute: HistoryPendingRoute?

    /// What the sources last said in this run (`+Sources`).
    @ObservationIgnored var sources = HistorySources()
    @ObservationIgnored private var routeNumber = 0

    @ObservationIgnored @Dependency(\.workoutRepository) var workouts
    @ObservationIgnored @Dependency(\.settingsRepository) var settings
    @ObservationIgnored @Dependency(\.date) var date
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @Dependency(\.locale) var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8).
    var logger: LedgerLogger {
        injectedLogger.category("history")
    }

    // MARK: Intents

    /// A row's tap, or the empty list's "Go to Today". One route waits at a time: a tap that arrives before the app
    /// was handed the one before is dropped.
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

    /// Shows `model`, unless it is the one on screen.
    func show(_ model: HistoryModel) {
        if state != .loaded(model) {
            state = .loaded(model)
        }
    }

    /// Shows the failed state.
    func fail() {
        state = .failed
    }
}
