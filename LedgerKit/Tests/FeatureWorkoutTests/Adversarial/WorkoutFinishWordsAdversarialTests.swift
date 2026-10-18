@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7a criteria 2, 4, 5, 24 and 40 (the words): the "End workout?" sheet's model for any workout,
/// word for word and from the numbers alone; the forms a count picks in languages whose rules differ from
/// English; nothing logged; and what the store does with a "Save workout" it should not take.
@MainActor
@Suite("Workout finish words (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutFinishWordsAdversarialTests {
    /// One exercise of `total` sets of 100 lb (or 100 kg) × 5, the first `done` logged.
    nonisolated static func workout(sets total: Int, done: Int, units: Units = .lb) throws -> WorkoutState {
        var workout = try Fixtures.seedSession()
        workout.units = units
        workout.exercises = total == 0 ? [] : [workout.exercises[0]]
        if total > 0 {
            let exercise = workout.exercises[0].id
            workout.exercises[0].sets = (0 ..< total).map { index in
                LoggedSet(
                    id: .derived(from: exercise, index: index),
                    weight: units == .lb ? .pounds(100) : .kilograms(100),
                    reps: Reps(clamping: 5),
                    kind: .working,
                    doneAt: index < done ? workout.startedAt : nil
                )
            }
        }
        return workout
    }

    /// A whole number with "," between its thousands, written here: rule 34's text.
    nonisolated static func grouped(_ number: Int) -> String {
        var digits = String(number)
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        return ([digits] + groups).joined(separator: ",")
    }

    @Test("The whole model, from the numbers alone, for every count of a workout, in pounds and kilograms", arguments: [
        (0, 0), (1, 0), (1, 1), (2, 0), (2, 1), (2, 2), (25, 23), (25, 25), (1250, 1234)
    ], [Units.lb, .kg])
    func model_isTheCriterias(counts: (total: Int, done: Int), units: Units) throws {
        let state = try Self.workout(sets: counts.total, done: counts.done, units: units)
        let sets = counts.total == 1 ? "set" : "sets"
        let logged = "\(Self.grouped(counts.done)) of \(Self.grouped(counts.total)) \(sets) logged"
        let moved = "\(Self.grouped(counts.done * 500)) \(units == .lb ? "lb" : "kg") moved"
        for isSaving in [false, true] {
            let model = WorkoutPresentation.finishSheet(state, isSaving: isSaving, locale: Fixtures.locale)
            #expect(model == WorkoutFinishModel(
                title: "End workout?",
                keepLifting: "Keep lifting",
                summary: "\(logged) · \(moved)",
                spokenSummary: "\(logged), \(moved)",
                save: "Save workout",
                discard: "Discard",
                canSave: counts.done > 0 && !isSaving,
                isEnabled: !isSaving
            ))
        }
    }

    @Test("The count's form is English's whatever the lifter's language: no other rule is applied", arguments: [
        ("ru_RU", 21, "sets"), ("ru_RU", 1, "set"), ("fr_FR", 0, "sets"), ("fr_FR", 1, "set"), ("ja_JP", 1, "set"),
        ("ja_JP", 5, "sets"), ("ar_EG", 2, "sets"), ("ar_EG", 11, "sets"), ("pl_PL", 22, "sets"), ("cy_GB", 3, "sets"),
        ("en_GB", 1, "set"), ("de_DE", 0, "sets")
    ])
    func countedForm_isEnglish(locale: String, total: Int, word: String) throws {
        let state = try Self.workout(sets: total, done: 0)
        let model = WorkoutPresentation.finishSheet(state, isSaving: false, locale: Locale(identifier: locale))
        #expect(model.summary.hasSuffix(" \(word) logged · 0 lb moved"), "\(locale): \(model.summary)")
        #expect(model.spokenSummary.hasSuffix(" \(word) logged, 0 lb moved"), "\(locale): \(model.spokenSummary)")
    }

    /// As built, for the product owner: the two counts are written the lifter's way and the volume the
    /// Domain's (rule 34), so one line can hold two ways of writing a number.
    @Test("The counts are in the lifter's digits and grouping; the volume is the Domain's text (as built)", arguments: [
        ("en_US", "1,234 of 1,250 sets logged · 617,000 lb moved"),
        ("de_DE", "1.234 of 1.250 sets logged · 617,000 lb moved"),
        ("ar_EG", "١٬٢٣٤ of ١٬٢٥٠ sets logged · 617,000 lb moved"),
        ("hi_IN", "1,234 of 1,250 sets logged · 617,000 lb moved")
    ])
    func numbers_inAnotherLocale_asBuilt(locale: String, wanted: String) throws {
        let state = try Self.workout(sets: 1250, done: 1234)
        let model = WorkoutPresentation.finishSheet(state, isSaving: false, locale: Locale(identifier: locale))
        #expect(model.summary == wanted)
    }

    @Test("The eight keys of the slice are in the catalog as the specification writes them, and the lookups answer")
    func texts_areTheSpecifications() throws {
        let catalog = try StringCatalog(module: "FeatureWorkout")
        let added: Set = [
            "Save workout", "%@ of %lld sets logged", "%@ lb moved", "%@ kg moved", "Rest, %@ remaining",
            // Invented, for the product owner: exactly these three.
            "Couldn't save this workout", "It's still on this iPhone. Try again.", "Try again"
        ]
        #expect(added.subtracting(catalog.keys) == [])
        #expect(WorkoutCopy.saveWorkout == "Save workout")
        #expect(WorkoutCopy.couldNotSaveWorkout == "Couldn't save this workout")
        #expect(WorkoutCopy.stillOnThisPhone == "It's still on this iPhone. Try again.")
        #expect(WorkoutCopy.tryAgainButton == "Try again")
        #expect(WorkoutCopy.tryAgain == "Try again.", "S4's sentence keeps its full stop: two keys, not one")
        #expect(WorkoutCopy.close == "Close")
        #expect(WorkoutCopy.setsLogged(done: "23", of: 25, locale: Fixtures.locale) == "23 of 25 sets logged")
        #expect(WorkoutCopy.setsLogged(done: "1", of: 1, locale: Fixtures.locale) == "1 of 1 set logged")
        #expect(WorkoutCopy.moved("24,180", units: .lb, locale: Fixtures.locale) == "24,180 lb moved")
        #expect(WorkoutCopy.moved("10,968", units: .kg, locale: Fixtures.locale) == "10,968 kg moved")
        #expect(WorkoutCopy.restRemaining("1 minute, 30 seconds", locale: Fixtures.locale)
            == "Rest, 1 minute, 30 seconds remaining")
        #expect(WorkoutCopy.restOver == "Rest over")
    }

    @Test("A text that holds a per cent sign or a format in its value is shown as it is")
    func values_areNotFormatsAgain() {
        #expect(WorkoutCopy.setsLogged(done: "%@", of: 2, locale: Fixtures.locale) == "%@ of 2 sets logged")
        #expect(WorkoutCopy.moved("100%", units: .lb, locale: Fixtures.locale) == "100% lb moved")
        #expect(WorkoutCopy.restRemaining("%lld", locale: Fixtures.locale) == "Rest, %lld remaining")
    }
}

