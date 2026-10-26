import Foundation
import LedgerDomain

/// The intents of `WorkoutStore`: `send(_:)`, the one place that decides what a tap changes. In a file of its
/// own for the store's length (F10 S7b); the members of the store it uses are the store's alone.
extension WorkoutStore {
    func send(_ action: WorkoutAction) {
        // Nothing answers once the cover is closing, or while a discard or a save runs; "Done" and a row
        // alone answer on the receipt.
        guard exit == nil, exitWhenDrained == nil, !isDiscarding, !isSaving, saved == nil || action.isReceipts else {
            return
        }
        switch action {
        case .minimize:
            minimize()
        case .finish:
            show(.finish)
        case .keepLifting, .dismissFailure, .dismissed:
            dismiss(dialogs(closedBy: action))
        case .save:
            startSave()
        case .discard:
            startDiscard()
        case .retrySave:
            retrySave()
        case let .edit(edit):
            enqueue(edit)
        case .done:
            closeReceipt()
        case let .openExercise(exercise):
            closeReceipt(showing: exercise)
        }
    }

    /// Whether a workout is on screen: only then is there something to finish, discard or change.
    var isShowingWorkout: Bool {
        if case .loaded = workout {
            return true
        }
        return false
    }

    private func show(_ asked: Dialog) {
        if isShowingWorkout {
            dialog = asked
        }
    }

    /// The dialogs a dismissal takes down: "Keep lifting" the sheet; the "OK" of a discard or a change that
    /// failed, and the "Close" of a save that did, whichever alert shows; the system's own dismissal, the
    /// dialog it took down and no other.
    private func dialogs(closedBy action: WorkoutAction) -> [Dialog] {
        switch action {
        case .keepLifting: [.finish]
        case let .dismissed(dialog): [dialog]
        default: [.discardFailed, .editFailed, .saveFailed]
        }
    }

    /// Takes the dialog down when it is one of `dialogs`.
    func dismiss(_ dialogs: [Dialog]) {
        if let shown = dialog, dialogs.contains(shown) {
            dialog = nil
        }
    }
}

extension WorkoutAction {
    /// The receipt's own actions: "Done" and a row. Each closes the cover as saved, and only the receipt sends them.
    var isReceipts: Bool {
        switch self {
        case .done, .openExercise: true
        default: false
        }
    }
}
