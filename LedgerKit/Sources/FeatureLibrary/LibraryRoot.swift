import LedgerDesign
import SwiftUI

/// The Library tab in the app (F12 S1): the screen over its store. It owns the store and runs its work from its
/// tasks, so nothing outlives the view; the app hands it `onRoute`, which resolves where a row's tap goes
/// (architecture §4).
///
/// **The sources are followed again when the app comes back from the background**, as `TodayRoot` follows
/// Today's: the task's id changes on the way there and on the way back, and at no other change of the scene's
/// phase, and SwiftUI restarts it when the tab comes back on screen. A view hosted with no scene (a package
/// test's window) is told it is in the background, and follows nothing until its host says otherwise.
///
/// **A route is handed on once.** The screen's taps go to the store, which keeps one route waiting; the task
/// below hands it to the app and the store forgets it when the app's handler has returned.
public struct LibraryRoot: View {
    @State private var store: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    private let onRoute: @MainActor (LibraryRoute) -> Void

    public init(onRoute: @escaping @MainActor (LibraryRoute) -> Void) {
        self.init(store: LibraryStore(), onRoute: onRoute)
    }

    /// For the tests, which keep the store to read what it shows. `@State` keeps the first store it is given: a
    /// store does no work when it is made.
    init(store: LibraryStore, onRoute: @escaping @MainActor (LibraryRoute) -> Void) {
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
            LibraryScreen(model: model, send: store.send)
        case .failed:
            EmptyState(LibraryCopy.failedTitle, body: LibraryCopy.failedBody)
                .padding(LedgerSpacing.screen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(LedgerColor.ground)
        }
    }
}
