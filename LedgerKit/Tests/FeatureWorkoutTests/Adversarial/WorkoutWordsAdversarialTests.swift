@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S4 criterion 8: every text of the slice, character for character; the catalog holds these and
/// no other; no source file reads an ambient clock, calendar, locale or zone, or starts a task of its own.
@MainActor
@Suite("Workout words (adversarial)", .tags(.feature))
struct WorkoutWordsAdversarialTests {
    /// The brief's "Copy (exact)" for what this slice draws, and the dialogs' texts of criteria 2 and 10.
    @Test("The texts the brief gives are the brief's, character for character")
    func briefTexts_areExact() {
        #expect(WorkoutCopy.minimize == "Minimize")
        #expect(WorkoutCopy.finish == "Finish")
        #expect(WorkoutCopy.exercise(2, of: 5, locale: Fixtures.locale) == "Exercise 2 of 5")
        #expect(WorkoutCopy.workoutInProgress == "You have a workout in progress")
        #expect(WorkoutCopy.resumeIt == "Resume it")
        #expect(WorkoutCopy.discardAndStartNew == "Discard and start new")
        #expect(WorkoutCopy.cancel == "Cancel")
        #expect(WorkoutCopy.endWorkout == "End workout?")
        #expect(WorkoutCopy.discard == "Discard")
        #expect(WorkoutCopy.keepLifting == "Keep lifting")
    }

    /// The seventeen the brief does not give, pinned so that a change is seen (test-findings lists each
    /// with when it shows).
    @Test("The texts the brief does not give are the ones the findings list")
    func otherTexts_arePinned() {
        let texts = [
            WorkoutCopy.elapsedTime, WorkoutCopy.workoutProgress, WorkoutCopy.okay, WorkoutCopy.close,
            WorkoutCopy.tryAgain, WorkoutCopy.couldNotStart, WorkoutCopy.dayHasNoExercises,
            WorkoutCopy.dayNotInProgram, WorkoutCopy.blockEnded, WorkoutCopy.nothingChanged,
            WorkoutCopy.couldNotStartNew, WorkoutCopy.liveWorkoutKept, WorkoutCopy.liveWorkoutDiscarded,
            WorkoutCopy.couldNotOpen, WorkoutCopy.closeAndTryAgain, WorkoutCopy.couldNotDiscard,
            WorkoutCopy.stillInProgress
        ]
        let expected = [
            "Elapsed time", "Workout progress", "OK", "Close",
            "Try again.", "Couldn't start this workout", "This day has no exercises yet.",
            "This day is no longer in your program.", "Your program's block has ended.",
            "Nothing was changed. Try again.",
            "Couldn't start the new workout", "Your workout in progress was kept.",
            "Your workout in progress was discarded.",
            "Couldn't open this workout", "Close this screen and try again.", "Couldn't discard this workout",
            "It's still in progress. Try again."
        ]
        for (text, wanted) in zip(texts, expected) {
            #expect(text == wanted)
        }
        #expect(texts.count == expected.count)
    }

    @Test("The catalog holds the 27 texts and no other")
    func catalog_holdsExactlyTheSlicesTexts() throws {
        let catalog = try StringCatalog(module: "FeatureWorkout")
        let expected: Set = [
            "Minimize", "Finish", "Exercise %lld of %lld", "You have a workout in progress", "Resume it",
            "Discard and start new", "Cancel", "End workout?", "Discard", "Keep lifting",
            "Elapsed time", "Workout progress", "OK", "Close", "Try again.", "Couldn't start this workout",
            "This day has no exercises yet.", "This day is no longer in your program.",
            "Your program's block has ended.", "Nothing was changed. Try again.", "Couldn't start the new workout",
            "Your workout in progress was kept.", "Your workout in progress was discarded.",
            "Couldn't open this workout", "Close this screen and try again.", "Couldn't discard this workout",
            "It's still in progress. Try again.",
            // F10 S5 (sanctioned edit): the keys of the exercise card, the remaining exercises and a change
            // that was not saved.
            "TARGET", "%lld × %lld @ %@ lb · RPE %@", "%lld × %lld @ %@ kg · RPE %@", "Last", "No history yet",
            "Repeat", "#", "reps", "lb", "kg", "D", "%@ LB", "%@ KG", "1 REP", "+ Add set", "REMAINING",
            "%lld × %lld", "Set %lld", "Drop set", "%@ pounds", "%@ kilograms", "%lld reps", "Log set %lld",
            "Undo set %lld", "Log drop set", "Undo drop set", "Couldn't save that change"
        ]
        #expect(catalog.keys.subtracting(expected).sorted() == [])
        #expect(expected.subtracting(catalog.keys).sorted() == [])
        #expect(catalog.problems == [])
    }

