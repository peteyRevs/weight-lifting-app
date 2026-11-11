import Foundation

/// What a swap brings besides the exercise's id and name (F10 S8, the payload of `exerciseSwapped`): the
/// replacement's equipment, step and last performance, which the device that swaps looks up and a peer may not
/// be able to (the watch holds no history), and the load its undone sets take. The device that swaps computes it
/// with `SwapAlternatives.replacement(of:with:last:units:)`; the reducer only copies it, so every device that
/// replays the swap reaches the same workout.
public struct SwappedExercise: Hashable, Codable, Sendable {
    /// The replacement's equipment.
    public let equipment: Equipment
    /// The replacement's default step in the workout's units (decision #22): the "+" and "−" of its sets.
    public let step: Weight
    /// What every undone set takes except a drop set (working, added and warm-up alike), and the exercise's
    /// target load (Q1, Q5); an undone drop set takes `SessionBuilder.dropLoad(of:step:)` of it.
    public let load: Weight
    /// The replacement's most recent session, the "Last" line; `nil` when it was never done.
    public let lastPerformance: LastPerformance?

    public init(equipment: Equipment, step: Weight, load: Weight, lastPerformance: LastPerformance?) {
        self.equipment = equipment
        self.step = step
        self.load = load
        self.lastPerformance = lastPerformance
    }
}
