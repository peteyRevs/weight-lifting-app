import Foundation

/// Builds the live workout for a program day (spec §7.3, rules 14–17).
public enum SessionBuilder {
    /// Spec §7.3: one `WorkoutExercise` per slot of `program`'s copy of `day` (found by `day.id`; a
    /// day the program does not hold throws `.dayNotInProgram`), in slot order. Each gets `p.sets` rows
    /// `{w: p.load, r: p.reps, kind: .working}` from `ProgressionRules.prescribe` (rule 14); a slot
    /// with a drop set appends `{w: (p.load × 0.85).rounded(toStep: p.step), r: p.reps, kind: .drop}`
    /// (rule 15). Rest, step, RPE, equipment, superset flag and targets are copied so later
    /// template edits never alter the session (rule 16). `lastPerformance` comes from `history`
    /// (`nil` on the first ever session). The cursor starts at (0, 0) (`nil` for an empty day),
    /// `phase` is `.live`, `startedAt` is `now`, and `autoRest` is snapshotted from `settings`.
    ///
    /// Child IDs are derived from `id` (`WorkoutExerciseID.derived`, `SetID.derived`), so the
    /// build is deterministic and needs no UUID source.
    public static func build( // swiftlint:disable:this function_parameter_count - F02 brief signature
        program: Program,
        weekIndex: Int,
        day: DayTemplate,
        exercises: [ExerciseID: Exercise],
        history: [ExerciseID: LastPerformance],
        settings: Settings,
        id: WorkoutID,
        device: DeviceID,
        now: Date
    ) throws(SessionBuilderError) -> WorkoutState {
        guard let week = program.week(at: weekIndex) else {
            throw .weekOutOfRange(weekIndex)
        }
        // Build from the program's own copy of the day, never a caller's possibly stale copy, so the
        // session's slots match what MissTracking and materialize(slotUpdates:) write back to.
        guard let programDay = program.days.first(where: { $0.id == day.id }) else {
            throw .dayNotInProgram(day.id)
        }
        var built: [WorkoutExercise] = []
        for (index, slot) in programDay.slots.enumerated() {
            guard let exercise = exercises[slot.exerciseID] else {
                throw .unknownExercise(slot.exerciseID)
            }
            let prescription = ProgressionRules.prescribe(
                week: week,
                weekIndex: weekIndex,
                slot: slot,
                exercise: exercise,
                units: settings.units
            )
            built.append(workoutExercise(
                id: .derived(from: id, index: index),
                slot: slot,
                exercise: exercise,
                prescription: prescription,
                lastPerformance: history[exercise.id]
            ))
        }
        return WorkoutState(
            id: id,
            source: WorkoutSource(programID: program.id, weekIndex: weekIndex, dayTemplateID: programDay.id),
            name: programDay.name,
            tag: programDay.tag,
            isDeload: week.isDeload,
            exercises: built,
            cursor: built.isEmpty ? nil : Cursor(exerciseIndex: 0, setIndex: 0),
            startedAt: now,
            phase: .live,
            originDevice: device,
            autoRest: settings.autoRest
        )
    }

    /// Rule 17: `live` when it is a live workout for the same program, week and day (resume it,
    /// keeping elapsed time and logged sets); otherwise `nil` (build a new one).
    public static func resumable(
        _ live: WorkoutState?,
        program: Program,
        weekIndex: Int,
        day: DayTemplate
    ) -> WorkoutState? {
        let source = WorkoutSource(programID: program.id, weekIndex: weekIndex, dayTemplateID: day.id)
        guard let live, live.phase == .live, live.source == source else {
            return nil
        }
        return live
    }

    private static func workoutExercise(
        id: WorkoutExerciseID,
        slot: Slot,
        exercise: Exercise,
        prescription: Prescription,
        lastPerformance: LastPerformance?
    ) -> WorkoutExercise {
        let reps = Reps(clamping: prescription.reps)
        var rows = (0 ..< prescription.sets).map { _ in (weight: prescription.load, kind: SetKind.working) }
        if slot.dropSets > 0 {
            let dropLoad = prescription.load.scaled(by: ProgressionRules.reductionFactor)
                .rounded(toStep: prescription.step)
            rows.append((weight: dropLoad, kind: .drop))
        }
        return WorkoutExercise(
            id: id,
            slotID: slot.id,
            exerciseID: exercise.id,
            originalExerciseID: exercise.id,
            name: exercise.name,
            equipment: exercise.equipment,
            step: prescription.step,
            rest: prescription.rest,
            rpe: prescription.rpe,
            isSupersetWithPrevious: slot.isSupersetWithPrevious,
            targetSets: prescription.sets,
            targetReps: prescription.reps,
            targetLoad: prescription.load,
            sets: rows.enumerated().map { index, row in
                LoggedSet(id: .derived(from: id, index: index), weight: row.weight, reps: reps, kind: row.kind)
            },
            lastPerformance: lastPerformance
        )
    }
}