    @Test("Every alert the launcher can show has a title, a line that says what is left, and one button", arguments: [
        (WorkoutLaunchFailure.notStarted(.emptyDay), "Couldn't start this workout / This day has no exercises yet."),
        (.notStarted(.dayNotInProgram), "Couldn't start this workout / This day is no longer in your program."),
        (.notStarted(.blockEnded), "Couldn't start this workout / Your program's block has ended."),
        (.notStarted(.other), "Couldn't start this workout / Nothing was changed. Try again."),
        (.notReplaced(.liveKept), "Couldn't start the new workout / Your workout in progress was kept."),
        (.notReplaced(.nothingLive), "Couldn't start the new workout / Your workout in progress was discarded."),
        (.notReplaced(.unknown), "Couldn't start the new workout / Try again."),
        (.notOpened, "Couldn't open this workout / Try again.")
    ])
    func launcherAlerts_sayWhatIsLeft(failure: WorkoutLaunchFailure, wanted: String) {
        let alert = WorkoutPresentation.alert(for: failure)
        #expect(wanted == "\(alert.title) / \(alert.message)")
        #expect(alert.dismiss == "OK")
    }

    @Test("The two dialogs' models")
    func dialogs_areTheBriefs() {
        let conflict = WorkoutPresentation.conflictDialog
        #expect([conflict.title, conflict.resume, conflict.replace, conflict.cancel]
            == ["You have a workout in progress", "Resume it", "Discard and start new", "Cancel"])
        let finish = WorkoutPresentation.finishDialog
        #expect([finish.title, finish.discard, finish.keepLifting] == ["End workout?", "Discard", "Keep lifting"])
    }

    @Test("No copy outside the copy file (the module's audit)")
    func sources_holdNoCopyOutsideTheCopyFile() throws {
        let audit = try CopyAudit(
            module: "FeatureWorkout",
            exempting: CopyAudit.Exemptions(debugOnly: ["WorkoutLauncher+Sample.swift"])
        )
        #expect(audit.findings == [])
    }

    /// Ambient time, place and language, and work that outlives a view. `Text(timerInterval:)` is the one
    /// reader of the wall clock the specification asks for, and it is not in this list.
    nonisolated static let forbidden = [
        "Date()", "Date.now", "Date(timeIntervalSinceNow", ".now)", ": .now", "= .now", "Calendar.current",
        "Calendar.autoupdatingCurrent", "Calendar(identifier", "Locale.current", "Locale.autoupdatingCurrent",
        "Locale(identifier", "TimeZone.current", "TimeZone.autoupdatingCurrent", "TimeZone(", "Timer", "DispatchQueue",
        "Task {", "Task(", "Task.detached", "Task.sleep", "ContinuousClock()", "SuspendingClock()", "UUID()",
        "TimelineView", ".formatted()", ".formatted(.", "DateFormatter", "String(localized", "NSLocalizedString",
        "LocalizedStringKey"
    ]

    @Test("No source file reads an ambient clock, calendar, locale or zone, or starts a task")
    func sources_readNothingAmbient() throws {
        let sources = try CopyAudit.sources(ofModule: "FeatureWorkout")
        #expect(sources.count >= 15, "the module's sources were not found")
        var hits: [String] = []
        for (file, text) in sources.sorted(by: { $0.key < $1.key }) {
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // `date.now` is the injected date (`@Dependency(\\.date)`), not the ambient one.
                let code = (line.components(separatedBy: "//").first ?? "").replacingOccurrences(
                    of: "date.now",
                    with: "injected"
                )
                for token in Self.forbidden where code.contains(token) {
                    if CopyAudit.isCopyFile(file), token == "String(localized" {
                        continue
                    }
                    hits.append("\(file):\(number + 1): \(token)")
                }
            }
        }
        #expect(hits == [])
    }
}
