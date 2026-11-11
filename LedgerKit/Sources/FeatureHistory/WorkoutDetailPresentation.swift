import Foundation
import LedgerDesign
import LedgerDomain

/// What `WorkoutDetailPresentation.make(_:)` reads: the workout with its records as they are stored now, and the
/// lifter's units, calendar and locale. The same input always gives the same model.
nonisolated struct WorkoutDetailInput: Sendable {
    /// `WorkoutRepository.observeWorkout(id:)`'s value.
    var recorded: RecordedWorkout
    /// The lifter's units, which every weight is drawn in (F13 question 5, built to A).
    var units: Units
    /// Its time zone says which day the workout started on.
    var calendar: Calendar
    var locale: Locale
}

/// A past workout's detail as words (F13 S2, criterion 3 as C15 and C16 restate it): F10's receipt, built here from
/// the same Domain values and FeatureHistory's own copy of its keys (ruling A3), in the lifter's units rather than
/// the workout's (F13 question 5, built to A), under the day it started and its name. Every number is the Domain's:
/// `WorkoutEngine.summary` gives the time, the sets, the volume and the records, and `ReceiptRow(exercise:units:)`
/// each row; nothing here counts. For a workout in the lifter's units, the receipt equals F10's string for string
/// (N13, `ReceiptParityTests`).
nonisolated enum WorkoutDetailPresentation {
    static func make(_ input: WorkoutDetailInput) -> WorkoutDetailModel {
        let workout = input.recorded.workout
        let (units, locale) = (input.units, input.locale)
        let summary = WorkoutEngine.summary(workout, prs: input.recorded.records)
        return WorkoutDetailModel(
            date: ClockText.startDay(of: workout.startedAt, calendar: input.calendar, locale: locale),
            title: workout.name,
            receipt: ReceiptLayout.Model(
                tiles: tiles(summary, units: units, locale: locale),
                records: summary.prs.isEmpty ? nil : HistoryCopy.newRecords(summary.prs.count, locale: locale),
                logged: HistoryCopy.logged,
                note: HistoryCopy.prescribedOnTheRight,
                rows: workout.exercises.map { row($0, units: units, locale: locale) }
            ),
            rowRoutes: workout.exercises.map { .exercise($0.exerciseID) },
            edit: HistoryCopy.edit,
            delete: deletion
        )
    }

    /// N10: "This workout can't be read.", with Delete still offered.
    static var unreadable: WorkoutDetailModel.Unreadable {
        WorkoutDetailModel.Unreadable(
            title: HistoryCopy.unreadableTitle,
            body: HistoryCopy.unreadableBody,
            delete: deletion
        )
    }

    static var deletion: WorkoutDetailModel.Deletion {
        WorkoutDetailModel.Deletion(
            title: HistoryCopy.deleteWorkout,
            question: HistoryCopy.deleteQuestion,
            message: HistoryCopy.deleteMessage,
            confirm: HistoryCopy.delete,
            cancel: HistoryCopy.cancel
        )
    }

    /// TIME, SETS and LB MOVED (KG MOVED), each as drawn and as spoken.
    private static func tiles(_ summary: WorkoutSummary, units: Units, locale: Locale) -> [ReceiptLayout.Tile] {
        let digits = IntegerFormatStyle<Int>(locale: locale)
        let done = digits.format(summary.doneSets)
        let volume = summary.volume.formatted(in: units)
        let spoken = ClockText.spokenElapsed(summary.elapsed, locale: locale)
        return [
            ReceiptLayout.Tile(
                label: HistoryCopy.timeTile,
                value: ClockText.elapsed(summary.elapsed),
                spoken: [HistoryCopy.timeTile, spoken].joined(separator: ", "),
                isAccented: true
            ),
            ReceiptLayout.Tile(
                label: HistoryCopy.setsTile,
                value: "\(done)/\(digits.format(summary.totalSets))",
                spoken: HistoryCopy.setsLogged(done: done, of: summary.totalSets, locale: locale)
            ),
            ReceiptLayout.Tile(
                label: HistoryCopy.movedTile(units: units),
                value: volume,
                spoken: HistoryCopy.moved(volume, units: units, locale: locale)
            )
        ]
    }

    /// One exercise: the Domain's name, target and chips in the lifter's units, and the row as VoiceOver reads it,
    /// "—" spoken "Nothing logged" when no set of it was done.
    private static func row(_ exercise: WorkoutExercise, units: Units, locale: Locale) -> ReceiptLayout.Row {
        let row = ReceiptRow(exercise: exercise, units: units)
        let spoken = [
            row.name,
            HistoryCopy.spokenPrescribed(row.target, locale: locale),
            exercise.sets.contains(where: \.isDone)
                ? HistoryCopy.spokenLogged(row.actual.joined(separator: ", "), locale: locale)
                : HistoryCopy.spokenNothingLogged
        ]
        return ReceiptLayout.Row(
            name: row.name,
            target: row.target,
            chips: row.actual,
            spoken: spoken.joined(separator: ", ")
        )
    }
}
