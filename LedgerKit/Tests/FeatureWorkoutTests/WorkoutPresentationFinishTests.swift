@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, criteria 2, 4, 5, 15 and 21: the "End workout?" sheet, the failed save's alert and the rest's
/// announcement as the presentation makes them, word for word, in pounds and in kilograms.
@Suite("WorkoutPresentation finish", .tags(.feature))
struct WorkoutPresentationFinishTests {
    /// A workout of one exercise whose sets are `weights`, each of five reps, the first `done` logged.
    static func workout(_ weights: [Weight], done: Int, units: Units = .lb) throws -> WorkoutState {
        var workout = try Fixtures.seedSession()
        workout.units = units
        workout.exercises = [workout.exercises[0]]
        workout.exercises[0].sets = weights.enumerated().map { index, weight in
            LoggedSet(
                id: .derived(from: workout.exercises[0].id, index: index),
                weight: weight,
                reps: Reps(clamping: 5),
                kind: .working,
                doneAt: index < done ? workout.startedAt : nil
            )
        }
        return workout
    }

    static func sheet(_ workout: WorkoutState, isSaving: Bool = false) -> WorkoutFinishModel {
        WorkoutPresentation.finishSheet(workout, isSaving: isSaving, locale: Fixtures.locale)
    }

    @Test("The sheet reads as the brief writes it: 23 of 25 sets logged · 24,180 lb moved")
    func sheet_isTheBriefs() throws {
        // 22 sets of 210 lb and one of 216 lb, five reps each: 24,180 lb.
        let weights = Array(repeating: Weight.pounds(210), count: 22) + Array(repeating: .pounds(216), count: 3)
        let model = try Self.sheet(Self.workout(weights, done: 23))
        #expect(model == WorkoutFinishModel(
            title: "End workout?",
            keepLifting: "Keep lifting",
            summary: "23 of 25 sets logged · 24,180 lb moved",
            spokenSummary: "23 of 25 sets logged, 24,180 lb moved",
            save: "Save workout",
            discard: "Discard",
            canSave: true,
            isEnabled: true
        ))
    }

    @Test("In a kilogram workout the volume is in kilograms, with its unit")
    func sheet_inKilograms() throws {
        let model = try Self.sheet(Self.workout([.kilograms(100), .kilograms(102.5)], done: 2, units: .kg))
        #expect(model.summary == "2 of 2 sets logged · 1,013 kg moved")
        #expect(model.spokenSummary == "2 of 2 sets logged, 1,013 kg moved")
    }

    @Test("The total picks the form; the done count does not")
    func sheet_countsByTheTotal() throws {
        #expect(try Self.sheet(Self.workout([.pounds(100)], done: 1)).summary == "1 of 1 set logged · 500 lb moved")
        #expect(try Self.sheet(Self.workout([.pounds(100), .pounds(100)], done: 1)).summary
            == "1 of 2 sets logged · 500 lb moved")
    }

    @Test("The plural form is the catalog's language's; the digits are the lifter's")
    func sheet_inAnotherLocale() throws {
        let workout = try Self.workout([.pounds(100)], done: 1)
        let arabic = WorkoutPresentation.finishSheet(workout, isSaving: false, locale: Locale(identifier: "ar_EG"))
        #expect(arabic.summary.hasSuffix("set logged · 500 lb moved"), "\(arabic.summary)")
        #expect(arabic.summary.hasPrefix("١ of ١"), "\(arabic.summary)")
    }

    @Test("With no set logged Save workout does not answer; Discard and Keep lifting do")
    func sheet_zeroSets_cannotSave() throws {
        let model = try Self.sheet(Self.workout([.pounds(100), .pounds(100)], done: 0))
        #expect(model.summary == "0 of 2 sets logged · 0 lb moved")
        #expect(!model.canSave)
        #expect(model.isEnabled)
    }

    @Test("While it saves nothing on the sheet answers")
    func sheet_saving_isDisabled() throws {
        let model = try Self.sheet(Self.workout([.pounds(100)], done: 1), isSaving: true)
        #expect(!model.canSave)
        #expect(!model.isEnabled)
        #expect(model.summary == "1 of 1 set logged · 500 lb moved")
    }

    @Test("A workout with no exercise gives a sheet and does not trap")
    func sheet_noExercise_isTotal() throws {
        var workout = try Fixtures.seedSession()
        workout.exercises = []
        let model = Self.sheet(workout)
        #expect(model.summary == "0 of 0 sets logged · 0 lb moved")
        #expect(!model.canSave)
    }

    @Test("A volume in the millions keeps its separators")
    func sheet_largeVolume() throws {
        let model = try Self.sheet(Self.workout(Array(repeating: .pounds(1234.567), count: 200), done: 200))
        #expect(model.summary == "200 of 200 sets logged · 1,234,567 lb moved")
    }

    @Test("The failed save's alert: what failed, that nothing is lost, Try again and Close, and no Discard")
    func saveFailedAlert_isTheSpecifications() {
        #expect(WorkoutPresentation.saveFailedAlert == WorkoutSaveFailedModel(
            title: "Couldn't save this workout",
            message: "It's still on this iPhone. Try again.",
            retry: "Try again",
            close: "Close"
        ))
    }

    @Test("A rest is announced with its time in words, rounded up to the second; one with no time left is not")
    func restAnnouncement_saysTheTimeInWords() {
        let rest = RestTimer(endsAt: Fixtures.now.addingTimeInterval(90), total: .seconds(90))
        func said(after seconds: TimeInterval) -> String? {
            WorkoutPresentation.restAnnouncement(
                rest, at: Fixtures.now.addingTimeInterval(seconds), locale: Fixtures.locale
            )
        }
        #expect(said(after: 0) == "Rest, 1 minute, 30 seconds remaining")
        #expect(said(after: 44.3) == "Rest, 46 seconds remaining")
        #expect(said(after: 89) == "Rest, 1 second remaining")
        #expect(said(after: 30) == "Rest, 1 minute remaining")
        #expect(said(after: 90) == nil)
        #expect(said(after: 400) == nil)
        #expect(said(after: 0)?.contains(":") == false)
        // The panel's spoken time is the same formatter's.
        #expect(WorkoutPresentation.spokenRestTime(.seconds(90), locale: Fixtures.locale) == "1 minute, 30 seconds")
    }
}