// MARK: - Nothing logged, and a Save workout the store should not take

extension WorkoutFinishWordsAdversarialTests {
    @Test("Nothing logged: the sheet opens, Save workout does not answer, the store takes none, Discard is one tap")
    func zeroSets_storeTakesNoSave() async throws {
        let cover = await SaveCover()
        cover.send(.finish)
        let sheet = try #require(cover.store.finishSheet)
        #expect(cover.store.dialog == .finish, "the sheet still opens, so Discard can be reached")
        #expect(sheet.summary == "0 of \(cover.running.totalSets) sets logged · 0 lb moved")
        #expect(!sheet.canSave)
        #expect(sheet.isEnabled)
        cover.send(.save, .retrySave)
        await cover.rest()
        #expect(!cover.store.isSaving)
        #expect(cover.store.saveAttempt == 0)
        #expect(cover.store.dialog == .finish)
        #expect(await cover.session.finishesAsked == [])
        // With the sheet down too: deviation 4 puts the sheet up only for a save it takes.
        cover.send(.keepLifting, .save)
        #expect(cover.store.dialog == nil)
        #expect(!cover.store.isSaving)
        cover.send(.finish, .discard)
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(cover.exits == [.route(.discarded)])
        #expect(await cover.session.discardsAsked == 1)
        #expect(await cover.session.finishesAsked == [])
        await cover.close()
    }

    @Test("A set logged and then un-logged is nothing logged again; a set whose weight is zero still counts")
    func zeroSets_afterAnUndo_andAZeroVolume() async {
        let cover = await SaveCover { $0.exercises[0].sets[0].weight = .zero }
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the set to be shown as logged") { cover.store.shown?.doneSets == 1 }
        cover.send(.finish)
        #expect(cover.store.finishSheet?.summary.hasPrefix("1 of ") == true)
        #expect(cover.store.finishSheet?.summary.hasSuffix(" · 0 lb moved") == true)
        #expect(cover.store.finishSheet?.canSave == true, "what can be saved is a logged set, not a volume")
        cover.send(.keepLifting)
        cover.clock.withValue { $0 += 30 }
        cover.tap(.unlog(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the set to be shown as not logged") { cover.store.shown?.doneSets == 0 }
        cover.send(.finish, .save)
        #expect(!cover.store.isSaving)
        #expect(cover.store.finishSheet?.canSave == false)
        #expect(await cover.session.finishesAsked == [])
        await cover.close()
    }

    @Test("Save workout is taken from the sheet or from no dialog: never from behind an alert or a failed screen")
    func save_isTakenOnlyWhereItCanBeTapped() async {
        let cover = await Self.loggedOne()
        // Deviation 4: with no dialog up, the save is taken and the sheet goes up to show it running.
        await cover.session.holdEveryEnd()
        cover.send(.save)
        #expect(cover.store.isSaving)
        #expect(cover.store.dialog == .finish)
        await cover.close()

        for dialog in [WorkoutDialog.discardFailed, .editFailed, .saveFailed] {
            let other = await Self.loggedOne()
            other.store.dialog = dialog
            other.send(.save)
            #expect(!other.store.isSaving, "\(dialog)")
            #expect(other.store.dialog == dialog)
            #expect(await other.session.finishesAsked == [])
            await other.close()
        }

        let lost = await Self.loggedOne()
        await lost.session.endStreams()
        await lost.until("the failed screen") { lost.store.shown == nil }
        lost.send(.finish, .save)
        #expect(lost.store.dialog == nil)
        #expect(!lost.store.isSaving)
        #expect(lost.store.finishSheet == nil)
        await lost.close()
    }

    static func loggedOne() async -> SaveCover {
        let cover = await SaveCover()
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the set to be shown as logged") { cover.store.shown?.doneSets == 1 }
        return cover
    }
}
