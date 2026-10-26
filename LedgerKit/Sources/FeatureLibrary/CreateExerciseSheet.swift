import LedgerDomain
import SwiftUI

/// The sheet that creates the lifter's own exercise, or edits one (F12 S3): the screen over its store. The Library's
/// root presents it for "New exercise" and the history's root for "Edit", each with `.sheet`; it owns its store and
/// runs the save from its task, so nothing outlives it. `onClose` takes it down: "Cancel", VoiceOver's escape, and a
/// save that went through. A sheet taken down while its save runs cancels the save, and a save cancelled before its
/// write stores nothing (N16). Each problem Save finds is announced to VoiceOver, as `ProgramRoot` announces its
/// notice (finding S3-6).
struct CreateExerciseSheet: View {
    @State private var store: CreateExerciseStore
    private let onClose: () -> Void
    private let announce: @MainActor (String) -> Void

    init(editing exercise: Exercise?, onClose: @escaping () -> Void) {
        self.init(store: CreateExerciseStore(editing: exercise), onClose: onClose)
    }

    /// For the tests, which keep the store to read what it shows and hear what is announced. `@State` keeps the first
    /// store it is given.
    init(
        store: CreateExerciseStore,
        onClose: @escaping () -> Void,
        announce: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        _store = State(initialValue: store)
        self.onClose = onClose
        self.announce = announce
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
            .onChange(of: store.problemNumber) {
                // The line may stand off screen, or behind the lifter's finger on Save (finding S3-6).
                if let line = store.model.announcement {
                    announce(line)
                }
            }
    }
}
