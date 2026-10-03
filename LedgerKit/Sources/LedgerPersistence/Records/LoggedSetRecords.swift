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
///
/// It holds the record as its columns, weights in whole 10⁻⁷ g, so that the replay of product decision #27, which
/// finds records in those units, writes and compares rows without decimal arithmetic.
struct PersonalRecordRecord: SyncedRecord {
    static let databaseTableName = "personal_record"

    let rowID: String
    let workoutID: WorkoutID
    private let exerciseID: ExerciseID
    private let kind: KindColumns
    private let previous: KindColumns?
    private let achievedAt: Double

    /// The record `found`, in whole 10⁻⁷ g, that `exerciseID` set in the workout `workoutID`, which started at
    /// `achievedAt` (seconds since the reference date, as `started_at` holds it).
    ///
    /// A `PersonalRecord` has no id, so the row's is derived from the workout, the exercise and the kind, which
    /// `PersonalRecords.found` finds at most once for an exercise of a workout. Detecting the same record again
    /// writes the same row, and a record whose value changes keeps its row.
    init(
        _ found: PersonalRecords.Found<Int64>,
        of exerciseID: ExerciseID,
        in workoutID: WorkoutID,
        at achievedAt: Double
    ) {
        let (columns, beaten) = switch found {
        case let .estimate(value, over):
            (
                KindColumns(name: Self.estimatedOneRepMax, e7g: value, reps: nil),
                KindColumns(name: Self.estimatedOneRepMax, e7g: over, reps: nil)
            )
        case let .weight(value, reps, over, overReps):
            (
                KindColumns(name: Self.weightAtReps, e7g: value, reps: reps.value),
                KindColumns(name: Self.weightAtReps, e7g: over, reps: overReps.value)
            )
        }
        self.init(workoutID: workoutID, exerciseID: exerciseID, kind: columns, previous: beaten, achievedAt: achievedAt)
    }

    private init(
        workoutID: WorkoutID,
        exerciseID: ExerciseID,
        kind: KindColumns,
        previous: KindColumns?,
        achievedAt: Double,
        rowID: String? = nil
    ) {
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.kind = kind
        self.previous = previous
        self.achievedAt = achievedAt
        let name = "personal_record \(ColumnCodec.text(exerciseID)) \(kind.name)"
        self.rowID = rowID ?? ColumnCodec.derivedID(named: name, in: workoutID.rawValue).uuidString
    }

    /// The row as stored, read strictly: a damaged column throws `malformedColumn`, an unknown kind too.
    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        try self.init(
            workoutID: read.identifier("workout_id"),
            exerciseID: read.identifier("exercise_id"),
            kind: Self.kind(read, "kind", "weight_e7g", "reps"),
            previous: read.isNull("previous_kind") ? nil : Self.kind(
                read,
                "previous_kind",
                "previous_weight_e7g",
                "previous_reps"
            ),
            achievedAt: ColumnCodec.seconds(read.date("achieved_at")),
            rowID: read.text("id")
        )
    }

    /// The record the row holds.
    var record: PersonalRecord {
        PersonalRecord(
            exerciseID: exerciseID,
            kind: kind.kind,
            previous: previous?.kind,
            achievedAt: Date(timeIntervalSinceReferenceDate: achievedAt),
            workoutID: workoutID
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = rowID
        container["workout_id"] = ColumnCodec.text(workoutID)
        container["exercise_id"] = ColumnCodec.text(exerciseID)
        container["kind"] = kind.name
        container["weight_e7g"] = kind.e7g
        container["reps"] = kind.reps
        container["previous_kind"] = previous?.name
        container["previous_weight_e7g"] = previous?.e7g
        container["previous_reps"] = previous?.reps
        container["achieved_at"] = achievedAt
    }

    private static let estimatedOneRepMax = "estimatedOneRepMax"
    private static let weightAtReps = "weightAtReps"

    /// A record kind as its three columns; `reps` is `NULL` for an estimated 1RM.
    private struct KindColumns {
        let name: String
        let e7g: Int64
        let reps: Int?

        /// The kind, for columns that `init(_:of:in:at:)` or `kind(_:_:_:_:)` made.
        var kind: PRKind {
            let count = reps.flatMap(Reps.init)
            return count.map { .weightAtReps(Weight(e7g: e7g), $0) } ?? .estimatedOneRepMax(Weight(e7g: e7g))
        }
    }

    /// The record kind three columns hold; a kind this app does not know throws `malformedColumn`, and so do reps
    /// below 1 in a weight at reps.
    private static func kind(
        _ read: ColumnReader,
        _ kind: String,
        _ weight: String,
        _ reps: String
    ) throws(LedgerPersistenceError) -> KindColumns {
        switch try read.text(kind) {
        case estimatedOneRepMax: try KindColumns(name: estimatedOneRepMax, e7g: read.integer(weight), reps: nil)
        case weightAtReps: try KindColumns(name: weightAtReps, e7g: read.integer(weight), reps: read.reps(reps).value)
        default: throw .malformedColumn("\(databaseTableName).\(kind)")
        }
    }
}
