@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 criterion 3: a row's load and weekly step in the lifter's unit, in exact decimals.
nonisolated extension DayEditorPresentationTests {
    @Test("In kilograms a row shows the load and the weekly step in kilograms, with the kettlebell's 2 kg")
    func rows_kilograms_showLoadsAndStepsInKilograms() throws {
        let kettlebell = try DayEditorFixtures.exercise(named: "Kettlebell Row")
        let slots = try [
            DayEditorFixtures.slot(1, startLoad: .kilograms(80)),
            DayEditorFixtures.slot(2, Fixtures.CatalogID.inclineDBPress, startLoad: .kilograms(22.5)),
            DayEditorFixtures.slot(3, kettlebell.id, startLoad: .kilograms(16)),
            // A load written in pounds is shown converted, to one decimal.
            DayEditorFixtures.slot(4, startLoad: .pounds(180))
        ]
        let rows = try DayEditorPresentation.make(DayEditorFixtures.input(slots: slots, units: .kg)).content().rows
        #expect(rows.map(\.load) == ["80 kg", "22.5 kg", "16 kg", "81.6 kg"])
        #expect(rows.map(\.sub) == [
            "Barbell · +2.5/wk · RPE 8 · 1:30 rest",
            "Dumbbell · +1.25/wk · RPE 8 · 1:30 rest",
            "Kettlebell · +2/wk · RPE 8 · 1:30 rest",
            "Barbell · +2.5/wk · RPE 8 · 1:30 rest"
        ])
        let pounds = try DayEditorPresentation.make(DayEditorFixtures.input(slots: [slots[2]])).content().rows
        #expect(pounds.first?.sub == "Kettlebell · +5/wk · RPE 8 · 1:30 rest")
    }

    @Test("A slot with a step of its own shows that step, and one with no start load shows its exercise's")
    func row_ownStepAndTheExercisesStartLoad() throws {
        var slot = try DayEditorFixtures.slot(1)
        slot.step = .pounds(10)
        let row = try #require(DayEditorPresentation.make(DayEditorFixtures.input(slots: [slot])).content().rows.first)
        let bench = try DayEditorFixtures.exercise(named: "Barbell Bench Press")
        #expect(row.sub == "Barbell · +10/wk · RPE 8 · 1:30 rest")
        #expect(row.load == "\(bench.startLoad(in: .lb).formatted(in: .lb)) lb")
    }
}
