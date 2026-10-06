@testable import FeatureProgram
import Foundation
import LedgerTestSupport
import Testing

/// F11 S5 criterion 7: the wording of the builder's copy, through its copy file. That the texts live in the
/// catalog and in no other file is not this suite's to test: `ModuleCopyTests` audits every module's sources
/// and asks each built bundle for its catalog's keys, and the gate compares each catalog with the compiler's
/// keys.
@Suite("ProgramCopy", .tags(.feature))
nonisolated struct ProgramCopyTests {
    static let english = Fixtures.locale

    @Test("The plain texts are the brief's, word for word")
    func plainTexts_areTheBriefs() {
        #expect(ProgramCopy.myProgram == "MY PROGRAM")
        #expect(ProgramCopy.programName == "Program name")
        #expect(ProgramCopy.deloadMark == "DELOAD")
        #expect(ProgramCopy.tapToAssign == "Tap to assign")
        #expect(ProgramCopy.rest == "REST")
        #expect(ProgramCopy.firstWeek == "First week")
        #expect(ProgramCopy.applyToLaterWeeks == "Apply to later weeks")
        #expect(ProgramCopy.deload == "Deload")
        #expect(ProgramCopy.trainingDays == "TRAINING DAYS")
        #expect(
            ProgramCopy.sharedByEveryWeek
                == "Shared by every week. The schedule above decides which day you train, and when."
        )
        #expect(ProgramCopy.noExercisesYet == "No exercises yet")
        #expect(ProgramCopy.addTrainingDay == "+ Add training day")
        #expect(ProgramCopy.newDay == "New day")
        #expect(ProgramCopy.minimumTwoWeeks == "A block needs at least 2 weeks.")
        #expect(ProgramCopy.dayHasNoExercises == "Add at least one exercise before scheduling this day.")
    }

    @Test("The texts the brief does not give read as the notes list them")
    func writtenTexts_areTheNotes() {
        #expect(ProgramCopy.blockLength == "Block length")
        #expect(ProgramCopy.restSpoken == "Rest")
        #expect(ProgramCopy.assignHint == "Double-tap to assign")
        #expect(ProgramCopy.unknownExercise == "—")
        #expect(ProgramCopy.week(3, locale: Self.english) == "Week 3")
    }

    @Test("The texts with a number read as the brief writes them")
    func textsWithValues_areTheBriefs() {
        let locale = Self.english
        #expect(ProgramCopy.weekChip(3, locale: locale) == "W3")
        #expect(ProgramCopy.weekTitle(3, locale: locale) == "WEEK 3")
        #expect(ProgramCopy.copyWeek(2, locale: locale) == "Copy week 2")
        #expect(ProgramCopy.more(2, locale: locale) == "+2")
        #expect(ProgramCopy.estimate(minutes: 39, locale: locale) == "~39 min")
        #expect(ProgramCopy.estimate(minutes: 1, locale: locale) == "~1 min")
        #expect(
            ProgramCopy.weekHasLoggedSessions(8, locale: locale) == "Week 8 has logged sessions and can't be removed."
        )
    }

    @Test("A counted text takes the singular with one and the plural with none or several")
    func countedTexts_haveOneAndOther() {
        let locale = Self.english
        #expect([0, 1, 8].map { ProgramCopy.block(weeks: $0, locale: locale) }
            == ["BLOCK · 0 WEEKS", "BLOCK · 1 WEEK", "BLOCK · 8 WEEKS"])
        #expect([0, 1, 8].map { ProgramCopy.weeks($0, locale: locale) } == ["0 weeks", "1 week", "8 weeks"])
        #expect([0, 1, 4].map { ProgramCopy.scheduledDays($0, locale: locale) } == ["0 DAYS", "1 DAY", "4 DAYS"])
        #expect([0, 1, 4].map { ProgramCopy.days($0, locale: locale) } == ["0 days", "1 day", "4 days"])
        #expect([0, 1, 58].map { ProgramCopy.setsAWeek($0, locale: locale) }
            == ["0 sets a week", "1 set a week", "58 sets a week"])
        #expect([0, 1, 5].map { ProgramCopy.exercises($0, locale: locale) } == [
            "0 exercises",
            "1 exercise",
            "5 exercises"
        ])
        #expect([0, 1, 18].map { ProgramCopy.sets($0, locale: locale) } == ["0 sets", "1 set", "18 sets"])
    }

    @Test("A number is written in the locale handed in, and the locale's language picks the plural form")
    func values_followTheLocaleHandedIn() {
        // No translation ships yet, so the words stay English; the digits and the plural rule are the locale's.
        let arabic = Locale(identifier: "ar_EG")
        #expect(ProgramCopy.weekChip(3, locale: arabic) == "W٣")
        #expect(ProgramCopy.copyWeek(12, locale: arabic) == "Copy week ١٢")
        let german = Locale(identifier: "de_DE")
        #expect(ProgramCopy.setsAWeek(1234, locale: german) == "1.234 sets a week")
        #expect(ProgramCopy.setsAWeek(1234, locale: Self.english) == "1,234 sets a week")
        // French counts none as one.
        #expect(ProgramCopy.days(0, locale: Locale(identifier: "fr_FR")) == "0 day")
    }
}
