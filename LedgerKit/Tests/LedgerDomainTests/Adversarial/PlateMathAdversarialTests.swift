import Foundation
@testable import LedgerDomain
import Testing

@Suite("PlateMath (adversarial)", .tags(.domain))
struct PlateMathAdversarialTests {
    static func line(_ load: Weight, _ inventory: PlateInventory = .standard(.lb), units: Units = .lb) -> String? {
        PlateMath.perSide(load: load, inventory: inventory)?.line(units: units)
    }
}

extension PlateMathAdversarialTests {
    @Test(
        "Standard pound loads split greedily per side (criterion 6, rule 38).",
        arguments: [
            ("185", "45 + 25 / side"), ("180", "45 + 2×10 + 2.5 / side"), ("250", "2×45 + 10 + 2.5 / side"),
            ("50", "2.5 / side"), ("55", "5 / side"), ("135", "45 / side"), ("225", "2×45 / side"),
            ("405", "4×45 / side"), ("95", "25 / side"), ("100", "25 + 2.5 / side"), ("60", "5 + 2.5 / side"),
            ("1045", "11×45 + 5 / side")
        ]
    )
    func perSide_poundTable(load: String, line: String) {
        #expect(Self.line(pounds(load)) == line)
    }

    @Test(
        "Loads with less than the smallest plate per side have no line (criterion 6's 47.5, rule 38).",
        arguments: ["47.5", "45", "44", "0", "-100", "49.9"]
    )
    func perSide_belowSmallestPlate_isNil(load: String) {
        #expect(PlateMath.perSide(load: pounds(load), inventory: .standard(.lb)) == nil)
    }

    @Test(
        "Standard kilogram loads split over the kilogram plates (brief test plan).",
        arguments: [
            ("60", "20 / side"), ("62.5", "20 + 1.25 / side"), ("100", "2×20 / side"), (
                "57.5",
                "15 + 2.5 + 1.25 / side"
            ),
            ("22.5", "1.25 / side"), ("25", "2.5 / side"), ("70", "20 + 5 / side"), ("50", "15 / side")
        ]
    )
    func perSide_kiloTable(load: String, line: String) {
        #expect(Self.line(kilos(load), .standard(.kg), units: .kg) == line)
    }

    @Test("Kilogram loads under 1.25 kg per side have no line.", arguments: ["21", "20", "15"])
    func perSide_kiloBelowSmallest_isNil(load: String) {
        #expect(PlateMath.perSide(load: kilos(load), inventory: .standard(.kg)) == nil)
    }

    @Test("An inventory without 25s falls back to the smaller plates.")
    func perSide_without25s_usesSmaller() {
        let inventory = PlateInventory(
            bar: pounds("45"),
            plates: [pounds("45"), pounds("10"), pounds("5"), pounds("2.5")]
        )
        #expect(Self.line(pounds("185"), inventory) == "45 + 2×10 + 5 / side")
    }

    @Test("A 25 kg plate inventory uses the 25s first.")
    func perSide_kiloWith25s() {
        let plates = ["25", "20", "15", "10", "5", "2.5", "1.25"].map(kilos)
        let inventory = PlateInventory(bar: kilos("20"), plates: plates)
        // 120 kg: (120 − 20) / 2 = 50 → 2×25.
        #expect(Self.line(kilos("120"), inventory, units: .kg) == "2×25 / side")
    }

    @Test("Greedy fill keeps the unfilled remainder rather than searching (rule 38 'greedy').")
    func perSide_greedyRemainder() throws {
        // Per side 60 lb with 45/35/25: greedy takes 45, then 15 cannot be made.
        let inventory = PlateInventory(bar: pounds("45"), plates: [pounds("45"), pounds("35"), pounds("25")])
        let breakdown = try #require(PlateMath.perSide(load: pounds("165"), inventory: inventory))
        #expect(breakdown.perSide == [PlateMath.PlateCount(plate: pounds("45"), count: 1)])
        #expect(breakdown.remainder == pounds("15"))
    }

    @Test("A load the standard plates cannot make exactly reports the leftover per side.")
    func perSide_inexactLoad_reportsRemainder() throws {
        // 182.5 lb: (182.5 − 45) / 2 = 68.75 → 45 + 2×10 + 2.5, 1.25 left over.
        let breakdown = try #require(PlateMath.perSide(load: pounds("182.5"), inventory: .standard(.lb)))
        #expect(breakdown.perSide.map(\.count) == [1, 2, 1])
        #expect(breakdown.remainder == pounds("1.25"))
    }

