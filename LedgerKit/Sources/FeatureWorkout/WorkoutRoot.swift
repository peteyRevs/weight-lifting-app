import SwiftUI

/// The cover's content (F10 S4, S5): the live workout as the session shows it, with the "End workout?" sheet
/// (F10 S7) and the alerts of a discard, a change and a save that failed. It owns the store and runs its
/// work: following the session and applying the page's taps for as long as the cover is up, the discard,
/// the save, and the shown rest's time (F10 S6), each from a `.task`, so all end with the view.
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
        let failure = WorkoutPresentation.discardFailedAlert
        let refusal = WorkoutPresentation.editFailedAlert
        let unsaved = WorkoutPresentation.saveFailedAlert
        WorkoutScreen(model: store.model, send: store.send) {
            StoreRestPanel(store: store)
        }
        // Product default O1: "End workout?" asks in a sheet. A swipe down, a tap outside it and
        // VoiceOver's escape are "Keep lifting".
        .sheet(isPresented: shows(.finish, else: .keepLifting)) {
            StoreFinishSheet(store: store)
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
        // A save that failed, in two alerts that take turns by the attempt's number: "Try again" can fail
        // again before the alert it was tapped on has gone, and one alert asked to go and come back at once
        // may not come back. Only its two buttons take either down: the system's own word that it went
        // is not passed on, since it can arrive after the next failure and would close that one's alert.
        .saveFailedAlert(unsaved, isPresented: shows(.saveFailed, else: nil, when: isEvenAttempt), send: store.send)
        .saveFailedAlert(unsaved, isPresented: shows(.saveFailed, else: nil, when: !isEvenAttempt), send: store.send)
        .task {
            await store.follow()
        }
        .task {
            await store.pump()
        }
        .task(id: store.discardAttempt) {
            await store.discard()
        }
        .task(id: store.saveAttempt) {
            await store.save()
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

    private var isEvenAttempt: Bool {
        store.saveAttempt.isMultiple(of: 2)
    }

    /// Whether `dialog` is the one showing, and `isTurn` holds. When the system takes it down by itself,
    /// the store is sent `dismissal`, which is what its cancelling button sends; with none, only the store
    /// takes it down.
    private func shows(
        _ dialog: WorkoutStore.Dialog,
        else dismissal: WorkoutAction?,
        when isTurn: Bool = true
    ) -> Binding<Bool> {
        Binding {
            store.dialog == dialog && isTurn
        } set: { isShown in
            if !isShown, let dismissal {
                store.send(dismissal)
            }
        }
    }
}

private extension View {
    /// "Couldn't save this workout", with "Try again" and "Close" (and no "Discard": product default O3).
    func saveFailedAlert(
        _ model: WorkoutSaveFailedModel,
        isPresented: Binding<Bool>,
        send: @escaping (WorkoutAction) -> Void
    ) -> some View {
        alert(model.title, isPresented: isPresented) {
            Button(model.retry) { send(.retrySave) }
            Button(model.close, role: .cancel) { send(.dismissFailure) }
        } message: {
            Text(model.message)
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

/// The "End workout?" sheet of the store's workout. Its body reads `WorkoutStore.finishSheet`, so the sheet
/// follows the workout while it is up: a tap that lands, a set logged elsewhere, a save that starts.
struct StoreFinishSheet: View {
    let store: WorkoutStore

    var body: some View {
        if let model = store.finishSheet {
            FinishSheet(model: model, send: store.send)
        }
    }
}
