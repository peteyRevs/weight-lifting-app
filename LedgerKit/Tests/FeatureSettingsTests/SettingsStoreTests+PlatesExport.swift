@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S2, the store: "Bar and plates" (criterion 3, N12) and the export's file (criterion 5, N15, N16).
@MainActor
@Suite("SettingsStore · plates and export", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct SettingsPlatesExportStoreTests {
    // MARK: Bar and plates

    @Test("Criterion 3. The sheet opens on the stored inventory; bar, plates and Done save that unit's alone")
    func plates_editedAndSaved_otherUnitUntouched() async throws {
        let scene = SettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        #expect(try scene.model.plates.detail == "45 lb bar" && scene.model.platesSheet == nil)
        scene.store.send(.editPlates)
        let opened = try #require(try scene.model.platesSheet)
        #expect(opened.bar.value == "45 lb" && opened.plates.filter(\.isOn).count == 5)
        try scene.store.send(#require(opened.bar.increment))
        scene.store.send(.setPlate(.pounds(55), isOn: true))
        scene.store.send(.setPlate(.pounds(2.5), isOn: false))
        let edited = try #require(try scene.model.platesSheet)
        #expect(edited.bar.value == "47.5 lb")
        #expect(scene.watched.saves.isEmpty, "nothing is saved before Done")
        scene.store.send(edited.done.action)
        #expect(try scene.model.platesSheet == nil)
        await eventually { scene.store.pending == nil }
        let stored = try await scene.stored()
        let pounds = PlateInventory(bar: .pounds(47.5), plates: [55, 45, 25, 10, 5].map(Weight.pounds))
        #expect(stored.plateInventory[.lb] == pounds)
        #expect(stored.plateInventory[.kg] == .standard(.kg), "the other unit's inventory is left alone")
        #expect(try scene.model.plates.detail == "47.5 lb bar")
    }

    @Test("Cancel closes the sheet and saves nothing; Reset to standard puts back the unit's standard")
    func plates_cancelAndReset() async throws {
        var settings = Fixtures.settingsLb
        settings.units = .kg
        settings.plateInventory[.kg] = PlateInventory(bar: .kilograms(15), plates: [.kilograms(25)])
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.editPlates)
        scene.store.send(.setBar(.kilograms(10)))
        scene.store.send(.cancelPlates)
        #expect(try scene.model.platesSheet == nil)
        scene.store.send(.editPlates)
        #expect(try scene.model.platesSheet?.bar.value == "15 kg", "the cancelled bar was dropped")
        scene.store.send(.resetPlates)
        scene.store.send(.savePlates)
        await eventually { scene.store.pending == nil }
        #expect(try await scene.stored().plateInventory[.kg] == .standard(.kg))
        #expect(scene.watched.saves.count == 1)
    }

    @Test("With Plate math off the row does nothing and says why")
    func plates_offWhilePlateMathIsOff() async throws {
        var settings = Fixtures.settingsLb
        settings.plateMathEnabled = false
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        let row = try scene.model.plates
        #expect(row.action == nil && row.detail == "Turn on Plate math to edit")
        scene.store.send(.editPlates)
        #expect(try scene.model.platesSheet == nil)
        scene.store.send(.setPlateMath(true))
        #expect(try scene.model.plates.action == .editPlates)
    }

    // MARK: Export

    @Test("Criterion 5, N15. The file is every workout, oldest first, as BOM plus render, named for today")
    func export_bytesAreTheRender() async throws {
        let history = try Fixtures.history(weeks: 2)
        let seed = try InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), workouts: history)
        let scene = SettingsScene(seed: seed)
        let task = await scene.running()
        defer { task.cancel() }
        let export = try scene.model.export.file
        #expect(export.fileName == "workouts-2026-09-16.csv")
        // Something of an earlier export is cleared first (N16).
        try FileManager.default.createDirectory(at: scene.exportDirectory, withIntermediateDirectories: true)
        let stale = scene.exportDirectory.appending(path: "stale.csv")
        try Data("old".utf8).write(to: stale)
        let file = try await export.write()
        #expect(file.lastPathComponent == "workouts-2026-09-16.csv")
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        let oldestFirst = history.sorted { $0.startedAt < $1.startedAt }
        let expected = Data(CSVExport.byteOrderMark.utf8)
            + Data(CSVExport.render(workouts: oldestFirst, units: .lb, calendar: Fixtures.calendar).utf8)
        let written = try Data(contentsOf: file)
        let isTheRender = written == expected
        #expect(isTheRender, "\(written.count) bytes against \(expected.count)")
        #expect(oldestFirst.count == history.count && !history.isEmpty)
    }

    @Test("N16. When Settings goes away its export directory is emptied")
    func export_clearedWhenSettingsGoesAway() async throws {
        let scene = SettingsScene()
        let task = await scene.running()
        _ = try await scene.model.export.file.write()
        #expect(FileManager.default.fileExists(atPath: scene.exportDirectory.path))
        task.cancel()
        await task.value
        #expect(!FileManager.default.fileExists(atPath: scene.exportDirectory.path))
    }

    @Test("Kilograms on screen: the file is in kilograms")
    func export_followsTheUnits() async throws {
        var settings = Fixtures.settingsLb
        settings.units = .kg
        let scene = SettingsScene(settings: settings)
        let task = await scene.running()
        defer { task.cancel() }
        let file = try await scene.model.export.file.write()
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("weight_kg"))
        try ExportFile.clear(scene.exportDirectory)
    }
}
