@testable import FeatureWorkout
import Foundation
import LedgerTestSupport
import Testing

/// F10 S4, criterion 8: the wording of the workout's copy, through its copy file. That the texts live in the
/// catalog and in no other file is not this suite's to test: `ModuleCopyTests` audits every module's sources
/// and asks each built bundle for its catalog's keys, and the gate compares each catalog with the compiler's
/// keys.
@Suite("WorkoutCopy", .tags(.feature))
nonisolated struct WorkoutCopyTests {
    @Test("The brief's texts are the brief's, word for word")
    func briefsTexts_areWordForWord() {
        #expect(WorkoutCopy.minimize == "Minimize")
        #expect(WorkoutCopy.finish == "Finish")
        #expect(WorkoutCopy.workoutInProgress == "You have a workout in progress")
        #expect(WorkoutCopy.resumeIt == "Resume it")
        #expect(WorkoutCopy.discardAndStartNew == "Discard and start new")
        #expect(WorkoutCopy.cancel == "Cancel")
        #expect(WorkoutCopy.endWorkout == "End workout?")
        #expect(WorkoutCopy.discard == "Discard")
        #expect(WorkoutCopy.keepLifting == "Keep lifting")
    }

    @Test("The texts the brief does not give read as the notes list them")
    func writtenTexts_areTheNotes() {
        #expect(WorkoutCopy.elapsedTime == "Elapsed time")
        #expect(WorkoutCopy.workoutProgress == "Workout progress")
        #expect(WorkoutCopy.okay == "OK")
        #expect(WorkoutCopy.close == "Close")
        #expect(WorkoutCopy.tryAgain == "Try again.")
        #expect(WorkoutCopy.couldNotStart == "Couldn't start this workout")
        #expect(WorkoutCopy.dayHasNoExercises == "This day has no exercises yet.")
        #expect(WorkoutCopy.dayNotInProgram == "This day is no longer in your program.")
        #expect(WorkoutCopy.blockEnded == "Your program's block has ended.")
        #expect(WorkoutCopy.nothingChanged == "Nothing was changed. Try again.")
        #expect(WorkoutCopy.couldNotStartNew == "Couldn't start the new workout")
        #expect(WorkoutCopy.liveWorkoutKept == "Your workout in progress was kept.")
        #expect(WorkoutCopy.liveWorkoutDiscarded == "Your workout in progress was discarded.")
        #expect(WorkoutCopy.couldNotOpen == "Couldn't open this workout")
        #expect(WorkoutCopy.closeAndTryAgain == "Close this screen and try again.")
        #expect(WorkoutCopy.couldNotDiscard == "Couldn't discard this workout")
        #expect(WorkoutCopy.stillInProgress == "It's still in progress. Try again.")
    }

    @Test("The exercise's place reads as the brief writes it, in the locale it is handed")
    func exercisePlace_readsAsTheBrief() {
        #expect(WorkoutCopy.exercise(1, of: 5, locale: Fixtures.locale) == "Exercise 1 of 5")
        #expect(WorkoutCopy.exercise(12, of: 12, locale: Fixtures.locale) == "Exercise 12 of 12")
        // The digits are the locale's, which the caller injects: the member writes none itself.
        #expect(WorkoutCopy.exercise(2, of: 5, locale: Locale(identifier: "ar_EG")) == "Exercise ٢ of ٥")
    }

    @Test("No text holds the product's name")
    func noText_namesTheProduct() throws {
        let catalog = try StringCatalog(module: "FeatureWorkout")
        #expect(catalog.keys.count == 27)
        #expect(!catalog.keys.contains { $0.localizedCaseInsensitiveContains("ledger") })
    }
}
