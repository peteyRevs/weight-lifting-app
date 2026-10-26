import LedgerDesign
import LedgerDomain
import SwiftUI

/// An exercise's history in the app (F12 S2): the screen over its store, pushed on whichever tab's stack asked
/// for it. It owns its store and runs its work from its tasks, as `LibraryRoot` does: the sources are followed
/// again when the app comes back from the background, and a session's route is handed to `onRoute` once. "Edit", on
/// the lifter's own exercise, opens `CreateExerciseSheet` on it (F12 S3).
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
            .sheet(item: editedExercise) { exercise in
                CreateExerciseSheet(editing: exercise) { store.editClosed() }
            }
    }

    /// "Edit"'s sheet (F12 S3, criterion 10): up while the store holds the exercise, and the store told when it goes
    /// down, by its own buttons or by the system.
    private var editedExercise: Binding<Exercise?> {
        Binding { store.editedExercise } set: { exercise in
            if exercise == nil {
                store.editClosed()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .loading:
            LedgerColor.ground.ignoresSafeArea()
        case let .loaded(model):
            ExerciseHistoryScreen(model: model, send: store.send, onEdit: store.edit)
        case .failed:
            EmptyState(LibraryCopy.historyFailedTitle, body: LibraryCopy.failedBody)
                .padding(LedgerSpacing.screen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(LedgerColor.ground)
        }
    }
}
