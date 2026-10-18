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

    @Test("The card's texts are the brief's, word for word (F10 S5)")
    func cardsTexts_areWordForWord() {
        let locale = Fixtures.locale
        #expect(WorkoutCopy.target == "TARGET")
        #expect(WorkoutCopy
            .targetPounds(sets: 5, reps: 5, load: "185", rpe: "8", locale: locale) == "5 × 5 @ 185 lb · RPE 8")
        #expect(
            WorkoutCopy.targetKilograms(sets: 3, reps: 12, load: "42.5", rpe: "8.5", locale: locale)
                == "3 × 12 @ 42.5 kg · RPE 8.5"
        )
        #expect(WorkoutCopy.last == "Last")
        #expect(WorkoutCopy.noHistoryYet == "No history yet")
        #expect(WorkoutCopy.repeatLast == "Repeat")
        #expect(WorkoutCopy.numberColumn == "#")
        #expect(WorkoutCopy.repsColumn == "reps")
        #expect(WorkoutCopy.unit(.lb) == "lb")
        #expect(WorkoutCopy.unit(.kg) == "kg")
        #expect(WorkoutCopy.dropSetLabel == "D")
        #expect(WorkoutCopy.weightStep("5", units: .lb, locale: locale) == "5 LB")
        #expect(WorkoutCopy.weightStep("1.25", units: .kg, locale: locale) == "1.25 KG")
        #expect(WorkoutCopy.repStep == "1 REP")
        #expect(WorkoutCopy.addSet == "+ Add set")
        #expect(WorkoutCopy.remaining == "REMAINING")
        #expect(WorkoutCopy.scheme(sets: 5, reps: 5, locale: locale) == "5 × 5")
    }

    @Test("The spoken texts and the failed change read as the notes list them (F10 S5)")
    func spokenTexts_areTheNotes() {
        let locale = Fixtures.locale
        #expect(WorkoutCopy.spokenSet(2, locale: locale) == "Set 2")
        #expect(WorkoutCopy.spokenDropSet == "Drop set")
        #expect(WorkoutCopy.spokenWeight("185", units: .lb, locale: locale) == "185 pounds")
        #expect(WorkoutCopy.spokenWeight("52.5", units: .kg, locale: locale) == "52.5 kilograms")
        #expect(WorkoutCopy.logSet(2, locale: locale) == "Log set 2")
        #expect(WorkoutCopy.undoSet(2, locale: locale) == "Undo set 2")
        #expect(WorkoutCopy.logDropSet == "Log drop set")
        #expect(WorkoutCopy.undoDropSet == "Undo drop set")
        #expect(WorkoutCopy.couldNotSaveChange == "Couldn't save that change")
    }

    /// Criterion 11. The words are the catalog's, which holds English, so the form is English's whatever the
    /// lifter's language: French counts 0 as one and Japanese has no singular, and with the lifter's own
    /// locale the lookup gave "0 rep" and "1 reps". The digits stay the lifter's.
    @Test(
        "A count of reps takes its plural form by the catalog's language, and its digits by the lifter's",
        arguments: [
            ("en_US", 1, "1 rep"), ("en_US", 0, "0 reps"), ("en_US", 5, "5 reps"),
            ("fr_FR", 0, "0 reps"), ("fr_FR", 1, "1 rep"), ("ja_JP", 1, "1 rep"), ("ru_RU", 21, "21 reps"),
            ("ar_EG", 2, "٢ reps"), ("ar_EG", 1, "١ rep")
        ]
    )
    func reps_takeTheCatalogsPluralForm(identifier: String, count: Int, wanted: String) {
        #expect(WorkoutCopy.spokenReps(count, locale: Locale(identifier: identifier)) == wanted)
    }

    @Test("The rest panel's texts: the brief's word for word, and those it does not give as the notes list them")
    func restTexts() {
        let locale = Fixtures.locale
        #expect(WorkoutCopy.extendRest == "+30s")
        #expect(WorkoutCopy.skipRest == "Skip rest")
        #expect(WorkoutCopy.restOver == "Rest over")
        #expect(WorkoutCopy
            .nextSet(number: 3, weight: "185", reps: 5, units: .lb, locale: locale) == "Set 3 · 185 lb × 5")
        // Not given by the brief: the prototype's line without the watch, the spoken "+30s", kilograms and
        // a drop set.
        #expect(WorkoutCopy.resting == "Resting")
        #expect(WorkoutCopy.extendRestLabel == "Add 30 seconds")
        let kilograms = WorkoutCopy.nextSet(number: 3, weight: "82.5", reps: 5, units: .kg, locale: locale)
        #expect(kilograms == "Set 3 · 82.5 kg × 5")
        let drop = WorkoutCopy.nextSet(number: nil, weight: "150", reps: 8, units: .lb, locale: locale)
        #expect(drop == "Drop set · 150 lb × 8")
        let dropInKilograms = WorkoutCopy.nextSet(number: nil, weight: "70", reps: 8, units: .kg, locale: locale)
        #expect(dropInKilograms == "Drop set · 70 kg × 8")
        // The digits are the locale's, which the caller injects.
        let arabic = Locale(identifier: "ar_EG")
        #expect(WorkoutCopy
            .nextSet(number: 3, weight: "185", reps: 5, units: .lb, locale: arabic) == "Set ٣ · 185 lb × ٥")
    }

    @Test("The sheet's, the failed save's and the announcement's texts, word for word (F10 S7a)")
    func finishTexts_areWordForWord() {
        let locale = Fixtures.locale
        #expect(WorkoutCopy.saveWorkout == "Save workout")
        #expect(WorkoutCopy.setsLogged(done: "23", of: 25, locale: locale) == "23 of 25 sets logged")
        #expect(WorkoutCopy.setsLogged(done: "0", of: 1, locale: locale) == "0 of 1 set logged")
        #expect(WorkoutCopy.setsLogged(done: "0", of: 0, locale: locale) == "0 of 0 sets logged")
        #expect(WorkoutCopy.moved("24,180", units: .lb, locale: locale) == "24,180 lb moved")
        #expect(WorkoutCopy.moved("10,968", units: .kg, locale: locale) == "10,968 kg moved")
        #expect(WorkoutCopy.couldNotSaveWorkout == "Couldn't save this workout")
        #expect(WorkoutCopy.stillOnThisPhone == "It's still on this iPhone. Try again.")
        #expect(WorkoutCopy.tryAgainButton == "Try again")
        #expect(WorkoutCopy.restRemaining("1 minute, 30 seconds", locale: locale)
            == "Rest, 1 minute, 30 seconds remaining")
        // A language with other plural rules takes the catalog's form, not its own (the catalog is English).
        #expect(WorkoutCopy.setsLogged(done: "1", of: 1, locale: Locale(identifier: "ar_EG")).hasSuffix("set logged"))
    }

    @Test("The receipt's texts, word for word, and the records line in both its forms (F10 S7b)")
    func receiptTexts_areWordForWord() {
        let locale = Fixtures.locale
        let plain = [
            WorkoutCopy.done, WorkoutCopy.timeTile, WorkoutCopy.setsTile, WorkoutCopy.movedTile(units: .lb),
            WorkoutCopy.movedTile(units: .kg), WorkoutCopy.logged, WorkoutCopy.prescribedOnTheRight,
            WorkoutCopy.spokenNothingLogged
        ]
        #expect(plain == [
            "Done", "TIME", "SETS", "LB MOVED", "KG MOVED", "LOGGED", "Prescribed on the right", "Nothing logged"
        ])
        #expect(WorkoutCopy.newRecords(1, locale: locale) == "1 new PR this session")
        #expect(WorkoutCopy.newRecords(3, locale: locale) == "3 new PRs this session")
        #expect(WorkoutCopy.newRecords(1234, locale: locale) == "1,234 new PRs this session")
        #expect(WorkoutCopy.spokenPrescribed("5 × 5 @ 185 lb", locale: locale) == "Prescribed 5 × 5 @ 185 lb")
        #expect(WorkoutCopy.spokenLogged("5 × 185×5, 185×4", locale: locale) == "Logged 5 × 185×5, 185×4")
    }

    @Test("No text holds the product's name")
    func noText_namesTheProduct() throws {
        let catalog = try StringCatalog(module: "FeatureWorkout")
        #expect(catalog.keys.count == 82)
        #expect(!catalog.keys.contains { $0.localizedCaseInsensitiveContains("ledger") })
    }
}
