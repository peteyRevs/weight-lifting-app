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
        let rest = groups.reduce(0) { total, group in
            let members = group.map { slots[$0] }
            let sets = members.map { prescriptions[$0.id]?.sets ?? $0.sets }
            let rests = members.map { prescriptions[$0.id]?.rest ?? $0.rest }
            let rounds = (sets.max() ?? 0) + (members.map(\.dropSets).max() ?? 0)
            return total + rounds * SupersetRounds.groupRest(of: rests).seconds
        }
        let work = setCount(day: day, prescriptions: prescriptions) * secondsPerSet
        return (work + rest + 30) / 60
    }

    /// The sets a day asks for, as the estimate counts them: every slot's sets and its drop sets. `sets`
    /// comes from `prescriptions[slot.id]` (a deload week has one fewer) and falls back to the slot's own, so
    /// no prescriptions gives the count of the day as it is written.
    public static func setCount(day: DayTemplate, prescriptions: [SlotID: Prescription]) -> Int {
        day.slots.reduce(0) { $0 + (prescriptions[$1.id]?.sets ?? $1.sets) + $1.dropSets }
    }

    /// The sets of several days as they are written: a program's training days together.
    public static func setCount(days: [DayTemplate]) -> Int {
        days.reduce(0) { $0 + setCount(day: $1, prescriptions: [:]) }
    }
}
