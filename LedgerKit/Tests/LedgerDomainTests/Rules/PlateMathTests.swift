import Foundation
@testable import LedgerDomain
import Testing

@Suite("PlateMath", .tags(.domain))
struct PlateMathTests {
    private let pounds = PlateInventory.standard(.lb)
    private let kilograms = PlateInventory.standard(.kg)

    private func line(_ load: Weight, _ inventory: PlateInventory, _ units: Units = .lb) -> String? {
        PlateMath.perSide(load: load, inventory: inventory)?.line(units: units)
    }

    @Test("185 lb is 45 + 25 per side (rule 38, criterion 6)")
    func perSide_185lb_is45plus25() throws {
        let breakdown = try #require(PlateMath.perSide(load: .pounds(185), inventory: pounds))
        #expect(breakdown.perSide == [
            PlateMath.PlateCount(plate: .pounds(45), count: 1),
            PlateMath.PlateCount(plate: .pounds(25), count: 1)
        ])
        #expect(breakdown.remainder == .zero)
        #expect(breakdown.line(units: .lb) == "45 + 25 / side")
    }

    @Test("180 lb is 45 + 2×10 + 2.5 per side (rule 38, criterion 6)")
    func perSide_180lb_is45_2x10_2p5() {
        #expect(line(.pounds(180), pounds) == "45 + 2×10 + 2.5 / side")
    }

    @Test("250 lb is 2×45 + 10 + 2.5 per side (rule 38, criterion 6)")
    func perSide_250lb_is2x45_10_2p5() {
        #expect(line(.pounds(250), pounds) == "2×45 + 10 + 2.5 / side")
    }

    @Test("Below the smallest plate per side there is no line (rule 38, criterion 6)")
    func perSide_belowSmallestPlate_isNil() {
        #expect(line(.pounds(47.5), pounds) == nil)
        #expect(line(.pounds(49), pounds) == nil)
        #expect(line(.pounds(50), pounds) == "2.5 / side")
    }

    @Test("A load at or below the bar has no line")
    func perSide_loadBelowBar_isNil() {
        #expect(line(.pounds(45), pounds) == nil)
        #expect(line(.pounds(20), pounds) == nil)
        #expect(line(.zero, kilograms, .kg) == nil)
    }

    @Test("Kilogram loads use the 20 kg bar and kg plates (decision #9)")
    func perSide_kg_20kgBar_usesKgInventory() {
        #expect(line(.kilograms(60), kilograms, .kg) == "20 / side")
        #expect(line(.kilograms(62.5), kilograms, .kg) == "20 + 1.25 / side")
        #expect(line(.kilograms(100), kilograms, .kg) == "2×20 / side")
        #expect(line(.kilograms(97.5), kilograms, .kg) == "20 + 15 + 2.5 + 1.25 / side")
    }

    @Test("Without 25s the greedy fill falls to smaller plates")
    func perSide_inventoryWithout25s_fallsToSmallerPlates() {
        let no25s = PlateInventory(bar: .pounds(45), plates: [45, 10, 5, 2.5].map(Weight.pounds))
        #expect(line(.pounds(185), no25s) == "45 + 2×10 + 5 / side")
    }

    @Test("What the plates cannot make up is reported as the remainder; no plates means no line")
    func perSide_remainderAndEmptyInventory() throws {
        let breakdown = try #require(PlateMath.perSide(load: .pounds(186), inventory: pounds))
        #expect(breakdown.line(units: .lb) == "45 + 25 / side")
        #expect(breakdown.remainder == .pounds(0.5))
        #expect(PlateMath.perSide(load: .pounds(185), inventory: PlateInventory(bar: .pounds(45), plates: [])) == nil)
    }

    @Test(
        "A breakdown uses only inventory plates and never loads more than the bar needs",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func perSide_neverExceedsInventoryCount(seed: PropertySeed) throws {
        var generator = seed.generator
        let units = try #require(Units.allCases.randomElement(using: &generator))
        let inventory = PlateInventory.standard(units)
        let load = inventory.bar.advanced(
            bySteps: Int.random(in: -10 ... 400, using: &generator),
            of: units == .lb ? .pounds(0.5) : .kilograms(0.25)
        )
        let smallest = try #require(inventory.plates.last)
        let perSide = Decimal(load.quanta(in: units) - inventory.bar.quanta(in: units)) / 2
        guard let breakdown = PlateMath.perSide(load: load, inventory: inventory) else {
            #expect(perSide < Decimal(smallest.quanta(in: units)))
            return
        }
        #expect(breakdown.perSide.allSatisfy { inventory.plates.contains($0.plate) && $0.count >= 1 })
        #expect(breakdown.perSide.map(\.plate) == breakdown.perSide.map(\.plate).sorted(by: >))
        let loaded = breakdown.perSide.reduce(Decimal(0)) { $0 + Decimal($1.count * $1.plate.quanta(in: units)) }
        #expect(loaded <= perSide)
        #expect(perSide - loaded < Decimal(smallest.quanta(in: units)))
        #expect(breakdown.remainder < smallest)
    }
}
