import Foundation

/// Plates per side of the bar (rule 38; decisions #9, #10).
public enum PlateMath {
    /// One plate size and how many of it go on each side.
    public struct PlateCount: Hashable, Sendable {
        public let plate: Weight
        public let count: Int

        public init(plate: Weight, count: Int) {
            self.plate = plate
            self.count = count
        }
    }

    /// The plates to load on each side, heaviest first.
    public struct Breakdown: Hashable, Sendable {
        public let perSide: [PlateCount]
        /// Per-side weight the inventory could not make up (zero when the load is exact).
        public let remainder: Weight

        public init(perSide: [PlateCount], remainder: Weight = .zero) {
            self.perSide = perSide
            self.remainder = remainder
        }

        /// Rule 38: "{n}×{p}" for multiples, "{p}" for singles, joined by " + ", then " / side":
        /// "45 + 2×10 + 2.5 / side".
        public func line(units: Units) -> String {
            let parts = perSide.map { entry in
                let plate = entry.plate.formatted(in: units)
                return entry.count > 1 ? "\(entry.count)×\(plate)" : plate
            }
            return parts.joined(separator: " + ") + " / side"
        }
    }

    /// Rule 38: `perSide = (load − bar) / 2`; `nil` when that is below the smallest plate (which
    /// includes a load at or below the bar) or there are no plates; otherwise greedy descending.
    ///
    /// Runs in the inventory's own unit (`Units.denominating`: pounds when the bar and every plate
    /// are whole quarter pounds, else kilograms) so 185 lb splits into exactly 45 + 25 per side.
    public static func perSide(load: Weight, inventory: PlateInventory) -> Breakdown? {
        let weights = [inventory.bar] + inventory.plates
        let units: Units = weights.allSatisfy { Units.denominating($0) == .lb } ? .lb : .kg
        let plates = inventory.plates.filter { $0 > .zero }.sorted(by: >)
        guard let smallest = plates.last else {
            return nil
        }
        var remaining = Decimal(load.quanta(in: units) - inventory.bar.quanta(in: units)) / 2
        guard remaining >= Decimal(smallest.quanta(in: units)) else {
            return nil
        }
        var perSide: [PlateCount] = []
        for plate in plates {
            let size = Decimal(plate.quanta(in: units))
            let count = (remaining / size).roundedToInt(.down)
            if count > 0 {
                perSide.append(PlateCount(plate: plate, count: count))
                remaining -= Decimal(count) * size
            }
        }
        return Breakdown(perSide: perSide, remainder: Weight(quanta: remaining, in: units))
    }
}
