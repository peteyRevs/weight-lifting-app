import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// A route on its way to the app: `LibraryRoot`'s `.task(id:)` hands it on. The number tells one tap from the
/// next when both ask for the same route.
nonisolated struct LibraryPendingRoute: Hashable, Sendable {
    let number: Int
    let route: LibraryRoute
}

/// The store of the Library tab (F12 S1; the M1 store convention): the filter, the rows the sources give, and the
/// route waiting for the app.
///
/// **Intents are synchronous and decide nothing.** Each action is applied as `LibraryAction` says, and the model
/// is made again before `send` returns: the search field reads its query back from the model, so typing would
/// lag behind a store that waited. A keystroke filters rows written when the sources last changed
/// (`LibraryPresentation.rows`); it formats none.
///
/// **Work** runs from `LibraryRoot`'s task: `run()` follows the sources (`+Sources`). A source that ends (an
/// observation whose read failed among them) is logged and shows the failed state; the next run follows again.
///
/// **Once loaded it is never loading again.** A new run (the tab came back, the app became active) keeps the
/// model on screen until its own first one is ready, so the field and the chips never flash away.
///
/// **Making one does nothing.** `LibraryRoot` makes a store each time SwiftUI makes the root and `@State` keeps
/// the first, so the initializer stays empty.
@MainActor @Observable
final class LibraryStore {
    /// What the root draws.
    enum State: Equatable {
        case loading
        case loaded(LibraryModel)
        /// A source ended or could not be read.
        case failed
    }

    private(set) var state = State.loading
    private(set) var filter = LibraryFilter()
    /// The route the root hands the app next; nil once the app's handler has returned.
    private(set) var pendingRoute: LibraryPendingRoute?
    /// "New exercise" was tapped and its sheet is up: `LibraryRoot` presents `CreateExerciseSheet` while it holds.
    private(set) var isNewExerciseShown = false

    /// What the sources last said in this run (`+Sources`), and the rows written from them.
    @ObservationIgnored var sources = LibrarySources()
    @ObservationIgnored var rows: LibraryPresentation.Rows?
    @ObservationIgnored private var routeNumber = 0

    @ObservationIgnored @Dependency(\.exerciseRepository) var exercises
    @ObservationIgnored @Dependency(\.settingsRepository) var settings
    @ObservationIgnored @Dependency(\.statsQueries) var stats
    @ObservationIgnored @Dependency(\.locale) var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8).
    var logger: LedgerLogger {
        injectedLogger.category("library")
    }

    // MARK: Intents

    func send(_ action: LibraryAction) {
        switch action {
        case let .setQuery(text):
            filter.query = text
        case let .setMuscle(muscle):
            filter.muscle = muscle
        case let .setEquipment(equipment):
            filter.equipment = equipment
        case .clearFilters:
            filter = LibraryFilter()
        case .newExercise:
            isNewExerciseShown = true
            return
        case .newExerciseClosed:
            isNewExerciseShown = false
            return
        case let .route(route):
            emit(route)
            return
        }
        // A filter changed: the screen shows it at once, unless it shows the failed state.
        if case .loaded = state {
            show()
        }
    }

    /// Hands the waiting route to `handler`, once, and forgets it when the handler has returned.
    func deliverRoute(to handler: (LibraryRoute) -> Void) {
        guard let pending = pendingRoute else {
            return
        }
        handler(pending.route)
        pendingRoute = nil
    }

    /// One route waits at a time: a tap that arrives before the app was handed the one before is dropped, so a
    /// double tap is one route.
    private func emit(_ route: LibraryRoute) {
        guard pendingRoute == nil else {
            return
        }
        routeNumber += 1
        pendingRoute = LibraryPendingRoute(number: routeNumber, route: route)
    }

    /// Shows the rows on hand under the filter. A model equal to the one on screen is not published again.
    func show() {
        guard let rows else {
            return
        }
        let model = LibraryPresentation.make(rows, filter: filter)
        if state != .loaded(model) {
            state = .loaded(model)
        }
    }

    /// Shows the failed state.
    func fail() {
        state = .failed
    }
}
