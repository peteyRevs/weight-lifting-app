import Foundation
@testable import LedgerDomain
import Testing

/// F14 S2, criterion 1's program part (Pete's question 1, A): a switch of units rounds each explicit start load and
/// step to the default grid of its exercise's equipment in the new unit, and leaves `nil` alone.
@Suite("UnitSwitch", .tags(.domain))
struct UnitSwitchTests {
    static let equipment = Fixtures.catalog.mapValues(\.equipment)

    /// A one-day program whose one slot is `exercise` with `load` and `step`.
    static func oneSlotProgram(_ exercise: Exercise, load: Weight?, step: Weight? = nil) throws -> Program {
        let day = try DayTemplate(
            id: DayTemplateID(Fixtures.uuid(300)),
            name: "Day",
            tag: "D1",
            slots: [Fixtures.slot(exercise, id: 301, startLoad: load, step: step)]
        )
        return try Fixtures.program(days: [day])
    }

    static func slot(of program: Program) throws -> Slot {
        try #require(program.days.first?.slots.first)
    }

    static func converted(
        _ exercise: Exercise,
        load: Weight?,
        step: Weight? = nil,
        to units: Units
    ) throws -> Slot {
        let program = try oneSlotProgram(exercise, load: load, step: step)
        return try slot(of: UnitSwitch.convert(program, to: units, equipment: equipment))
    }

    @Test("A 45 lb bar becomes 20 kg, 135 lb 60 kg, 180 lb 82.5 kg: the nearest 2.5 kg", arguments: [
        ("45", "20"), ("135", "60"), ("180", "82.5"), ("225", "102.5")
    ])
    func barbell_poundsToKilograms_nearestStep(_ pounds: String, _ kilograms: String) throws {
        let slot = try Self.converted(Fixtures.bench, load: .pounds(dec(pounds)), to: .kg)
        #expect(slot.startLoad == .kilograms(dec(kilograms)))
    }

    @Test("Back to pounds: 60 kg is 130 lb, one step from the 135 it came from; 20 kg is 45 lb (R6)")
    func roundTrip_driftsAtMostOneStep() throws {
        let kilograms = try UnitSwitch.convert(
            Self.oneSlotProgram(Fixtures.bench, load: .pounds(135)),
            to: .kg,
            equipment: Self.equipment
        )
        let pounds = try Self.slot(of: UnitSwitch.convert(kilograms, to: .lb, equipment: Self.equipment))
        #expect(pounds.startLoad == .pounds(130))
        let bar = try Self.converted(Fixtures.bench, load: .kilograms(20), to: .lb)
        #expect(bar.startLoad == .pounds(45))
    }

    @Test("A dumbbell and a cable move on 1.25 kg; a kettlebell on 2 kg (decision #22)")
    func otherEquipment_movesOnItsOwnGrid() throws {
        // 50 lb is 22.68 kg, 12.5 lb 5.67 kg.
        #expect(try Self.converted(Fixtures.inclineDB, load: .pounds(50), to: .kg).startLoad == .kilograms(22.5))
        #expect(try Self.converted(Fixtures.lateralRaise, load: .pounds(12.5), to: .kg).startLoad == .kilograms(6.25))
        let bell = Fixtures.exercise(40, "Kettlebell Swing", .kettlebell, pounds: 35, kilograms: 16)
        let withBell = Self.equipment.merging([bell.id: .kettlebell]) { _, new in new }
        let program = try Self.oneSlotProgram(bell, load: .pounds(35))
        // 35 lb is 15.88 kg: the nearest 2 kg is 16.
        #expect(try Self.slot(of: UnitSwitch.convert(program, to: .kg, equipment: withBell))
            .startLoad == .kilograms(16))
    }

    @Test("An explicit step is converted the same way, and never below one default step")
    func explicitStep_convertedAndAtLeastOneStep() throws {
        #expect(try Self.converted(Fixtures.bench, load: nil, step: .pounds(5), to: .kg).step == .kilograms(2.5))
        #expect(try Self.converted(Fixtures.bench, load: nil, step: .pounds(10), to: .kg).step == .kilograms(5))
        // 2.5 lb is 1.13 kg, nearest the 0 of a 2.5 kg grid: one default step instead.
        #expect(try Self.converted(Fixtures.bench, load: nil, step: .pounds(2.5), to: .kg).step == .kilograms(2.5))
        #expect(try Self.converted(Fixtures.inclineDB, load: nil, step: .pounds(2.5), to: .kg).step == .kilograms(1.25))
    }

    @Test("No load and no step of its own stay nil")
    func nilFields_stayNil() throws {
        let slot = try Self.converted(Fixtures.bench, load: nil, to: .kg)
        #expect(slot.startLoad == nil && slot.step == nil)
    }

    @Test("An exercise the map lacks moves on the finest grid: 1.25 kg")
    func unknownExercise_finestGrid() throws {
        let program = try Self.oneSlotProgram(Fixtures.bench, load: .pounds(45))
        // 20.41 kg on 1.25 kg is 20.
        let slot = try Self.slot(of: UnitSwitch.convert(program, to: .kg, equipment: [:]))
        #expect(slot.startLoad == .kilograms(20))
    }

    @Test("Everything but the loads and steps is kept, and the result still validates")
    func otherFields_kept_andValid() throws {
        let program = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let converted = UnitSwitch.convert(program, to: .kg, equipment: Self.equipment)
        let keptIsSame = converted.days.map(\.slots.count) == program.days.map(\.slots.count)
            && converted.weeks == program.weeks && converted.name == program.name
        #expect(keptIsSame)
        let data = try JSONEncoder().encode(converted)
        let decoded = try JSONDecoder().decode(Program.self, from: data)
        let roundTrips = decoded == converted
        #expect(roundTrips)
    }

    /// N11: converting twice equals converting once, for any load and step, either way.
    @Test(
        "Idempotent: converting twice gives what converting once gives",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func convert_isIdempotent(_ seed: PropertySeed) throws {
        var generator = seed.generator
        let exercises = [Fixtures.bench, Fixtures.inclineDB, Fixtures.latPulldown, Fixtures.backSquat]
        let exercise = try #require(exercises.randomElement(using: &generator))
        // Loads to 500 in hundredths of a unit, either unit; a step from 0.01 up to 25.
        let from: Units = Bool.random(using: &generator) ? .lb : .kg
        let load = Decimal(Int.random(in: 0 ... 50000, using: &generator)) / 100
        let step = Decimal(Int.random(in: 1 ... 2500, using: &generator)) / 100
        let loadWeight: Weight = from == .lb ? .pounds(load) : .kilograms(load)
        let stepWeight: Weight = from == .lb ? .pounds(step) : .kilograms(step)
        let program = try Self.oneSlotProgram(exercise, load: loadWeight, step: stepWeight)
        let target: Units = Bool.random(using: &generator) ? .lb : .kg
        let once = UnitSwitch.convert(program, to: target, equipment: Self.equipment)
        let twice = UnitSwitch.convert(once, to: target, equipment: Self.equipment)
        let isIdempotent = once == twice
        #expect(isIdempotent, "\(seed): \(load) \(from) by \(step) to \(target)")
    }
}
