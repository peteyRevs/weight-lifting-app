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
    /// Exact arithmetic (ADR-007), so 185 lb splits into exactly 45 + 25 per side.
    public static func perSide(load: Weight, inventory: PlateInventory) -> Breakdown? {
        let plates = inventory.plates.filter { $0 > .zero }.sorted(by: >)
        guard let smallest = plates.last else {
            return nil
        }
        var remaining = (load - inventory.bar).scaled(by: Decimal(sign: .plus, exponent: -1, significand: 5))
        guard remaining >= smallest else {
            return nil
        }
        var perSide: [PlateCount] = []
        for plate in plates {
            let count = (remaining.grams / plate.grams).roundedToInt(.down)
            if count > 0 {
                perSide.append(PlateCount(plate: plate, count: count))
                remaining -= plate.scaled(by: Decimal(count))
            }
        }
        return Breakdown(perSide: perSide, remainder: remaining)
    }
}
