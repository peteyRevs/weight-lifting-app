import Foundation
import LedgerDesign
import LedgerDomain

nonisolated extension WorkoutPresentation {
    /// The receipt of `finished`, the workout this cover saved, with the personal records it set
    /// (`records`; none while they are not known). Every number is the Domain's: the summary
    /// (`WorkoutEngine.summary`) gives the time, the sets, the volume, the records and the rows, and
    /// nothing here counts. The date is the day the workout started (decision #26), in `calendar` and
    /// `locale`. Total: a workout with no exercise, an exercise with nothing logged, a start that is not
    /// finite and no volume all give a receipt.
    static func receipt(
        _ finished: WorkoutState,
        records: [PersonalRecord],
        locale: Locale,
        calendar: Calendar
    ) -> ReceiptScreenModel {
        let summary = WorkoutEngine.summary(finished, prs: records)
        let sets = WorkoutCopy.setsLogged(
            done: IntegerFormatStyle<Int>(locale: locale).format(summary.doneSets),
            of: summary.totalSets,
            locale: locale
        )
        let volume = summary.volume.formatted(in: finished.units)
        let tiles = [
            ReceiptLayout.Tile(
                label: WorkoutCopy.timeTile,
                value: ClockText.elapsed(summary.elapsed),
                spoken: spokenTimeTile(summary.elapsed, locale: locale),
                isAccented: true
            ),
            ReceiptLayout.Tile(label: WorkoutCopy.setsTile, value: setCount(summary, locale: locale), spoken: sets),
            ReceiptLayout.Tile(
                label: WorkoutCopy.movedTile(units: finished.units),
                value: volume,
                spoken: WorkoutCopy.moved(volume, units: finished.units, locale: locale)
            )
        ]
        return ReceiptScreenModel(
            header: ReceiptHeaderModel(
                date: ClockText.startDay(of: finished.startedAt, calendar: calendar, locale: locale),
                title: finished.name,
                done: WorkoutCopy.done
            ),
            page: ReceiptLayout.Model(
                tiles: tiles,
                records: summary.prs.isEmpty ? nil : WorkoutCopy.newRecords(summary.prs.count, locale: locale),
                logged: WorkoutCopy.logged,
                note: WorkoutCopy.prescribedOnTheRight,
                // One summary row for each exercise, in order (`WorkoutEngine.summary`), a superset's members
                // included as rows of their own (F10 S9, Q9: no letters, no block row), so the two zip one to
                // one; a summary of another shape would have `zip` drop rows silently.
                rows: zip(summary.rows, finished.exercises).map { row, exercise in
                    receiptRow(row, hasDoneSet: exercise.sets.contains(where: \.isDone), locale: locale)
                }
            ),
            // The same rows, in the same order: each opens its exercise's history (F12 S3, N18).
            rowActions: zip(summary.rows, finished.exercises).map { _, exercise in .openExercise(exercise.exerciseID) }
        )
    }

    /// "23/25": the sets done of all, in the lifter's digits.
    private static func setCount(_ summary: WorkoutSummary, locale: Locale) -> String {
        let digits = IntegerFormatStyle<Int>(locale: locale)
        return "\(digits.format(summary.doneSets))/\(digits.format(summary.totalSets))"
    }

    /// "TIME, 24 minutes, 22 seconds".
    private static func spokenTimeTile(_ elapsed: Duration, locale: Locale) -> String {
        [WorkoutCopy.timeTile, ClockText.spokenElapsed(elapsed, locale: locale)].joined(separator: ", ")
    }

    /// One exercise of the receipt: the Domain's name, target and chips, and the row as VoiceOver reads it.
    private static func receiptRow(_ row: ReceiptRow, hasDoneSet: Bool, locale: Locale) -> ReceiptLayout.Row {
        let spoken = [
            row.name,
            WorkoutCopy.spokenPrescribed(row.target, locale: locale),
            hasDoneSet
                ? WorkoutCopy.spokenLogged(row.actual.joined(separator: ", "), locale: locale)
                : WorkoutCopy.spokenNothingLogged
        ]
        return ReceiptLayout.Row(
            name: row.name,
            target: row.target,
            chips: row.actual,
            spoken: spoken.joined(separator: ", ")
        )
    }
}
