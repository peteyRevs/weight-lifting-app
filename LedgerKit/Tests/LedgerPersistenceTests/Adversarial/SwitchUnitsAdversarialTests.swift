import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: `SettingsRepository.switchUnits` (ruling A4, N11): the settings and the active program's
/// converted weights in one transaction. Attacked with a trigger that refuses the program's write (and one that
/// refuses the settings'), then the retry; the same units (no conversion, even off the grid); inactive programs; no
/// program; the equipment read from the exercise rows; and a differential against the in-memory stores.
@Suite("Adversarial F14 S2 · switchUnits", .tags(.persistence), .timeLimit(.minutes(1)))
struct SwitchUnitsAdversarialTests {
    static func settings(_ units: Units) -> Settings {
        var settings = Settings.default
        settings.units = units
        return settings
    }

    /// The settings row as text: payload, version and stamp.
    static func settingsRow(_ queue: DatabaseQueue) async throws -> [String] {
        try await queue.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM settings ORDER BY id").map(\.description)
        }
    }

    struct Bench {
        let stack: S2Kit.Stack
        let settings: GRDBSettingsRepository
    }

    /// A database holding `S2Kit.slotExercises` (barbells), the settings in `units`, and `programs` saved in order.
    static func bench(units: Units = .lb, programs: [Program]) async throws -> Bench {
        let stack = try await S2Kit.stack()
        let settings = GRDBSettingsRepository(stack.queue, now: { stack.clock.now })
        try await settings.save(Self.settings(units))
        for program in programs {
            try await stack.programs.save(program)
        }
        stack.clock.advance()
        return Bench(stack: stack, settings: settings)
    }

    static var equipment: [ExerciseID: Equipment] {
        Dictionary(uniqueKeysWithValues: S2Kit.slotExercises.map { ($0.id, $0.equipment) })
    }

    @Test("A refused program write rolls the settings back too; Try again then converts both")
    func refusedProgramWrite_rollsBack_thenRetryConverts() async throws {
        let program = try S2Kit.program(weeks: 2, days: 2, slotsPerDay: 3)
        let bench = try await Self.bench(programs: [program])
        let queue = bench.stack.queue
        let programBefore = try await ProgramRoundTripAdversarialTests.dump(queue)
        let settingsBefore = try await Self.settingsRow(queue)
        try await queue.write { database in
            try database.execute(sql: """
            CREATE TRIGGER refuse_slot BEFORE UPDATE ON slot BEGIN SELECT RAISE(ABORT, 'refused'); END
            """)
        }
        await #expect(throws: (any Error).self) {
            try await bench.settings.switchUnits(Self.settings(.kg))
        }
        #expect(try await ProgramRoundTripAdversarialTests.dump(queue) == programBefore)
        #expect(try await Self.settingsRow(queue) == settingsBefore)
        #expect(try await bench.settings.load().units == .lb)

        try await queue.write { try $0.execute(sql: "DROP TRIGGER refuse_slot") }
        try await bench.settings.switchUnits(Self.settings(.kg))
        #expect(try await bench.settings.load().units == .kg)
        let expected = UnitSwitch.convert(program, to: .kg, equipment: Self.equipment)
        #expect(try await bench.stack.programs.active() == expected)
    }

    @Test("A refused settings write leaves the program as it was")
    func refusedSettingsWrite_leavesTheProgram() async throws {
        let bench = try await Self.bench(programs: [S2Kit.program(weeks: 2, days: 1, slotsPerDay: 4)])
        let queue = bench.stack.queue
        let before = try await ProgramRoundTripAdversarialTests.dump(queue)
        try await queue.write { database in
            try database.execute(sql: """
            CREATE TRIGGER refuse_settings BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT, 'refused'); END
            """)
        }
        await #expect(throws: (any Error).self) {
            try await bench.settings.switchUnits(Self.settings(.kg))
        }
        #expect(try await ProgramRoundTripAdversarialTests.dump(queue) == before)
        #expect(try await bench.settings.load().units == .lb)
    }

    @Test("Switching to the units already stored writes the settings but leaves loads off the grid alone")
    func sameUnits_noConversion() async throws {
        var program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 2)
        program.days[0].slots[0].startLoad = .pounds(46.25)
        program.days[0].slots[0].step = .pounds(1.25)
        let bench = try await Self.bench(programs: [program])
        let before = try await ProgramRoundTripAdversarialTests.dump(bench.stack.queue)
        var changed = Self.settings(.lb)
        changed.autoRest = false
        try await bench.settings.switchUnits(changed)
        #expect(try await bench.settings.load() == changed)
        #expect(try await ProgramRoundTripAdversarialTests.dump(bench.stack.queue) == before)
    }

    @Test("Only the active program is converted; an inactive one keeps its weights")
    func inactiveProgram_untouched() async throws {
        let inactive = try S2Kit.program(2, weeks: 2, days: 1, slotsPerDay: 3, isActive: false)
        let active = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 3)
        let bench = try await Self.bench(programs: [inactive, active])
        try await bench.settings.switchUnits(Self.settings(.kg))
        #expect(try await bench.stack.programs.program(id: inactive.id) == inactive)
        #expect(try await bench.stack.programs.active() == UnitSwitch.convert(
            active,
            to: .kg,
            equipment: Self.equipment
        ))
    }

    @Test("With no active program, only the settings are written")
    func noProgram_onlySettings() async throws {
        let bench = try await Self.bench(programs: [])
        try await bench.settings.switchUnits(Self.settings(.kg))
        #expect(try await bench.settings.load().units == .kg)
        #expect(try await bench.stack.programs.active() == nil)
    }

    @Test("Each slot is converted by its exercise row's equipment: a kettlebell's 35 lb becomes 16 kg")
    func kettlebellRow_usesItsEquipment() async throws {
        let stack = try await S2Kit.stack()
        try await stack.exercises.save(S2Kit.exercise(40, "Swing", equipment: .kettlebell))
        var program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 2)
        program.days[0].slots[0].exerciseID = S2Kit.exerciseID(40)
        program.days[0].slots[0].startLoad = .pounds(35)
        program.days[0].slots[0].step = .pounds(5)
        program.days[0].slots[1].startLoad = .pounds(35)
        program.days[0].slots[1].step = .pounds(5)
        try await stack.programs.save(program)
        let settings = GRDBSettingsRepository(stack.queue, now: { stack.clock.now })
        try await settings.save(Self.settings(.lb))
        try await settings.switchUnits(Self.settings(.kg))
        let slots = try #require(try await stack.programs.active()?.days.first?.slots)
        #expect(slots[0].startLoad == .kilograms(16))
        #expect(slots[0].step == .kilograms(2))
        // A barbell: 35 lb is 15.88 kg, 15 on its 2.5 kg grid.
        #expect(slots[1].startLoad == .kilograms(15))
        #expect(slots[1].step == .kilograms(2.5))
    }

    @Test("Over an unreadable settings row, switchUnits to the units the program is already in still rounds it")
    func unreadableRow_sameUnits_convertsAnyway() async throws {
        var program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 2)
        program.days[0].slots[0].startLoad = .pounds(46.25)
        let bench = try await Self.bench(programs: [program])
        try await S2Kit.damage(bench.stack.queue, "UPDATE settings SET payload = 'not json'")
        try await bench.settings.switchUnits(Self.settings(.lb))
        let load = try await bench.stack.programs.active()?.days[0].slots[0].startLoad
        // As documented ("cannot be read: converted"). The store sends only a change of units here (held).
        #expect(load == .pounds(45))
    }

    @Test("GRDB and the in-memory stores convert the same program the same way through lb → kg → lb → kg")
    func differential_inMemoryAgrees() async throws {
        let program = try S2Kit.program(weeks: 2, days: 3, slotsPerDay: 5)
        let bench = try await Self.bench(programs: [program])
        let memory = InMemoryStores(seed: .init(
            catalog: S2Kit.slotExercises,
            programs: [program],
            settings: Self.settings(.lb)
        ))
        for units in [Units.kg, .lb, .kg, .kg] {
            try await bench.settings.switchUnits(Self.settings(units))
            try await memory.settings.switchUnits(Self.settings(units))
            let database = try await bench.stack.programs.active()
            let inMemory = try await memory.programs.active()
            #expect(database == inMemory, "after switching to \(units)")
            #expect(try await memory.settings.load().units == units)
        }
    }
}
