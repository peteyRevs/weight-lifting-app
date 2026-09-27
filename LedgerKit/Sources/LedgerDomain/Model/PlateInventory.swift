import Foundation

/// The bar and plate sizes a lifter has, per unit (decisions #9, #10; rule 38).
///
/// `plates` lists plate sizes, each available in any number of pairs. The initializer and the
/// decoder normalise the list: positive sizes only, no duplicates, heaviest first.
public struct PlateInventory: Hashable, Codable, Sendable {
    public var bar: Weight
    /// Plate sizes, descending.
    public var plates: [Weight]

    public init(bar: Weight, plates: [Weight]) {
        self.bar = bar
        self.plates = Set(plates.filter { $0 > .zero }).sorted(by: >)
    }

    /// Decision #9 / rule 38: lb — 45 lb bar, 45/25/10/5/2.5; kg — 20 kg bar, 20/15/10/5/2.5/1.25.
    public static func standard(_ units: Units) -> PlateInventory {
        switch units {
        case .lb:
            PlateInventory(bar: .pounds(45), plates: [45, 25, 10, 5, 2.5].map(Weight.pounds))
        case .kg:
            PlateInventory(bar: .kilograms(20), plates: [20, 15, 10, 5, 2.5, 1.25].map(Weight.kilograms))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case bar, plates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            bar: container.decode(Weight.self, forKey: .bar),
            plates: container.decode([Weight].self, forKey: .plates)
        )
    }
}
