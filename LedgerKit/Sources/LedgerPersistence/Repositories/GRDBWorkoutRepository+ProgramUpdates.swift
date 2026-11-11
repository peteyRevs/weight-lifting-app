import Foundation
import GRDB
import LedgerDomain
import os

/// The program changes a workout's save writes (decision #13; compare-and-set since F10 S8).
extension GRDBWorkoutRepository {
    /// Sets the exercise of each slot `workout.programUpdates` names (decision #13), in slot-id order, and
    /// nothing else of the slot: its numbers and its misses stay.
    ///
    /// An entry is applied only to a live slot, under a live day, of the workout's own live program, so a
    /// workout of one program never rewrites another's (the takeover class of F05 review B1); only while that
    /// slot still holds the exercise the workout was built from (`WorkoutState.originalExercise(ofSlot:)`,
    /// compare-and-set, ADR-004 amendment §3), so a slot changed since keeps the lifter's later choice (an
    /// entry no exercise of the workout came from, which no swap writes, has nothing to compare and is not
    /// held to it); and only when its exercise has a row, as the slot's foreign key and a program save require
    /// (`ProgramRows.holdsExercise(_:in:)`, the one rule for both). Any other entry is logged and skipped: the
    /// program was edited or deleted during the workout or since, and the workout is still stored. A slot that
    /// already holds the exercise is left alone, so a second materialisation runs no statement that writes.
    static func writeProgramUpdates(of workout: WorkoutState, in database: Database, at timestamp: String) throws {
        guard !workout.programUpdates.isEmpty else {
            return
        }
        guard let program = workout.source.map({ ColumnCodec.text($0.programID) }) else {
            Logger.persistence.notice("Program updates of an ad-hoc workout skipped: it has no program")
            return
        }
        let updates = workout.programUpdates
            .map { slot, exercise in
                ProgramUpdate(
                    slot: ColumnCodec.text(slot),
                    exercise: ColumnCodec.text(exercise),
                    original: workout.originalExercise(ofSlot: slot).map { ColumnCodec.text($0) }
                )
            }
            .sorted { $0.slot < $1.slot }
        for update in updates {
            guard try update.applies(toProgram: program, in: database) else {
                continue
            }
            try database.execute(
                sql: "UPDATE slot SET exercise_id = ?, updated_at = ? WHERE id = ?",
                arguments: [update.exercise, timestamp, update.slot]
            )
        }
    }
}

/// One entry of `programUpdates`, as column text.
private struct ProgramUpdate {
    let slot: String
    let exercise: String
    /// What the slot held when the workout was built; `nil` when no exercise of the workout came from it.
    let original: String?

    /// Whether the slot takes `exercise` (`GRDBWorkoutRepository.writeProgramUpdates`); a skip is logged,
    /// except for a slot that already holds the exercise.
    func applies(toProgram program: String, in database: Database) throws -> Bool {
        // Whether the workout's own slot holds the exercise already, and whether it still holds the one the
        // workout was built from; no row when the slot is not its own.
        let ownSlot = """
        SELECT slot.exercise_id IS ? AS isHeld, slot.exercise_id IS ? AS isOriginal FROM slot
        JOIN day_template ON day_template.id = slot.day_template_id
        JOIN program ON program.id = day_template.program_id
        WHERE slot.id = ? AND program.id = ?
            AND slot.deleted_at IS NULL AND day_template.deleted_at IS NULL AND program.deleted_at IS NULL
        """
        let arguments: StatementArguments = [exercise, original, slot, program]
        guard let held = try Row.fetchOne(database, sql: ownSlot, arguments: arguments) else {
            Logger.persistence.notice(
                "Program update of slot \(slot, privacy: .public) skipped: the workout's program has no such slot"
            )
            return false
        }
        guard !(held["isHeld"] as Bool) else {
            return false
        }
        // Compare-and-set; an entry with no original (no swap writes one) has nothing to compare.
        guard original == nil || held["isOriginal"] as Bool else {
            Logger.persistence.notice(
                "Program update of slot \(slot, privacy: .public) skipped: not the exercise the workout began with"
            )
            return false
        }
        guard try ProgramRows.holdsExercise(exercise, in: database) else {
            Logger.persistence.notice(
                "Program update of slot \(slot, privacy: .public) skipped: its exercise is not stored"
            )
            return false
        }
        return true
    }
}
