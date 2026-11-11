@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import Testing

/// F14 S2, N12: the plates sheet's model. The bar is stepped by 2.5 lb within 0–100 lb, or by 1.25 kg within 0–45 kg;
/// the plates are the unit's fixed list, with any other stored size among them; no plate says so.
@Suite("Plates presentation", .tags(.feature))
struct PlatesPresentationTests {
    static func sheet(_ units: Units, bar: Weight, plates: [Weight]) -> PlatesModel {
        PlatesPresentation.sheet(
            PlatesDraft(units: units, inventory: PlateInventory(bar: bar, plates: plates)),
            locale: Fixtures.locale
        )
    }

    @Test("The bar steps within its range, and each end switches its step off")
    func bar_stepsWithinItsRange() {
        let pounds = Self.sheet(.lb, bar: .pounds(45), plates: []).bar
        #expect(pounds.decrement == .setBar(.pounds(42.5)) && pounds.increment == .setBar(.pounds(47.5)))
        #expect(pounds.value == "45 lb" && pounds.spokenValue == "45 pounds")
        #expect(Self.sheet(.lb, bar: .zero, plates: []).bar.decrement == nil)
        #expect(Self.sheet(.lb, bar: .pounds(100), plates: []).bar.increment == nil)
        let kilograms = Self.sheet(.kg, bar: .kilograms(20), plates: []).bar
        #expect(kilograms.increment == .setBar(.kilograms(21.25)))
        #expect(Self.sheet(.kg, bar: .kilograms(45), plates: []).bar.increment == nil)
        // A bar off the grid (20.41 kg, another version's) steps to the multiples beside it.
        let offGrid = Self.sheet(.kg, bar: .pounds(45), plates: []).bar
        #expect(offGrid.decrement == .setBar(.kilograms(20)) && offGrid.increment == .setBar(.kilograms(21.25)))
    }

    @Test("The plates are the unit's list, heaviest first, each on or off, its action the other state")
    func plates_areTheUnitsList() {
        let pounds = Self.sheet(.lb, bar: .pounds(45), plates: PlateInventory.standard(.lb).plates)
        let poundsListed = pounds.plates.map(\.title) == [
            "55 lb",
            "45 lb",
            "35 lb",
            "25 lb",
            "15 lb",
            "10 lb",
            "5 lb",
            "2.5 lb",
            "1.25 lb"
        ]
        #expect(poundsListed)
        let poundsOn = pounds.plates.map(\.isOn) == [false, true, false, true, false, true, true, true, false]
        #expect(poundsOn)
        #expect(pounds.plates[0].action == .setPlate(.pounds(55), isOn: true))
        #expect(pounds.plates[1].action == .setPlate(.pounds(45), isOn: false))
        #expect(pounds.plates[7].spokenLabel == "2.5 pounds")
        let kilograms = Self.sheet(.kg, bar: .kilograms(20), plates: [])
        let kilogramsListed = kilograms.plates.map(\.title) == [
            "25 kg",
            "20 kg",
            "15 kg",
            "10 kg",
            "5 kg",
            "2.5 kg",
            "1.25 kg",
            "0.5 kg"
        ]
        #expect(kilogramsListed)
        #expect(pounds.empty == nil && kilograms.empty == "No plates: no plate line will show")
    }

    @Test("A stored size off the list is shown, on, in its place")
    func offListSize_isKept() {
        let sheet = Self.sheet(.kg, bar: .kilograms(20), plates: [.kilograms(0.25), .kilograms(20)])
        #expect(sheet.plates.last?.title == "0.25 kg" && sheet.plates.last?.isOn == true)
        #expect(sheet.plates.count == 9)
    }

    @Test("The row reads the bar, or why it is off; the sheet's words")
    func row_andWords() {
        var settings = Fixtures.settingsLb
        settings.units = .kg
        #expect(PlatesPresentation.row(settings, locale: Fixtures.locale).detail == "20 kg bar")
        settings.plateInventory[.kg] = nil
        #expect(PlatesPresentation.row(settings, locale: Fixtures.locale).action == .editPlates)
        let sheet = Self.sheet(.lb, bar: .pounds(45), plates: [])
        #expect(sheet.title == "Bar and plates" && sheet.cancel == "Cancel" && sheet.platesTitle == "Plates you own")
        #expect(sheet.reset == SettingsModel.Link(title: "Reset to standard", action: .resetPlates))
        #expect(sheet.done == SettingsModel.Link(title: "Done", action: .savePlates))
    }
}
