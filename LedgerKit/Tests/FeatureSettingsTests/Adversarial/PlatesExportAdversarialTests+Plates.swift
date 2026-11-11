@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: the plate editor through the store (criterion 3, N12).
extension PlatesExportAdversarialTests {
    // MARK: - Plates (criterion 3, N12)

    static func sheet(_ scene: SettingsScene) throws -> PlatesModel {
        try #require(scene.store.model?.platesSheet)
    }

    @Test("The bar walks down to 0 and up to the top in exact steps, in each unit", arguments: [
        (Units.lb, Weight.pounds(45), Weight.pounds(2.5), Weight.pounds(100)),
        (.kg, .kilograms(20), .kilograms(1.25), .kilograms(45))
    ])
    func bar_walksToBothEnds(units: Units, start: Weight, step: Weight, top: Weight) async throws {
        var settings = Fixtures.settingsLb
        settings.units = units
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        var downs = 0
        while let action = try Self.sheet(scene).bar.decrement, downs < 100 {
            scene.store.send(action)
            downs += 1
        }
        #expect(scene.store.plates?.inventory.bar == .zero)
        #expect(Decimal(downs) == start.grams / step.grams)
        var ups = 0
        while let action = try Self.sheet(scene).bar.increment, ups < 100 {
            scene.store.send(action)
            ups += 1
        }
        #expect(scene.store.plates?.inventory.bar == top)
        #expect(Decimal(ups) == top.grams / step.grams)
    }

    @Test("A bar stored off the grid or above the top (a later version's) steps back onto the grid and never higher")
    func bar_offGridAndAboveTop() {
        let offGrid = PlatesPresentation.bar(.pounds(44), .lb, locale: Fixtures.locale)
        #expect(offGrid.decrement == .setBar(.pounds(42.5)))
        #expect(offGrid.increment == .setBar(.pounds(45)))
        let above = PlatesPresentation.bar(.pounds(110), .lb, locale: Fixtures.locale)
        #expect(above.increment == nil)
        #expect(above.decrement == .setBar(.pounds(107.5)))
        let negative = PlatesPresentation.bar(.kilograms(-1), .kg, locale: Fixtures.locale)
        #expect(negative.decrement == nil)
    }

    @Test("The sheet lists N12's sizes per unit, heaviest first", arguments: Units.allCases)
    func sheet_listsTheFixedSizes(units: Units) {
        let draft = PlatesDraft(units: units, inventory: .standard(units))
        let titles = PlatesPresentation.sheet(draft, locale: Fixtures.locale).plates.map(\.title)
        let expected = units == .lb
            ? ["55 lb", "45 lb", "35 lb", "25 lb", "15 lb", "10 lb", "5 lb", "2.5 lb", "1.25 lb"]
            : ["25 kg", "20 kg", "15 kg", "10 kg", "5 kg", "2.5 kg", "1.25 kg", "0.5 kg"]
        #expect(titles == expected)
    }

    @Test("Done saves the edited unit's inventory and leaves the other unit's stored inventory exactly as it was")
    func done_leavesTheOtherUnit() async throws {
        var settings = Fixtures.settingsLb
        let kgInventory = PlateInventory(bar: .kilograms(15), plates: [.kilograms(25), .kilograms(0.5)])
        settings.plateInventory = [.kg: kgInventory]
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        scene.store.send(.setPlate(.pounds(55), isOn: true))
        scene.store.send(.setPlate(.pounds(2.5), isOn: false))
        scene.store.send(.setBar(.pounds(35)))
        scene.store.send(.savePlates)
        await eventually { scene.store.pending == nil }
        let stored = try await scene.stored()
        #expect(stored.plateInventory[.kg] == kgInventory)
        #expect(stored.plateInventory[.lb] == PlateInventory(
            bar: .pounds(35),
            plates: [55, 45, 25, 10, 5].map(Weight.pounds)
        ))
        #expect(stored.units == .lb)
        #expect(scene.store.model?.platesSheet == nil)
    }

    @Test("With no kg inventory stored, editing lb stores none for kg")
    func done_storesNothingForTheOtherUnit() async throws {
        var settings = Fixtures.settingsLb
        settings.plateInventory = [:]
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        scene.store.send(.setPlate(.pounds(45), isOn: false))
        scene.store.send(.savePlates)
        await eventually { scene.store.pending == nil }
        #expect(try await scene.stored().plateInventory[.kg] == nil)
    }

    @Test("A stored size off the list is shown, and kept by Done when untouched")
    func offListSize_shownAndKept() async throws {
        var settings = Fixtures.settingsLb
        settings.plateInventory = [.lb: PlateInventory(bar: .pounds(45), plates: [45, 7.5, 2.5].map(Weight.pounds))]
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        let plate = try #require(try Self.sheet(scene).plates.first { $0.title == "7.5 lb" })
        #expect(plate.isOn)
        scene.store.send(.setBar(.pounds(47.5)))
        scene.store.send(.savePlates)
        await eventually { scene.store.pending == nil }
        #expect(try await scene.stored().plateInventory[.lb]?.plates.contains(.pounds(7.5)) == true)
    }

    @Test("An off-list size switched off stays in the sheet, switched off, so the lifter can switch it back on")
    func offListSize_switchedOff_staysListed() async throws {
        var settings = Fixtures.settingsLb
        settings.plateInventory = [.lb: PlateInventory(bar: .pounds(45), plates: [45, 7.5].map(Weight.pounds))]
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        scene.store.send(.setPlate(.pounds(7.5), isOn: false))
        let listed = try Self.sheet(scene).plates.map(\.title)
        #expect(listed.contains("7.5 lb"))
    }

    @Test("Every plate off shows the empty line; Reset to standard restores the unit's standard; Cancel saves nothing")
    func emptyResetCancel() async throws {
        let scene = SettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        for size in PlatesPresentation.sizes(.lb) {
            scene.store.send(.setPlate(size, isOn: false))
        }
        #expect(try Self.sheet(scene).empty == "No plates: no plate line will show")
        scene.store.send(.resetPlates)
        #expect(scene.store.plates?.inventory == .standard(.lb))
        #expect(try Self.sheet(scene).empty == nil)
        scene.store.send(.setBar(.pounds(0)))
        scene.store.send(.cancelPlates)
        #expect(scene.store.model?.platesSheet == nil)
        #expect(scene.watched.saves.isEmpty)
    }

    @Test("With Plate math off the row is disabled and says why, and .editPlates opens nothing")
    func plateMathOff_rowDisabled() async throws {
        var settings = Fixtures.settingsLb
        settings.plateMathEnabled = false
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        let row = try scene.model.plates
        #expect(row.action == nil)
        #expect(row.detail == "Turn on Plate math to edit")
        scene.store.send(.editPlates)
        #expect(scene.store.model?.platesSheet == nil)
    }

    @Test("In kilograms the sheet edits the kg inventory, and the lb one is untouched")
    func kilograms_editsTheKgInventory() async throws {
        let lbInventory = PlateInventory(bar: .pounds(35), plates: [.pounds(45)])
        var settings = Fixtures.settingsKg
        settings.plateInventory[.lb] = lbInventory
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        #expect(scene.store.plates?.units == .kg)
        scene.store.send(.setPlate(.kilograms(0.5), isOn: true))
        scene.store.send(.savePlates)
        await eventually { scene.store.pending == nil }
        let stored = try await scene.stored()
        #expect(stored.plateInventory[.lb] == lbInventory)
        #expect(stored.plateInventory[.kg]?.plates.contains(.kilograms(0.5)) == true)
    }
}
