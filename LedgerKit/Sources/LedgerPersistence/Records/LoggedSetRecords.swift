import Foundation
import GRDB
import LedgerDomain

/// A `logged_set` row: one set row of a finished workout, and its place in `WorkoutExercise.sets`.
struct LoggedSetRecord: SyncedRecord {
    static let databaseTableName = "logged_set"

    let set: LoggedSet
    let workoutExerciseID: WorkoutExerciseID
    let position: Int

    var rowID: String {
        ColumnCodec.text(set.id)
    }

    init(_ set: LoggedSet, workoutExerciseID: WorkoutExerciseID, position: Int) {
        self.set = set
        self.workoutExerciseID = workoutExerciseID
        self.position = position
    }

    /// `e1rm_e7g` is not read: it is derived from the weight and reps on every write, for the stats queries.
    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        set = try LoggedSet(
            id: read.identifier("id"),
            weight: Weight(e7g: read.integer("weight_e7g")),
            reps: read.reps("reps"),
            kind: read.enumeration("kind"),
            doneAt: read.optionalDate("done_at")
        )
        workoutExerciseID = try read.identifier("workout_exercise_id")
        position = try read.integer("position")
    }

    /// `e1rm_e7g` is the Brzycki estimate (decision #4) of a done set of at most 12 reps, whatever its kind,
    /// and `NULL` otherwise. It is whole grams, so it always has a column value unless it lies beyond the
    /// column (`inexactWeight`).
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = rowID
        container["workout_exercise_id"] = ColumnCodec.text(workoutExerciseID)
        container["position"] = position
        container["weight_e7g"] = try set.weight.e7g()
        container["reps"] = set.reps.value
        container["kind"] = set.kind.rawValue
        container["done_at"] = try set.doneAt.map(ColumnCodec.seconds)
        container["e1rm_e7g"] = set.isDone ? try OneRepMax.brzycki(weight: set.weight, reps: set.reps)?.e7g() : nil
    }
}

/// A `personal_record` row: one record a workout set (decision #3). The table is derived and local-only, never
/// synced (`Migrations`).
struct PersonalRecordRecord: SyncedRecord {
    static let databaseTableName = "personal_record"

    let record: PersonalRecord
    /// The record's place among its workout's records, which gives the row its id.
    let position: Int

    /// A `PersonalRecord` has no id, so the row's is derived from its workout and its place: materialising
    /// the same records again writes the same rows.
    var rowID: String {
        ColumnCodec.derivedID(named: "personal_record \(position)", in: record.workoutID.rawValue).uuidString
    }

    init(_ record: PersonalRecord, position: Int) {
        self.record = record
        self.position = position
    }

    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        record = try PersonalRecord(
            exerciseID: read.identifier("exercise_id"),
            kind: Self.kind(read, "kind", "weight_e7g", "reps"),
            previous: read.isNull("previous_kind")
                ? nil
                : Self.kind(read, "previous_kind", "previous_weight_e7g", "previous_reps"),
            achievedAt: read.date("achieved_at"),
            workoutID: read.identifier("workout_id")
        )
        position = 0 // not stored: only the id depends on it, and a row read back is never written
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = rowID
        container["workout_id"] = ColumnCodec.text(record.workoutID)
        container["exercise_id"] = ColumnCodec.text(record.exerciseID)
        let kind = Self.columns(record.kind)
        container["kind"] = kind.name
        container["weight_e7g"] = try kind.weight.e7g()
        container["reps"] = kind.reps
        let previous = record.previous.map(Self.columns)
        container["previous_kind"] = previous?.name
        container["previous_weight_e7g"] = try previous?.weight.e7g()
        container["previous_reps"] = previous?.reps
        container["achieved_at"] = try ColumnCodec.seconds(record.achievedAt)
    }

    private static let estimatedOneRepMax = "estimatedOneRepMax"
    private static let weightAtReps = "weightAtReps"

    /// A record kind as its three columns; `reps` is `NULL` for an estimated 1RM.
    private struct KindColumns {
        let name: String
        let weight: Weight
        let reps: Int?
    }

    private static func columns(_ kind: PRKind) -> KindColumns {
        switch kind {
        case let .estimatedOneRepMax(weight): KindColumns(name: estimatedOneRepMax, weight: weight, reps: nil)
        case let .weightAtReps(weight, reps): KindColumns(name: weightAtReps, weight: weight, reps: reps.value)
        }
    }

    /// The record kind three columns hold; a kind this app does not know throws `malformedColumn`.
    private static func kind(
        _ read: ColumnReader,
        _ kind: String,
        _ weight: String,
        _ reps: String
    ) throws(LedgerPersistenceError) -> PRKind {
        switch try read.text(kind) {
        case estimatedOneRepMax: try .estimatedOneRepMax(Weight(e7g: read.integer(weight)))
        case weightAtReps: try .weightAtReps(Weight(e7g: read.integer(weight)), read.reps(reps))
        default: throw .malformedColumn("\(databaseTableName).\(kind)")
        }
    }
}
