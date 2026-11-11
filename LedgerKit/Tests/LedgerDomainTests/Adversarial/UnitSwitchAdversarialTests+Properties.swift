import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: `UnitSwitch.convert`'s seeded properties.
extension UnitSwitchAdversarialTests {
    // MARK: - Properties

    /// A random program: every slot's exercise one of four (one the map lacks), its load and step random in either
    /// unit (or nil), at fine resolution so most are off every grid.
    static func randomProgram(_ seed: PropertySeed) throws -> Program {
        var generator = seed.generator
        let exercises = [barbell, kettlebell, dumbbell, missing]
        var program = try Seeders.program(
            number: Int(seed.value % 1000),
            weeks: 2,
            days: Int.random(in: 1 ... 4, using: &generator),
            slotsPerDay: Int.random(in: 1 ... 6, using: &generator),
            exercises: exercises
        )
        for day in program.days.indices {
            for index in program.days[day].slots.indices {
                program.days[day].slots[index].exerciseID = exercises.randomElement(using: &generator) ?? barbell
                program.days[day].slots[index].startLoad = randomWeight(&generator, upTo: 400_000, allowsZero: true)
                program.days[day].slots[index].step = randomWeight(&generator, upTo: 2000, allowsZero: false)
            }
        }
        return program
    }

    /// nil one time in four; else a whole number of hundredths in lb or kg up to `upTo` hundredths.
    static func randomWeight(_ generator: inout SeededGenerator, upTo: Int, allowsZero: Bool) -> Weight? {
        guard Int.random(in: 0 ..< 4, using: &generator) != 0 else {
            return nil
        }
        let hundredths = Int.random(in: (allowsZero ? 0 : 1) ... upTo, using: &generator)
        let value = Decimal(hundredths) / 100
        return Bool.random(using: &generator) ? .pounds(value) : .kilograms(value)
    }

    @Test(
        "Property: converting twice equals converting once, to either unit",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func property_idempotent(seed: PropertySeed) throws {
        let program = try Self.randomProgram(seed)
        for units in Units.allCases {
            let once = UnitSwitch.convert(program, to: units, equipment: Self.equipment)
            let twice = UnitSwitch.convert(once, to: units, equipment: Self.equipment)
            #expect(once == twice, "\(seed), \(units)")
        }
    }

    @Test(
        "Property: every load lands on its grid within half a step, every step on its grid and at least one step",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func property_onTheGrid(seed: PropertySeed) throws {
        let program = try Self.randomProgram(seed)
        for units in Units.allCases {
            let converted = UnitSwitch.convert(program, to: units, equipment: Self.equipment)
            for (before, after) in zip(program.days.flatMap(\.slots), converted.days.flatMap(\.slots)) {
                let grid = (Self.equipment[before.exerciseID] ?? .machine).defaultStep(in: units)
                #expect((before.startLoad == nil) == (after.startLoad == nil), "\(seed): load's nil kept")
                #expect((before.step == nil) == (after.step == nil), "\(seed): step's nil kept")
                if let load = after.startLoad, let original = before.startLoad {
                    let count = load.grams / grid.grams
                    #expect(count.rounded(scale: 0, .toNearestOrAwayFromZero) == count, "\(seed): load off the grid")
                    let distance = abs(load.grams - original.grams)
                    #expect(distance * 2 <= grid.grams, "\(seed): load moved more than half a step")
                    #expect(load >= .zero, "\(seed): negative load")
                }
                if let step = after.step {
                    let count = step.grams / grid.grams
                    #expect(count.rounded(scale: 0, .toNearestOrAwayFromZero) == count, "\(seed): step off the grid")
                    #expect(step >= grid, "\(seed): step below one default step")
                }
            }
        }
    }

    @Test(
        "Property: only start loads and steps change, and the result survives a decode (every range holds)",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func property_nothingElseMoves_andDecodes(seed: PropertySeed) throws {
        let program = try Self.randomProgram(seed)
        for units in Units.allCases {
            var converted = UnitSwitch.convert(program, to: units, equipment: Self.equipment)
            let decoded = try JSONDecoder().decode(Program.self, from: JSONEncoder().encode(converted))
            #expect(decoded == converted, "\(seed): the converted program does not decode back")
            for day in converted.days.indices {
                for index in converted.days[day].slots.indices {
                    converted.days[day].slots[index].startLoad = program.days[day].slots[index].startLoad
                    converted.days[day].slots[index].step = program.days[day].slots[index].step
                }
            }
            #expect(converted == program, "\(seed): a field other than a load or a step changed")
        }
    }

    @Test(
        "Property: a round trip lb → kg → lb lands within one grid step of the start (Q1's drift, bounded)",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func property_roundTripDriftIsBounded(seed: PropertySeed) throws {
        let start = try UnitSwitch.convert(Self.randomProgram(seed), to: .lb, equipment: Self.equipment)
        let back = UnitSwitch.convert(
            UnitSwitch.convert(start, to: .kg, equipment: Self.equipment),
            to: .lb,
            equipment: Self.equipment
        )
        for (before, after) in zip(start.days.flatMap(\.slots), back.days.flatMap(\.slots)) {
            guard let original = before.startLoad, let returned = after.startLoad else {
                continue
            }
            let grid = (Self.equipment[before.exerciseID] ?? .machine).defaultStep(in: .lb)
            let kgGrid = (Self.equipment[before.exerciseID] ?? .machine).defaultStep(in: .kg)
            // Half a kg step out, half a lb step back.
            #expect(abs(returned.grams - original.grams) * 2 <= kgGrid.grams + grid.grams, "\(seed)")
        }
    }
}
