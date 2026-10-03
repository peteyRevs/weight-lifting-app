import Foundation
import GRDB
import LedgerDomain
import os

/// The replay's walk over its rows, in history's order. A workout's rows come together, one exercise after
/// another. When the next workout begins, each of its exercises' tallies is judged against the bests before the
/// workout (unless it is a deload, or the walk only gathers bests), then raises them.
///
/// A workout whose rows cannot be read (damage, or a case a later version added) is left out, as the lists leave
/// it out (S1's rule; orchestrator decision on R-Q1): logged, judged for nothing, counted in no best. Its stored
/// records stay as they are until a write repairs it, and the lifter's write goes through.
struct Walk {
    private(set) var bests: [ExerciseID: PersonalRecords.Tally<Int64>]
    private(set) var records: [PersonalRecordRecord] = []
    /// The `[workout.id, exercise_id]` values, as stored, of the lifts of workouts left out: a lift whose rows
    /// cannot be read, or every lift of a workout whose own columns cannot be.
    private(set) var skipped: Set<[DatabaseValue]> = []
    private let judges: Bool
    /// A workout the walk never reads: the one whose bests before it are gathered.
    private let excluded: DatabaseValue?
    private var open: Open?

    /// The workout being read: its key, its first row (the workout's columns), its exercises' tallies in order,
    /// and the first failure to read one of its rows.
    private struct Open {
        let key: DatabaseValue
        let row: Row
        var lifts: [Lift] = []
    }

    private struct Lift {
        let key: DatabaseValue
        let exercise: ExerciseID?
        var tally = PersonalRecords.Tally<Int64>()
        var failure: LedgerPersistenceError?
    }

    init(bests: [ExerciseID: PersonalRecords.Tally<Int64>], judges: Bool, excluding excluded: DatabaseValue?) {
        self.bests = bests
        self.judges = judges
        self.excluded = excluded
    }

    /// Walks the rows `sql` selects for `exercises` and `position` (the columns of `RecordReplay.walkSQL`).
    mutating func walk(
        _ database: Database,
        sql: String,
        _ exercises: [DatabaseValue],
        _ position: RecordReplay.Position
    ) throws {
        let rows = try Row.fetchCursor(
            database,
            sql: sql,
            arguments: StatementArguments(exercises) + [position.startedAt, position.id]
        )
        while let row = try rows.next() {
            add(row)
        }
        close()
    }

    private mutating func add(_ row: Row) {
        let key: DatabaseValue = row[4]
        if key == excluded {
            return
        }
        if open?.key != key {
            close()
            open = Open(key: key, row: row.copy())
        }
        let exerciseKey: DatabaseValue = row[0]
        if open?.lifts.last?.key != exerciseKey {
            let exercise: ExerciseID? = try? ColumnReader(row: row, table: "workout_exercise").identifier("exercise_id")
            var lift = Lift(key: exerciseKey, exercise: exercise)
            if exercise == nil {
                lift.failure = .malformedColumn("workout_exercise.exercise_id")
            }
            open?.lifts.append(lift)
        }
        guard let last = open?.lifts.indices.last, open?.lifts[last].failure == nil else {
            return
        }
        do throws(LedgerPersistenceError) {
            try open?.lifts[last].tally.add(row)
        } catch {
            open?.lifts[last].failure = error
        }
    }

    /// Judges the open workout, if any, and closes it.
    private mutating func close() {
        guard let workout = open else {
            return
        }
        open = nil
        let read = ColumnReader(row: workout.row, table: "workout")
        let isDeload: Bool
        let workoutID: WorkoutID
        let startedAt: Double
        do throws(LedgerPersistenceError) {
            isDeload = try read.flag("is_deload")
            workoutID = try read.identifier("workout_id")
            startedAt = try ColumnCodec.seconds(read.date("started_at"))
        } catch {
            for lift in workout.lifts {
                skip(workout.key, lift.key, error)
            }
            return
        }
        for lift in workout.lifts {
            guard let exercise = lift.exercise, lift.failure == nil else {
                skip(workout.key, lift.key, lift.failure ?? .malformedColumn("workout_exercise.exercise_id"))
                continue
            }
            if judges, !isDeload {
                let found = PersonalRecords.found(lift.tally, over: bests[exercise] ?? .init())
                records += found.map { PersonalRecordRecord($0, of: exercise, in: workoutID, at: startedAt) }
            }
            bests[exercise, default: .init()].add(lift.tally)
        }
    }

    private mutating func skip(_ workout: DatabaseValue, _ lift: DatabaseValue, _ error: LedgerPersistenceError) {
        skipped.insert([workout, lift])
        let id = String.fromDatabaseValue(workout) ?? "?"
        Logger.persistence.error("Records replay left out a lift of workout \(id, privacy: .public): \(error)")
    }
}

extension PersonalRecords.Tally<Int64> {
    /// Adds a row of the walk, or of the bests before it: an exercise's record sets at one rep count (column 1,
    /// `reps`), at their heaviest (column 2, `weight_e7g`) and best estimate (column 3, `e1rm_e7g`), in whole
    /// 10⁻⁷ g. Read by index, as strictly as `ColumnReader` reads: GRDB finds a column by name with a
    /// case-insensitive search, and for the worst case's 4,800 rows that cost 3 ms of 45 (Debug, host).
    mutating func add(_ row: Row) throws(LedgerPersistenceError) {
        func integer(_ index: Int, _ column: String) throws(LedgerPersistenceError) -> Int64 {
            guard case let .int64(value) = (row[index] as DatabaseValue).storage else {
                throw .malformedColumn("logged_set.\(column)")
            }
            return value
        }
        guard let reps = try Int(exactly: integer(1, "reps")).flatMap(Reps.init) else {
            throw .malformedColumn("logged_set.reps")
        }
        let estimate = (row[3] as DatabaseValue).isNull ? nil : try integer(3, "e1rm_e7g")
        try add(integer(2, "weight_e7g"), reps: reps, estimate: estimate)
    }
}
