import LedgerDesign
import LedgerDomain
import SwiftUI

/// The Day editor in the app (F11 S14, criterion 20): the screen over its store, pushed on the Program tab's
/// stack for one day of the active program and the week the builder had selected. It owns the store and runs
/// its work from its tasks, so nothing outlives the view: the sources, followed again when the app comes back
/// from the background as `ProgramRoot` follows its own, and the session's save loop, which is not keyed, so
/// going to the background never cancels a write.
///
/// The screen draws its own bar, so the navigation bar is hidden; the system's swipe back stays and pops at
/// once, which cancels a write in flight whole (ruling R5). "Done" and "Program" ask the app to pop the
/// editor through `onRoute`, once nothing waits to be stored. The content is keyed by the day, so a name's
/// draft, a focus or a delete confirmation never passes to another day drawn in its place (ruling R8).
///
/// It presents the exercise library as a sheet on "+ Add exercise from library"; a swipe down is its
/// "Cancel". A change that could not be saved is said in an alert with one "OK" (Pete's question 1, A);
/// "Delete day" asks in the page's own alert (question 3, A).
public struct DayEditorRoot: View {
    @State private var store: DayEditorStore
    @Environment(\.scenePhase) private var scenePhase
    private let onRoute: @MainActor (ProgramRoute) -> Void

    public init(day: DayTemplateID, weekIndex: Int, onRoute: @escaping @MainActor (ProgramRoute) -> Void) {
        self.init(store: DayEditorStore(day: day, weekIndex: weekIndex), onRoute: onRoute)
    }

    /// For the tests, which keep the store to read what it shows. `@State` keeps the first store it is given:
    /// a store does no work when it is made.
    init(store: DayEditorStore, onRoute: @escaping @MainActor (ProgramRoute) -> Void) {
        _store = State(initialValue: store)
        self.onRoute = onRoute
    }

    public var body: some View {
        content
            .hidesTheNavigationBar()
            .task(id: scenePhase == .background) {
                guard scenePhase != .background else {
                    return
                }
                await store.run()
            }
            .task {
                await store.save()
            }
            .task(id: store.pendingRoute) {
                store.deliverRoute(to: onRoute)
            }
            .sheet(isPresented: isLibraryShown) {
                if let model = store.libraryModel {
                    ExercisePickerScreen(model: model, send: store.send)
                }
            }
            .alert(ProgramCopy.saveFailed, isPresented: $store.showsSaveFailure) {
                Button(ProgramCopy.okay) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading, .dayIsGone:
            LedgerColor.ground.ignoresSafeArea()
        case let .editing(model):
            DayEditorScreen(model: model, send: store.send)
                .id(model.id)
        case .failed:
            ProgramMessage(title: ProgramCopy.failedTitle, text: ProgramCopy.failedBody)
        }
    }

    /// The sheet is up while the library's store says so; a swipe down is "Cancel".
    private var isLibraryShown: Binding<Bool> {
        Binding {
            store.library.isShown
        } set: { isShown in
            if !isShown, store.library.isShown {
                store.send(ExercisePickerAction.cancel)
            }
        }
    }
}

private extension View {
    /// The Day editor draws its own bar over the page.
    func hidesTheNavigationBar() -> some View {
        #if os(iOS)
            toolbarVisibility(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }
}
