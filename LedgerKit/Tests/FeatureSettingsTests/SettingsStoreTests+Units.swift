@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S2, the store: a switch of units converts the program in the same write (criterion 1, ruling A4).
@MainActor
@Suite("SettingsStore · units", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct SettingsUnitsStoreTests {
    /// The bundled catalog and the spec's seed program, active, every start load in pounds.
    static func programSeed() throws -> InMemoryStores.Seed {
        try InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), programs: [Fixtures.seedProgram()])
    }

    static func benchLoad(_ scene: SettingsScene) async throws -> Weight? {
        let program = try #require(try await scene.memory.programs.active())
        return program.days.first?.slots.first?.startLoad
    }

    // MARK: Units

    @Test("Criterion 1. KG is one switchUnits: the settings and the program's loads, together")
    func kilograms_switchConvertsTheProgram() async throws {
        let scene = try SettingsScene(seed: Self.programSeed())
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await eventually { scene.store.pending == nil }
        #expect(scene.watched.switches.map(\.units) == [.kg])
        #expect(try await scene.stored().units == .kg)
        // 180 lb on a barbell: 82.5 kg.
        #expect(try await Self.benchLoad(scene) == .kilograms(82.5))
    }

    @Test("A change that is not of units is a plain save, and converts nothing")
    func otherChange_isASave() async throws {
        let scene = try SettingsScene(seed: Self.programSeed())
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setAutoRest(false))
        await eventually { scene.store.pending == nil }
        #expect(scene.watched.switches.isEmpty && scene.watched.saves.count == 1)
        #expect(try await Self.benchLoad(scene) == .pounds(180))
    }

    @Test("Ruling A4. A failed switch changes neither, says so, and Try again switches again")
    func failedSwitch_saysSo_andTryAgainSwitches() async throws {
        let scene = try SettingsScene(failures: 1, seed: Self.programSeed())
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await eventually { scene.store.model?.problem != nil }
        let failed = try scene.model
        #expect(failed.problem == "Couldn't change the units. Nothing was changed.")
        #expect(failed.retry?.title == "Try again" && failed.retry?.action == .setUnits(.kg))
        #expect(failed.units.options[0].isSelected, "the control shows pounds again")
        #expect(try await scene.stored().units == .lb)
        #expect(try await Self.benchLoad(scene) == .pounds(180))
        let retry = try #require(failed.retry)
        scene.store.send(retry.action)
        #expect(try scene.model.retry == nil && scene.model.problem == nil)
        await eventually { scene.store.pending == nil }
        #expect(scene.watched.switches.map(\.units) == [.kg, .kg])
        #expect(try await Self.benchLoad(scene) == .kilograms(82.5))
    }

    @Test("A failed save of anything else keeps S1's line, with no Try again")
    func failedSave_hasNoRetry() async throws {
        let scene = SettingsScene(failures: 1)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setWatchBuzz(false))
        await eventually { scene.store.model?.problem != nil }
        #expect(try scene.model.problem == "Couldn't save that change." && scene.model.retry == nil)
    }

    @Test("With no program, a switch saves the settings alone")
    func noProgram_switchSavesTheSettings() async throws {
        let scene = SettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await eventually { scene.store.pending == nil }
        #expect(try await scene.stored().units == .kg)
        #expect(try await scene.memory.programs.active() == nil)
    }
}
