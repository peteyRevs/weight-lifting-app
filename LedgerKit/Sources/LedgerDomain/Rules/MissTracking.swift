import Foundation

/// Which weeks a slot was missed in (rule 13 as amended by decision #5; decision #18).
public enum MissTracking {
    /// Decision #5: the week is missed if any `.working` set is not done or was done with
    /// `reps < targetReps`, or fewer `.working` sets were done than `targetSets`. `.drop`, `.added`
    /// and `.warmup` sets never count either way. Missed → `weekIndex` is inserted into
    /// `slot.misses`; not missed → it is removed. A deload week (`isDeload`) returns the slot
    /// unchanged. Idempotent.
    public static func update(slot: Slot, exercise: WorkoutExercise, weekIndex: Int, isDeload: Bool) -> Slot {
        guard !isDeload else {
            return slot
        }
        let working = exercise.sets.filter { $0.kind == .working }
        let isMissed = working.contains { !$0.isDone || $0.reps.value < exercise.targetReps }
            || working.count(where: \.isDone) < exercise.targetSets
        var updated = slot
        if isMissed {
            updated.misses.insert(weekIndex)
        } else {
            updated.misses.remove(weekIndex)
        }
        return updated
    }

    /// Decision #18: skipping a whole week counts as a miss for every slot, so every load holds.
    /// A skipped deload week is not a miss (decision #5: deload weeks never count as misses).
    /// Weeks outside the block leave the program unchanged.
    public static func recordSkippedWeek(_ weekIndex: Int, in program: Program) -> Program {
        guard let week = program.week(at: weekIndex), !week.isDeload else {
            return program
        }
        var updated = program
        for dayIndex in updated.days.indices {
            for slotIndex in updated.days[dayIndex].slots.indices {
                updated.days[dayIndex].slots[slotIndex].misses.insert(weekIndex)
            }
        }
        return updated
    }
}
