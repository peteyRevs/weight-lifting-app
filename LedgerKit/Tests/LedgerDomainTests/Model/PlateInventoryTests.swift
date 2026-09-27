import Foundation
@testable import LedgerDomain
import Testing

@Suite("PlateInventory", .tags(.domain))
struct PlateInventoryTests {
    @Test("Standard inventories: 45 lb bar with 45/25/10/5/2.5, 20 kg bar with 20…1.25 (decision #9)")
    func standard_perUnit() {
        let pounds = PlateInventory.standard(.lb)
        let kilograms = PlateInventory.standard(.kg)
        #expect(pounds.bar == .pounds(45))
        #expect(pounds.plates == [45, 25, 10, 5, 2.5].map(Weight.pounds))
        #expect(kilograms.bar == .kilograms(20))
        #expect(kilograms.plates == [20, 15, 10, 5, 2.5, 1.25].map(Weight.kilograms))
    }

    @Test("Plates are normalised: heaviest first, no duplicates, positive only")
    func init_normalisesPlates() throws {
        let inventory = PlateInventory(
            bar: .pounds(35),
            plates: [.pounds(5), .pounds(45), .zero, .pounds(5), .pounds(-10)]
        )
        #expect(inventory.plates == [.pounds(45), .pounds(5)])
        let json = #"{"bar":{"grams":15876},"plates":[{"grams":2268},{"grams":20412},{"grams":2268}]}"#
        let decoded = try JSONDecoder().decode(PlateInventory.self, from: Data(json.utf8))
        #expect(decoded.plates == [.pounds(45), .pounds(5)])
        #expect(try JSONDecoder().decode(PlateInventory.self, from: JSONEncoder().encode(inventory)) == inventory)
    }
}
