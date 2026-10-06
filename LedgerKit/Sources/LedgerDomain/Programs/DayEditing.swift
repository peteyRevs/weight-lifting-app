import Foundation

/// One field of a slot, with the value it is set to (spec §3.4, the Day editor's stepper fields).
public enum SlotField: Hashable, Sendable {
    case sets(Int)
    case reps(Int)
    /// The top of the double-progression range.
    case repsHi(Int)
    case rpe(Decimal)
    case restSeconds(Int)
    case startLoad(Weight)

    /// A field without a value: what a stepper names when it asks for the value one step away.
    public enum Kind: Hashable, Sendable, CaseIterable {
        case sets, reps, repsHi, rpe, rest, startLoad
    }
}

/// Which way a stepper button moves a value: "−" downward, "+" upward.
public enum StepDirection: Hashable, Sendable {
    case downward, upward
}

/// Which way a slot is carried within its day: "Move up" upward, towards the day's first slot, and
/// "Move down" downward.
public enum MoveDirection: Hashable, Sendable {
    case upward, downward
}

/// The Day editor's edits to one training day (spec §3.4; rules 1–3, 6 and 7), as pure functions from a day
/// to the edited day. `ProgramEditing.updateDay` applies one inside a program. A store adds nothing to them:
/// every clamp, the coupling of reps and the top of the range, and the order of slots are decided here.
///
/// **Normal form.** A superset group is a run of slots in which every slot after the first has
/// `isSupersetWithPrevious` set; every reader ignores the flag of a day's first slot
/// (`SupersetRounds.groups`). A day is in normal form when that flag is false. Every function reads the day
/// it is given as its normal form and returns a day in normal form, so the first slot of every group has the
/// flag false.
///
/// Every function is total. Given a slot id the day does not hold, a function returns the day as it reads it,
/// which for a day in normal form is the day unchanged. Given a day whose slots `Slot.init` accepts, every
/// slot of the result is one it accepts too; fields are assigned directly, because each function keeps the
/// ranges itself.
///
/// No function changes the misses or the exercise of a slot the day already holds: a workout's save writes
/// those (F11 slice S1, criterion 12).
public enum DayEditing {
    // MARK: - Slots

    /// A slot for an exercise picked from the library, with rule 7's defaults: 3 × 8, top of range 10, RPE 8,
    /// linear, rest `defaultRest`, and the exercise's start load in `units` copied in (decision #24). It has
    /// no step of its own, no drop set, no misses, and is joined to no slot.
    ///
    /// - Throws: `SlotValidationError.negativeStartLoad` when the exercise's start load is below zero, which
    ///   only a custom exercise can hold.
    public static func newSlot(
        id: SlotID,
        exercise: Exercise,
        units: Units,
        defaultRest: RestDuration
    ) throws(SlotValidationError) -> Slot {
        try Slot(
            id: id,
            exerciseID: exercise.id,
            sets: 3,
            reps: 8,
            repsHi: 10,
            rpe: 8,
            restSeconds: defaultRest.seconds,
            progression: .linear,
            startLoad: exercise.startLoad(in: units)
        )
    }

    /// Appends `slots` in order. One whose id the day already holds is left out; the same exercise may be in
    /// a day twice, under two ids. An appended slot keeps its own `isSupersetWithPrevious`: one that arrives
    /// with it set joins the slot before it, which for the first appended is the day's last slot. `newSlot`
    /// never sets it.
    public static func addSlots(_ day: DayTemplate, _ slots: [Slot]) -> DayTemplate {
        var edited = day
        for slot in slots where !edited.slots.contains(where: { $0.id == slot.id }) {
            edited.slots.append(slot)
        }
        return normalized(edited)
    }

    /// "Remove". When the slot led a superset group, the next member leads what is left of it.
    public static func removeSlot(_ day: DayTemplate, slot: SlotID) -> DayTemplate {
        editing(day, slot: slot) { slots, index in
            let removed = slots.remove(at: index)
            if !removed.isSupersetWithPrevious, slots.indices.contains(index) {
                slots[index].isSupersetWithPrevious = false
            }
        }
    }

    // MARK: - Progression, drop set, superset

    /// "PROGRESSION". Changing to double progression makes the top of the range at least `reps + 2`; leaving
    /// it keeps the top as it is. Choosing the progression the slot already has changes nothing, so a second
    /// tap on "Double" never widens a range the lifter narrowed.
    public static func setProgression(_ progression: Progression, slot: SlotID, in day: DayTemplate) -> DayTemplate {
        editing(day, slot: slot) { slots, index in
            guard slots[index].progression != progression else {
                return
            }
            slots[index].progression = progression
            if progression == .double {
                slots[index].repsHi = max(slots[index].repsHi, saturatingSum(slots[index].reps, 2))
            }
        }
    }

    /// "Drop set": one drop set, or none.
    public static func setDropSet(_ isOn: Bool, slot: SlotID, in day: DayTemplate) -> DayTemplate {
        editing(day, slot: slot) { slots, index in
            slots[index].dropSets = isOn ? 1 : 0
        }
    }

    /// Joins the slot to the one before it, or breaks it out. "Superset with next" on a slot joins the slot
    /// after it, so it passes that slot's id; when that slot leads a superset, the two groups become one.
    /// "Break out" breaks out the slot itself, and the members after it stay with it. The day's first slot
    /// has no slot before it and is never joined.
    public static func setSuperset(_ isOn: Bool, slot: SlotID, in day: DayTemplate) -> DayTemplate {
        editing(day, slot: slot) { slots, index in
            slots[index].isSupersetWithPrevious = isOn
        }
    }

    /// The day's slot ids in their superset groups, in order (rule 44). A slot on its own is a group of one.
    public static func groups(of day: DayTemplate) -> [[SlotID]] {
        SupersetRounds.groups(joiningPrevious: day.slots.map(\.isSupersetWithPrevious))
            .map { group in group.map { day.slots[$0].id } }
    }

    // MARK: - Shared

    /// `day` with `change` applied at the place of `slot` when the day holds it. `change` is given the slots
    /// in normal form, and what it leaves is put in normal form again.
    static func editing(_ day: DayTemplate, slot: SlotID, _ change: (inout [Slot], Int) -> Void) -> DayTemplate {
        var edited = normalized(day)
        if let index = edited.slots.firstIndex(where: { $0.id == slot }) {
            change(&edited.slots, index)
        }
        return normalized(edited)
    }

    /// `day` with its first slot joined to nothing.
    static func normalized(_ day: DayTemplate) -> DayTemplate {
        guard day.slots.first?.isSupersetWithPrevious == true else {
            return day
        }
        var normal = day
        normal.slots[0].isSupersetWithPrevious = false
        return normal
    }

    /// `value + delta`, held at the ends of `Int` where the sum would leave it. The model keeps a slot's
    /// numbers small, but they are `var` and can hold any `Int`, and no edit may trap on one.
    static func saturatingSum(_ value: Int, _ delta: Int) -> Int {
        let (sum, overflowed) = value.addingReportingOverflow(delta)
        guard overflowed else {
            return sum
        }
        return delta > 0 ? .max : .min
    }
}
