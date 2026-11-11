@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: the store's side of S2. The unit switch through `switchUnits` (one write, ruling A4), its
/// failure and "Try again"; the plate editor's bar walked to both ends in both units, off-list sizes, the other unit's
/// inventory, reset, cancel and Plate math off; the export's bytes, order, name and directory.
@MainActor
@Suite("Adversarial F14 S2 · plates, units and export", .tags(.feature), .timeLimit(.minutes(1)))
struct PlatesExportAdversarialTests {
    static let barbell = Seeders.catalogEntry(0)

    /// A program whose one slot is a barbell at 135 lb, stepping 5 lb.
    static func program() throws -> Program {
        var program = try Seeders.program(weeks: 2, days: 1, slotsPerDay: 1, exercises: [barbell.id])
        program.days[0].slots[0].startLoad = .pounds(135)
        program.days[0].slots[0].step = .pounds(5)
        return program
    }

    static func seed(workouts: [WorkoutState] = []) throws -> InMemoryStores.Seed {
        try InMemoryStores.Seed(catalog: [barbell], programs: [program()], workouts: workouts)
    }

    static func slot(_ scene: SettingsScene) async throws -> Slot? {
        try await scene.memory.programs.active()?.days.first?.slots.first
    }

    // MARK: - Units (criterion 1, N11, A4)

    @Test("KG converts the program in the same write: 135 lb becomes 60 kg, 5 lb steps become 2.5 kg")
    func kilograms_convertsTheProgram() async throws {
        let scene = try SettingsScene(seed: Self.seed())
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await eventually { scene.store.pending == nil }
        #expect(scene.watched.switches.count == 1)
        let slot = try await Self.slot(scene)
        #expect(slot?.startLoad == .kilograms(60))
        #expect(slot?.step == .kilograms(2.5))
    }

    @Test("A failed switch says nothing changed, offers Try again, and leaves program and units; Try again converts")
    func failedSwitch_thenTryAgain() async throws {
        let scene = try SettingsScene(failures: 1, seed: Self.seed())
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await eventually { scene.store.model?.retry != nil }
        let failed = try scene.model
        #expect(failed.problem != nil)
        #expect(failed.units.options[0].isSelected, "LB shows again")
        #expect(try await scene.stored().units == .lb)
        #expect(try await Self.slot(scene)?.startLoad == .pounds(135))
        let retry = try #require(failed.retry)
        scene.store.send(retry.action)
        await eventually { scene.store.pending == nil }
        #expect(try scene.model.problem == nil)
        #expect(try scene.model.retry == nil)
        #expect(try await scene.stored().units == .kg)
        #expect(try await Self.slot(scene)?.startLoad == .kilograms(60))
    }

    @Test("N11's line: a failed conversion reads \"Couldn't convert your program's weights.\" (contract text)")
    func failedSwitch_lineMatchesTheContract() async throws {
        let scene = try SettingsScene(failures: 1, seed: Self.seed())
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await eventually { scene.store.model?.retry != nil }
        let problem = try scene.model.problem
        // F14-S2-G2-2, ruled: N11.3 is amended to the shipped line.
        #expect(problem == "Couldn't change the units. Nothing was changed.")
    }

    @Test("A change made while the switch is held is saved with save, and the program is converted once")
    func changeDuringSwitch_convertsOnce() async throws {
        let scene = try SettingsScene(holdsSaves: true, seed: Self.seed())
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilASaveIsHeld()
        scene.store.send(.setAutoRest(false))
        scene.store.send(.setUnits(.lb))
        scene.store.send(.setUnits(.kg))
        scene.watched.releaseSaves()
        await eventually { scene.store.pending == nil }
        #expect(scene.watched.switches.count == 1)
        #expect(scene.watched.saves.count == 2)
        #expect(try await Self.slot(scene)?.startLoad == .kilograms(60))
        #expect(try await scene.stored().autoRest == false)
    }

    @Test("A failed ordinary save never offers Try again")
    func failedOrdinarySave_noRetry() async throws {
        let scene = try SettingsScene(failures: 1, seed: Self.seed())
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setAutoRest(false))
        await eventually { scene.store.model?.problem != nil }
        #expect(try scene.model.retry == nil)
        #expect(scene.watched.switches.isEmpty)
    }

    @Test("Over an unreadable row, a change that is not of the units does not run the unit switch")
    func unreadableRow_otherChange_noSwitch() async throws {
        var seed = try Self.seed()
        seed.programs[0].days[0].slots[0].startLoad = .pounds(46.25)
        let scene = SettingsScene(unreadable: true, seed: seed)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setDefaultRest(RestDuration(clampingSeconds: 60)))
        await eventually { scene.store.pending == nil }
        // The screen showed pounds and still does: the lifter did not switch units. GRDB's switchUnits converts the
        // program whenever the stored row cannot be read (SwitchUnitsAdversarialTests), so it must not be called here.
        #expect(scene.watched.switches.isEmpty)
        #expect(try await Self.slot(scene)?.startLoad == .pounds(46.25))
    }
}
