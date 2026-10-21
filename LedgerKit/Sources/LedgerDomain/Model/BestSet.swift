import Foundation

/// The heaviest set of an exercise, and of two as heavy the one with more reps, over the sets that count toward
/// a best (`StatsQueries.bestSets()`; product decision #25).
public struct BestSet: Hashable, Sendable {
    public let weight: Weight
    public let reps: Reps

    public init(weight: Weight, reps: Reps) {
        self.weight = weight
        self.reps = reps
    }
}