    @Test("An empty plate list never produces a breakdown.")
    func perSide_noPlates_isNil() {
        #expect(PlateMath.perSide(load: pounds("225"), inventory: PlateInventory(bar: pounds("45"), plates: [])) == nil)
    }

    @Test("Inventories are normalised: positive, distinct, heaviest first (documented contract).")
    func inventory_isNormalised() throws {
        let inventory = PlateInventory(
            bar: pounds("45"),
            plates: [
                pounds("2.5"),
                pounds("45"),
                .zero,
                pounds("10"),
                pounds("45"),
                pounds("-5"),
                pounds("25"),
                pounds("5")
            ]
        )
        let expected = ["45", "25", "10", "5", "2.5"].map(pounds)
        #expect(inventory.plates == expected)
        #expect(Self.line(pounds("185"), inventory) == "45 + 25 / side")
        let decoded = try JSONDecoder().decode(
            PlateInventory.self,
            from: Adversarial
                .tampered(inventory) { $0["plates"] = try Adversarial.fragment(["5", "45", "5", "25"].map(pounds)) }
        )
        #expect(decoded.plates == ["45", "25", "5"].map(pounds))
    }

    @Test("Standard inventories match decision #9.")
    func standard_inventories() {
        #expect(PlateInventory.standard(.lb).bar == pounds("45"))
        #expect(PlateInventory.standard(.lb).plates == ["45", "25", "10", "5", "2.5"].map(pounds))
        #expect(PlateInventory.standard(.kg).bar == kilos("20"))
        #expect(PlateInventory.standard(.kg).plates == ["20", "15", "10", "5", "2.5", "1.25"].map(kilos))
    }
}

@Suite("PlateMath properties (adversarial)", .tags(.domain, .property))
struct PlateMathPropertyAdversarialTests {}

extension PlateMathPropertyAdversarialTests {
    @Test("Every 5 lb load from 50 to 1,000 lb is made exactly, heaviest plate first.", arguments: PropertySeed.all)
    func perSide_standardPounds_isExactAndDescending(seed: PropertySeed) throws {
        var generator = seed.generator
        let load = randomMultiple(of: 5, in: 10 ... 200, using: &generator)
        let breakdown = try #require(PlateMath.perSide(load: .pounds(load), inventory: .standard(.lb)))
        let total = breakdown.perSide
            .reduce(Decimal(0)) { $0 + decimalRounded($1.plate.pounds, scale: 2) * Decimal($1.count) }
        #expect(total == (load - 45) / 2, "\(load) lb")
        #expect(breakdown.remainder == .zero)
        #expect(breakdown.perSide.allSatisfy { $0.count >= 1 })
        #expect(breakdown.perSide.map(\.plate) == breakdown.perSide.map(\.plate).sorted(by: >))
        // Greedy oracle (rule 38): take as many of each plate, heaviest first, as still fit.
        var remaining = (load - 45) / 2
        var oracle: [String] = []
        for plate in ["45", "25", "10", "5", "2.5"].map(dec) {
            let count = NSDecimalNumber(decimal: decimalRounded(remaining / plate, .down)).intValue
            if count > 0 {
                oracle.append("\(plate)×\(count)")
                remaining -= plate * Decimal(count)
            }
        }
        let actual = breakdown.perSide.map { "\(decimalRounded($0.plate.pounds, scale: 2))×\($0.count)" }
        #expect(actual == oracle, "\(load) lb")
    }

    @Test("Every 2.5 kg load from 22.5 to 300 kg is made exactly by the kilogram set.", arguments: PropertySeed.all)
    func perSide_standardKilos_isExact(seed: PropertySeed) throws {
        var generator = seed.generator
        let load = randomMultiple(of: dec("2.5"), in: 9 ... 120, using: &generator)
        let breakdown = try #require(PlateMath.perSide(load: .kilograms(load), inventory: .standard(.kg)))
        let grams = breakdown.perSide.reduce(Decimal(0)) { $0 + $1.plate.grams * Decimal($1.count) }
        #expect(grams == (load - 20) / 2 * 1000, "\(load) kg")
        #expect(breakdown.remainder == .zero)
    }
}
