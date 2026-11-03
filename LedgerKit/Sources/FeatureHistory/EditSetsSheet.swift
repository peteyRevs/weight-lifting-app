import LedgerDesign
import SwiftUI

/// The sheet that fixes a past workout's sets (F13 S3): the screen over its store, presented by `WorkoutDetailRoot`. It
/// owns its store and runs the save from its task, so nothing outlives it. `onClose` takes it down, saying how:
/// "Cancel" or VoiceOver's escape, a save that went through (with the draft it stored), and the "OK" of the alert that
/// says the workout was deleted. While a save runs no swipe takes it down. A failed save's line is also announced to
/// VoiceOver: it stands at the foot, perhaps behind the lifter's finger on "Save".
struct EditSetsSheet: View {
    @State private var store: EditSetsStore
    private let onClose: (EditSetsClosing) -> Void
    private let announce: @MainActor (String) -> Void

    init(request: EditSetsRequest, onClose: @escaping (EditSetsClosing) -> Void) {
        self.init(store: EditSetsStore(request), onClose: onClose)
    }

    /// For the tests, which keep the store to read what it shows and hear what is announced. `@State` keeps the first
    /// store it is given.
    init(
        store: EditSetsStore,
        onClose: @escaping (EditSetsClosing) -> Void,
        announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        _store = State(initialValue: store)
        self.onClose = onClose
        self.announce = announce
    }

    var body: some View {
        let model = store.model
        EditSetsScreen(model: model, send: store.send) {
            if store.canClose {
                onClose(.cancelled)
            }
        }
        .task(id: store.attempt) {
            await store.save()
        }
        .interactiveDismissDisabled(!model.isEnabled)
        .onChange(of: store.phase == .saved) { _, isSaved in
            if isSaved {
                onClose(.saved(store.draft))
            }
        }
        .onChange(of: model.foot.problem) { _, problem in
            if let problem {
                announce(problem)
            }
        }
        .alert(
            model.workoutGone?.title ?? "",
            isPresented: .constant(model.workoutGone != nil),
            presenting: model.workoutGone
        ) { gone in
            Button(gone.okay) { onClose(.workoutGone) }
        } message: { gone in
            Text(gone.message)
        }
    }
}
