import Foundation

/// Estimated one-rep max (rule 40, decision #4).
public enum OneRepMax {
    /// Reps above this are not estimated (decision #4: r ≤ 12).
    public static let maximumReps = 12

    /// Decision #4 Brzycki: `w × 36 / (37 − r)`, exact `Decimal` maths rounded to the nearest gram;
    /// `nil` when `reps > 12` (which also keeps the `37 − r` divisor positive). One rep returns `weight`.
    ///
    /// Presentation rounds to a whole unit (`Weight.wholeValue(in:)`): 195 lb × 5 → 219.375 → 219 lb.
    /// The prototype's "218" was illustrative (F02 brief, risks).
    public static func brzycki(weight: Weight, reps: Reps) -> Weight? {
        guard reps.value <= maximumReps else {
            return nil
        }
        return Weight(grams: (Decimal(weight.grams * 36) / Decimal(37 - reps.value)).roundedToInt())
    }
}
