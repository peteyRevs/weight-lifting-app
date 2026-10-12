import SwiftUI

/// The cover's content (F10 S4, S5): the live workout as the session shows it, with the finish dialog and the
/// alerts of a discard and of a change that failed. It owns the store and runs its work: following the
/// session and applying the page's taps for as long as the cover is up, the discard, and the shown rest's
/// time (F10 S6), each from a `.task`, so all end with the view.
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
        let refusal = WorkoutPresentation.editFailedAlert
        WorkoutScreen(model: store.model, send: store.send) {
            StoreRestPanel(store: store)
        }
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
        .alert(refusal.title, isPresented: shows(.editFailed, else: .dismissFailure)) {
            Button(refusal.dismiss) { store.send(.dismissFailure) }
        } message: {
            Text(refusal.message)
        }
        .task {
            await store.follow()
        }
        .task {
            await store.pump()
        }
        .task(id: store.discardAttempt) {
            await store.discard()
        }
        .task(id: store.shownRest) {
            await store.keepRestTime()
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

/// The rest panel of the store's workout, in the screen's bottom inset. Its body is the one place that
/// reads `WorkoutStore.restPanel`, and so the one view drawn again at each second of a rest: the root's
/// body, the header and the page read `model`, which a tick does not change (F10 S6, criterion 16).
struct StoreRestPanel: View {
    let store: WorkoutStore

    var body: some View {
        if let rest = store.restPanel {
            PlacedRestPanel(model: rest, send: store.send)
        }
    }
}
