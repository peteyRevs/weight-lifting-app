@testable import FeatureWorkout
import Foundation
import LedgerTestSupport
import Testing

/// F10 S4, criteria 4, 5, 15 and 16: the words of the two dialogs and of every failure, as the presentation
/// makes them.
@Suite("WorkoutPresentation dialogs", .tags(.feature))
struct WorkoutPresentationDialogTests {
    @Test("The two dialogs read as the brief writes them")
    func dialogs_areTheBriefs() {
        #expect(WorkoutPresentation.conflictDialog == WorkoutConflictDialogModel(
            title: "You have a workout in progress",
            resume: "Resume it",
            replace: "Discard and start new",
            cancel: "Cancel"
        ))
        #expect(WorkoutPresentation.finishDialog == WorkoutFinishDialogModel(
            title: "End workout?",
            discard: "Discard",
            keepLifting: "Keep lifting"
        ))
        #expect(WorkoutPresentation.discardFailedAlert == WorkoutAlertModel(
            title: "Couldn't discard this workout",
            message: "It's still in progress. Try again.",
            dismiss: "OK"
        ))
    }

    @Test("Every failure of the launcher has its title and its line, and says what is live afterwards", arguments: [
        (WorkoutLaunchFailure.notStarted(.emptyDay), "Couldn't start this workout", "This day has no exercises yet."),
        (.notStarted(.dayNotInProgram), "Couldn't start this workout", "This day is no longer in your program."),
        (.notStarted(.blockEnded), "Couldn't start this workout", "Your program's block has ended."),
        (.notStarted(.other), "Couldn't start this workout", "Nothing was changed. Try again."),
        (.notStarted(.unknown), "Couldn't start this workout", "Try again."),
        (.notReplaced(.liveKept), "Couldn't start the new workout", "Your workout in progress was kept."),
        (.notReplaced(.nothingLive), "Couldn't start the new workout", "Your workout in progress was discarded."),
        (.notReplaced(.unknown), "Couldn't start the new workout", "Try again."),
        (.notOpened, "Couldn't open this workout", "Try again.")
    ])
    func alert_saysWhatFailedAndWhatIsLeft(failure: WorkoutLaunchFailure, title: String, message: String) {
        #expect(
            WorkoutPresentation.alert(for: failure) == WorkoutAlertModel(title: title, message: message, dismiss: "OK")
        )
    }
}
