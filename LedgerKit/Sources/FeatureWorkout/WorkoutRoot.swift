import SwiftUI

/// The cover's content (F10 S4): the live workout as the session shows it, with the finish dialog and the
/// alert of a discard that failed. It owns the store and runs its work: following the session for as long
/// as the cover is up, and the discard, each from a `.task`, so both end with the view.
///
/// It closes nothing itself. When the store says the cover is done (`WorkoutStore.exit`), `onExit` tells
/// the launcher, which takes the cover down and hands the app its route.
struct WorkoutRoot: View {
    @State private var store: WorkoutStore
    private let onExit: @MainActor (WorkoutExit) -> Void

    init(onExit: @escaping @MainActor (WorkoutExit) -> Void) {
        self.init(store: WorkoutStore(), onExit: onExit)
    }

    /// For the tests, which keep the store to send it what a tap sends. `@State` keeps the first store it is
    /// given: a store does no work when it is made.
    init(store: WorkoutStore, onExit: @escaping @MainActor (WorkoutExit) -> Void) {
        _store = State(initialValue: store)
        self.onExit = onExit
    }

    var body: some View {
        let finish = WorkoutPresentation.finishDialog
        let failure = WorkoutPresentation.discardFailedAlert
        WorkoutScreen(model: store.model, send: store.send)
            .confirmationDialog(
                finish.title,
                isPresented: shows(.finish, else: .keepLifting),
                titleVisibility: .visible
            ) {
                Button(finish.discard, role: .destructive) { store.send(.discard) }
                    .accessibilityIdentifier("workout.finish.discard")
                // No cancel role: the system draws no cancelling button in a dialog (iOS 26 on), and the brief
                // asks for this one. Tapping outside the dialog still returns to the workout.
                Button(finish.keepLifting) { store.send(.keepLifting) }
                    .accessibilityIdentifier("workout.finish.keep")
            }
            .alert(failure.title, isPresented: shows(.discardFailed, else: .dismissFailure)) {
                Button(failure.dismiss) { store.send(.dismissFailure) }
            } message: {
                Text(failure.message)
            }
            .task {
                await store.follow()
            }
            .task(id: store.discardAttempt) {
                await store.discard()
            }
            .onChange(of: store.exit) { _, exit in
                if let exit {
                    onExit(exit)
                }
            }
    }

    /// Whether `dialog` is the one showing. When the system takes it down by itself, the store is sent
    /// `dismissal`, which is what its cancelling button sends.
    private func shows(_ dialog: WorkoutStore.Dialog, else dismissal: WorkoutAction) -> Binding<Bool> {
        Binding {
            store.dialog == dialog
        } set: { isShown in
            if !isShown {
                store.send(dismissal)
            }
        }
    }
}
