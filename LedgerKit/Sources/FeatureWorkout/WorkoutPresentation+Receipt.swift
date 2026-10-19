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
                spoken: [WorkoutCopy.timeTile, spokenElapsed(summary.elapsed, locale: locale)].joined(separator: ", "),
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
                date: startDay(of: finished, locale: locale, calendar: calendar),
                title: finished.name,
                done: WorkoutCopy.done
            ),
            page: ReceiptLayout.Model(
                tiles: tiles,
                records: summary.prs.isEmpty ? nil : WorkoutCopy.newRecords(summary.prs.count, locale: locale),
                logged: WorkoutCopy.logged,
                note: WorkoutCopy.prescribedOnTheRight,
                // One summary row for each exercise, in order (`WorkoutEngine.summary`); a summary of another
                // shape (S9's superset rows) would have `zip` drop rows silently.
                rows: zip(summary.rows, finished.exercises).map { row, exercise in
                    receiptRow(row, hasDoneSet: exercise.sets.contains(where: \.isDone), locale: locale)
                }
            )
        )
    }

    /// "23/25": the sets done of all, in the lifter's digits.
    private static func setCount(_ summary: WorkoutSummary, locale: Locale) -> String {
        let digits = IntegerFormatStyle<Int>(locale: locale)
        return "\(digits.format(summary.doneSets))/\(digits.format(summary.totalSets))"
    }

    /// "24 minutes, 22 seconds", "1 hour, 1 minute, 5 seconds": the time as VoiceOver reads it, by the
    /// whole second, rounded down as the tile's "24:22" is, in `locale`. The format style traps on more
    /// seconds than an `Int64` holds, which a saturated time (2^63 s, `WorkoutState.elapsed(at:)`) is, so
    /// the time is held under that first.
    static func spokenElapsed(_ elapsed: Duration, locale: Locale) -> String {
        Duration.UnitsFormatStyle(
            allowedUnits: [.hours, .minutes, .seconds],
            width: .wide,
            zeroValueUnits: .hide,
            fractionalPart: .hide(rounded: .down)
        )
        .locale(locale)
        .format(min(elapsed, .seconds(Int64.max)))
    }

    /// "Wednesday, September 16": the day `workout` started, in `calendar`'s time zone; empty for a start
    /// that is not a date.
    private static func startDay(of workout: WorkoutState, locale: Locale, calendar: Calendar) -> String {
        guard workout.startedAt.timeIntervalSinceReferenceDate.isFinite else {
            return ""
        }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.weekday(.wide).month(.wide).day()
        return style.format(workout.startedAt)
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
