import Foundation

/// Session length estimate (decision #14: one formula everywhere, replacing rule 37's two).
public enum TimeEstimate {
    /// Assumed work time per set (rule 37).
    public static let secondsPerSet = 42

    /// Decision #14: Σ over slots of `(sets + dropSets) × 42 s`, plus rest, where every block of
    /// slots joined by `isSupersetWithPrevious` rests once per round for its longest member rest.
    /// A block has `max(sets)` working rounds plus one drop round when any member has a drop
    /// set (the same rounds as `SupersetRounds`), so a straight slot rests after every set.
    /// The total is rounded to the nearest whole minute (half up).
    ///
    /// `sets` and `rest` come from `prescriptions[slot.id]` (deload weeks have one fewer set) and
    /// fall back to the slot's own values when a slot has no prescription.
    public static func minutes(day: DayTemplate, prescriptions: [SlotID: Prescription]) -> Int {
        let slots = day.slots
        let groups = SupersetRounds.groups(joiningPrevious: slots.map(\.isSupersetWithPrevious))
        let seconds = groups.reduce(0) { total, group in
            let members = group.map { slots[$0] }
            let sets = members.map { prescriptions[$0.id]?.sets ?? $0.sets }
            let rests = members.map { (prescriptions[$0.id]?.rest ?? $0.rest).seconds }
            let drops = members.map(\.dropSets)
            let work = zip(sets, drops).reduce(0) { $0 + ($1.0 + $1.1) * secondsPerSet }
            let rounds = (sets.max() ?? 0) + (drops.max() ?? 0)
            return total + work + rounds * (rests.max() ?? 0)
        }
        return (seconds + 30) / 60
    }
}
