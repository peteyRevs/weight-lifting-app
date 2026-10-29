import LedgerDesign
import LedgerDomain
import SwiftUI

/// A past workout's detail in the app (F13 S2): the screen over its store, pushed on the stack of whichever tab asked
/// for it (F13 question 1, built to A). It owns its store and runs its work from its tasks, as `HistoryRoot` does: the
/// sources are followed again when the app comes back from the background, a route is handed to `onRoute` once, and
/// a confirmed delete runs from the task its number keys, so nothing outlives the view. A delete that failed is said
/// in an alert with one "OK".
public struct WorkoutDetailRoot: View {
    @State private var store: WorkoutDetailStore
    @Environment(\.scenePhase) private var scenePhase
    private let onRoute: @MainActor (HistoryRoute) -> Void

    public init(workout: WorkoutID, onRoute: @escaping @MainActor (HistoryRoute) -> Void) {
        self.init(store: WorkoutDetailStore(workout: workout), onRoute: onRoute)
    }

    /// For the tests, which keep the store to read what it shows. `@State` keeps the first store it is given: a store
    /// does no work when it is made.
    init(store: WorkoutDetailStore, onRoute: @escaping @MainActor (HistoryRoute) -> Void) {
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
            .task(id: store.deletion) {
                await store.delete()
            }
            .alert(HistoryCopy.deleteFailedTitle, isPresented: $store.showsDeleteFailure) {
                Button(HistoryCopy.okay) {}
            } message: {
                Text(HistoryCopy.deleteFailedBody)
            }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .loading, .gone:
            LedgerColor.ground.ignoresSafeArea()
        case let .loaded(model):
            WorkoutDetailScreen(model: model, send: store.send, onDelete: store.confirmDelete)
        case let .unreadable(model):
            UnreadableWorkout(model: model, onDelete: store.confirmDelete)
        }
    }
}
