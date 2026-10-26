import LedgerDesign
import LedgerDomain
import SwiftUI

/// An exercise's history in the app (F12 S2): the screen over its store, pushed on whichever tab's stack asked
/// for it. It owns its store and runs its work from its tasks, as `LibraryRoot` does: the sources are followed
/// again when the app comes back from the background, and a session's route is handed to `onRoute` once.
public struct ExerciseHistoryRoot: View {
    @State private var store: ExerciseHistoryStore
    @Environment(\.scenePhase) private var scenePhase
    private let onRoute: @MainActor (LibraryRoute) -> Void

    public init(exercise: ExerciseID, onRoute: @escaping @MainActor (LibraryRoute) -> Void) {
        self.init(store: ExerciseHistoryStore(exercise: exercise), onRoute: onRoute)
    }

    /// For the tests, which keep the store to read what it shows.
    init(store: ExerciseHistoryStore, onRoute: @escaping @MainActor (LibraryRoute) -> Void) {
        _store = State(initialValue: store)
        self.onRoute = onRoute
    }

    public var body: some View {
        content
            .task(id: scenePhase == .background) {
                guard scenePhase != .background else {
                    return
                }
                await store.run()
            }
            .task(id: store.pendingRoute) {
                store.deliverRoute(to: onRoute)
            }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .loading:
            LedgerColor.ground.ignoresSafeArea()
        case let .loaded(model):
            ExerciseHistoryScreen(model: model, send: store.send)
        case .failed:
            EmptyState(LibraryCopy.historyFailedTitle, body: LibraryCopy.failedBody)
                .padding(LedgerSpacing.screen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(LedgerColor.ground)
        }
    }
}
