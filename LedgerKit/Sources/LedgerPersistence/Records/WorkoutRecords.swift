import Foundation
import GRDB
import LedgerDomain

/// A `workout` row: a finished workout's own fields. Its exercises are rows of their own, so a workout read
/// from a row has none until `WorkoutRows` adds them.
///
/// The live-only fields of `WorkoutState` are not stored: a workout read back has no `cursor`, no `rest` and
/// no `programUpdates`, and `autoRest` at its default. `elapsed` is `ended_at − started_at`.
struct WorkoutRecord: SyncedRecord {
    static let databaseTableName = "workout"

    let workout: WorkoutState

    var rowID: String {
        ColumnCodec.text(workout.id)
    }

    init(_ workout: WorkoutState) {
        self.workout = workout
    }

    /// The totals (`volume_e7g_reps`, `done_sets`, `total_sets`, `pr_count`) are not read: `WorkoutState`
    /// computes them from its sets, and the columns exist for queries that do not load the sets.
    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        workout = try WorkoutState(
            id: read.identifier("id"),
            source: Self.source(read),
            name: read.text("name"),
            tag: read.text("tag"),
            isDeload: read.flag("is_deload"),
            exercises: [],
            cursor: nil,
            startedAt: read.date("started_at"),
            endedAt: read.optionalDate("ended_at"),
            phase: read.enumeration("phase"),
            originDevice: read.identifier("origin_device"),
            units: read.enumeration("units")
        )
    }

    /// The program week and day the workout was built from: all three columns, or none (an ad-hoc workout).
    /// Some but not all is damage, and throws rather than dropping the ones that are there.
    private static func source(_ read: ColumnReader) throws(LedgerPersistenceError) -> WorkoutSource? {
        let programID: ProgramID? = try read.optionalIdentifier("program_id")
        let weekIndex: Int? = try read.optionalInteger("week_index")
        let dayTemplateID: DayTemplateID? = try read.optionalIdentifier("day_template_id")
        guard let programID, let weekIndex, let dayTemplateID else {
            guard programID == nil, weekIndex == nil, dayTemplateID == nil else {
                throw .malformedColumn("workout.program_id")
            }
            return nil
        }
        return WorkoutSource(programID: programID, weekIndex: weekIndex, dayTemplateID: dayTemplateID)
    }

    /// The totals come from the sets being stored with it, so the columns cannot disagree with the rows.
    /// `pr_count` is not written here: a new row starts at 0, and `RecordReplay` keeps it equal to the
    /// workout's live records. A date that is not finite throws `nonFiniteDate`, and a volume beyond the column
    /// `inexactWeight`.
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = rowID
        container["program_id"] = workout.source.map { ColumnCodec.text($0.programID) }
        container["week_index"] = workout.source?.weekIndex
        container["day_template_id"] = workout.source.map { ColumnCodec.text($0.dayTemplateID) }
        container["name"] = workout.name
        container["tag"] = workout.tag
        container["is_deload"] = workout.isDeload
        container["started_at"] = try ColumnCodec.seconds(workout.startedAt)
        container["ended_at"] = try workout.endedAt.map(ColumnCodec.seconds)
        container["phase"] = workout.phase.rawValue
        container["units"] = workout.units.rawValue
        container["volume_e7g_reps"] = try workout.volume.e7gReps()
        container["done_sets"] = workout.doneSets
        container["total_sets"] = workout.totalSets
        container["origin_device"] = ColumnCodec.text(workout.originDevice)
    }
}

/// A `workout_exercise` row: one exercise of a finished workout, with the targets it was built with (rule 16),
/// and its place in `WorkoutState.exercises`. Its sets are rows of their own. `lastPerformance` is live-only
/// and not stored.
struct WorkoutExerciseRecord: SyncedRecord {
    static let databaseTableName = "workout_exercise"

    let exercise: WorkoutExercise
    let workoutID: WorkoutID
    let position: Int

    var rowID: String {
        ColumnCodec.text(exercise.id)
    }

    init(_ exercise: WorkoutExercise, workoutID: WorkoutID, position: Int) {
        self.exercise = exercise
        self.workoutID = workoutID
        self.position = position
    }

    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        guard let rest = try RestDuration(seconds: read.integer("rest_seconds")) else {
            throw LedgerPersistenceError.malformedColumn("workout_exercise.rest_seconds")
        }
        guard let rpe = try RPE(Decimal(read.integer("rpe_x2") as Int) / 2) else {
            throw LedgerPersistenceError.malformedColumn("workout_exercise.rpe_x2")
        }
        exercise = try WorkoutExercise(
            id: read.identifier("id"),
            slotID: read.optionalIdentifier("slot_id"),
            exerciseID: read.identifier("exercise_id"),
            originalExerciseID: read.identifier("original_exercise_id"),
            name: read.text("name"),
            equipment: read.enumeration("equipment"),
            step: Weight(e7g: read.integer("step_e7g")),
            rest: rest,
            rpe: rpe,
            isSupersetWithPrevious: read.flag("is_superset_with_previous"),
            targetSets: read.integer("target_sets"),
            targetReps: read.integer("target_reps"),
            targetLoad: Weight(e7g: read.integer("target_load_e7g")),
            sets: []
        )
        workoutID = try read.identifier("workout_id")
        position = try read.integer("position")
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = rowID
        container["workout_id"] = ColumnCodec.text(workoutID)
        container["position"] = position
        container["exercise_id"] = ColumnCodec.text(exercise.exerciseID)
        container["original_exercise_id"] = ColumnCodec.text(exercise.originalExerciseID)
        container["slot_id"] = exercise.slotID.map(ColumnCodec.text)
        container["name"] = exercise.name
        container["equipment"] = exercise.equipment.rawValue
        container["step_e7g"] = try exercise.step.e7g()
        container["rest_seconds"] = exercise.rest.seconds
        container["rpe_x2"] = NSDecimalNumber(decimal: exercise.rpe.value * 2).intValue // 10…20, whole
        container["is_superset_with_previous"] = exercise.isSupersetWithPrevious
        container["target_sets"] = exercise.targetSets
        container["target_reps"] = exercise.targetReps
        container["target_load_e7g"] = try exercise.targetLoad.e7g()
    }
}
