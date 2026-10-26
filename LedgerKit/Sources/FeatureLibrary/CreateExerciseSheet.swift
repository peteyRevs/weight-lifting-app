import LedgerDomain
import SwiftUI

/// The sheet that creates the lifter's own exercise, or edits one (F12 S3): the screen over its store. The Library's
/// root presents it for "New exercise" and the history's root for "Edit", each with `.sheet`; it owns its store and
/// runs the save from its task, so nothing outlives it. `onClose` takes it down: "Cancel", VoiceOver's escape, and a
/// save that went through. A sheet taken down while its save runs cancels the save, and a save cancelled before its
/// write stores nothing (N16).
struct CreateExerciseSheet: View {
    @State private var store: CreateExerciseStore
    private let onClose: () -> Void

    init(editing exercise: Exercise?, onClose: @escaping () -> Void) {
        self.init(store: CreateExerciseStore(editing: exercise), onClose: onClose)
    }

    /// For the tests, which keep the store to read what it shows. `@State` keeps the first store it is given.
    init(store: CreateExerciseStore, onClose: @escaping () -> Void) {
        _store = State(initialValue: store)
        self.onClose = onClose
    }

    var body: some View {
        CreateExerciseScreen(model: store.model, send: store.send, onCancel: onClose)
            .task(id: store.attempt) {
                await store.save()
            }
            .onChange(of: store.phase == .saved) { _, isSaved in
                if isSaved {
                    onClose()
                }
            }
    }
}
