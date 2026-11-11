import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: `UnitSwitch.convert` (criterion 1's program part, N11; Pete's question 1, A), attacked with
/// hand-worked values in both directions, every equipment's grid, steps finer than a grid, nil fields, exercises the
/// map lacks, and seeded properties: idempotence, the grid, the half-step bound, decodability, nothing else moved.
@Suite("Adversarial F14 S2 · UnitSwitch", .tags(.domain))
struct UnitSwitchAdversarialTests {
    static let barbell = Seeders.catalogID(0)
    static let kettlebell = Seeders.catalogID(1)
    static let dumbbell = Seeders.catalogID(2)
    static let missing = Seeders.catalogID(99)
    static let equipment: [ExerciseID: Equipment] = [barbell: .barbell, kettlebell: .kettlebell, dumbbell: .dumbbell]

    /// A one-day program whose only slot is `exercise` with these loads.
    static func program(_ exercise: ExerciseID, load: Weight?, step: Weight?) throws -> Program {
        var program = try Seeders.program(weeks: 2, days: 1, slotsPerDay: 1, exercises: [exercise])
        program.days[0].slots[0].startLoad = load
        program.days[0].slots[0].step = step
        return program
    }

    static func converted(
        _ exercise: ExerciseID,
        load: Weight?,
        step: Weight? = nil,
        to units: Units
    ) throws -> Slot {
        let program = try program(exercise, load: load, step: step)
        return UnitSwitch.convert(program, to: units, equipment: equipment).days[0].slots[0]
    }

    // MARK: - Hand-worked values

    @Test("Pounds to kilograms on a barbell rounds each load to the nearest 2.5 kg", arguments: [
        (45, 20), (135, 60), (225, 102.5), (315, 142.5), (405, 182.5), (0, 0), (2.5, 0), (3, 2.5), (500, 227.5)
    ] as [(Decimal, Decimal)])
    func barbell_poundsToKilograms(pounds: Decimal, kilograms: Decimal) throws {
        let slot = try Self.converted(Self.barbell, load: .pounds(pounds), to: .kg)
        #expect(slot.startLoad == .kilograms(kilograms), "\(pounds) lb")
    }

    @Test(
        "Kilograms to pounds on a barbell rounds each load to the nearest 5 lb (60 kg comes back as 130 lb)",
        arguments: [(20, 45), (60, 130), (62.5, 140), (100, 220), (102.5, 225), (142.5, 315)] as [(Decimal, Decimal)]
    )
    func barbell_kilogramsToPounds(kilograms: Decimal, pounds: Decimal) throws {
        let slot = try Self.converted(Self.barbell, load: .kilograms(kilograms), to: .lb)
        #expect(slot.startLoad == .pounds(pounds), "\(kilograms) kg")
    }

    @Test("Kettlebells land on 2 kg bells and 5 lb bells", arguments: [
        (Units.kg, Weight.pounds(35), Weight.kilograms(16)), (.kg, .pounds(53), .kilograms(24)),
        (.kg, .pounds(70), .kilograms(32)), (.kg, .pounds(18), .kilograms(8)),
        (.lb, .kilograms(16), .pounds(35)), (.lb, .kilograms(24), .pounds(55)), (.lb, .kilograms(32), .pounds(70)),
        (.lb, .kilograms(12), .pounds(25))
    ])
    func kettlebell_landsOnBells(units: Units, load: Weight, expected: Weight) throws {
        let slot = try Self.converted(Self.kettlebell, load: load, to: units)
        #expect(slot.startLoad == expected)
    }

    @Test("A step is converted and rounded, never below one default step of the new unit", arguments: [
        // barbell
        (barbell, Weight.pounds(5), Units.kg, Weight.kilograms(2.5)),
        (barbell, .pounds(10), .kg, .kilograms(5)),
        (barbell, .pounds(2.5), .kg, .kilograms(2.5)),
        (barbell, .pounds(1.25), .kg, .kilograms(2.5)),
        (barbell, .kilograms(2.5), .lb, .pounds(5)),
        (barbell, .kilograms(1.25), .lb, .pounds(5)),
        (barbell, .kilograms(5), .lb, .pounds(10)),
        (barbell, .kilograms(0.5), .lb, .pounds(5)),
        // kettlebell
        (kettlebell, .pounds(5), .kg, .kilograms(2)),
        (kettlebell, .pounds(10), .kg, .kilograms(4)),
        (kettlebell, .kilograms(2), .lb, .pounds(5)),
        (kettlebell, .kilograms(1), .lb, .pounds(5)),
        // dumbbell
        (dumbbell, .pounds(2.5), .kg, .kilograms(1.25)),
        (dumbbell, .pounds(5), .kg, .kilograms(2.5)),
        (dumbbell, .kilograms(1.25), .lb, .pounds(2.5)),
        (dumbbell, .kilograms(0.5), .lb, .pounds(2.5)),
        // not in the map: the finest grid of the unit
        (missing, .pounds(5), .kg, .kilograms(2.5)),
        (missing, .pounds(1), .kg, .kilograms(1.25))
    ])
    func step_neverBelowOneDefaultStep(exercise: ExerciseID, step: Weight, units: Units, expected: Weight) throws {
        let slot = try Self.converted(exercise, load: nil, step: step, to: units)
        #expect(slot.step == expected)
        #expect(slot.startLoad == nil)
    }

    @Test("nil loads and nil steps stay nil, in both directions", arguments: Units.allCases)
    func nilFields_stayNil(units: Units) throws {
        let slot = try Self.converted(Self.barbell, load: nil, step: nil, to: units)
        #expect(slot.startLoad == nil)
        #expect(slot.step == nil)
    }

    @Test("An exercise the map lacks is rounded on the unit's finest grid (1.25 kg, 2.5 lb)")
    func missingExercise_roundsOnTheFinestGrid() throws {
        // 135 lb = 61.235 kg: 60 on a barbell's grid, 61.25 on the finest.
        #expect(try Self.converted(Self.missing, load: .pounds(135), to: .kg).startLoad == .kilograms(61.25))
        // 62 kg = 136.69 lb: 135 on a barbell's 5 lb grid, 137.5 on the finest.
        #expect(try Self.converted(Self.missing, load: .kilograms(62), to: .lb).startLoad == .pounds(137.5))
    }

    @Test("A tie on the grid goes away from zero (decision #3), so the result does not depend on the platform")
    func tie_goesAwayFromZero() throws {
        // A load stored between two steps in the unit it is already in: 21.25 kg is half-way between 20 and 22.5.
        #expect(try Self.converted(Self.barbell, load: .kilograms(21.25), to: .kg).startLoad == .kilograms(22.5))
        #expect(try Self.converted(Self.barbell, load: .pounds(47.5), to: .lb).startLoad == .pounds(50))
    }

    @Test("Converting a program with no days, or days with no slots, returns it unchanged")
    func emptyShapes_unchanged() throws {
        let empty = try Seeders.program(weeks: 2, days: 0, slotsPerDay: 0, exercises: [Self.barbell])
        #expect(UnitSwitch.convert(empty, to: .kg, equipment: Self.equipment) == empty)
        let noSlots = try Seeders.program(weeks: 2, days: 3, slotsPerDay: 0, exercises: [Self.barbell])
        #expect(UnitSwitch.convert(noSlots, to: .lb, equipment: [:]) == noSlots)
    }
}
