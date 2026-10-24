import Foundation
import LedgerDomain

/// An exercise's history, as words (F12 S2): `ExerciseHistory.make` folds the sessions, and this writes what the
/// screen draws from the fold. Estimates are shown as whole units (decision #4); the chart's change is the last
/// shown value less the first, so the numbers on screen add up (Pete's question 7, A); a set's weight and a tag's
/// step are the Domain's `formatted(in:)`. Every text comes from `LibraryCopy`.
nonisolated enum ExerciseHistoryPresentation {
    /// Between the sets of a session, as v2 spaces its chips.
    static let setSeparator = "   "
    /// The lowest week's bar, in hundredths of the highest's (v2 draws its lowest at about a quarter).
    static let lowestLevel = 25

    static func make(_ input: ExerciseHistoryInput) -> ExerciseHistoryModel {
        let history = ExerciseHistory.make(
            sessions: input.sessions,
            records: input.records,
            now: input.now,
            weekStart: input.weekStart,
            calendar: input.calendar
        )
        let exercise = input.exercise
        return ExerciseHistoryModel(
            eyebrow: [LibraryCopy.equipment(exercise.equipment), LibraryCopy.muscle(exercise.primaryMuscle)]
                .joined(separator: LibraryPresentation.separator),
            title: exercise.name,
            stats: stats(history, input),
            chart: chart(history.weeks, input),
            log: ExerciseHistoryModel.Log(
                title: LibraryCopy.sessionLog,
                entries: history.log.map { entry($0, input) },
                empty: history.log.isEmpty ? LibraryCopy.noSessions : nil
            )
        )
    }

    private static func stats(
        _ history: ExerciseHistory,
        _ input: ExerciseHistoryInput
    ) -> [ExerciseHistoryModel.Stat] {
        let best = history.bestSet
        return [
            ExerciseHistoryModel.Stat(
                id: 0,
                value: history.e1RM.map { String($0.wholeValue(in: input.units)) } ?? LibraryCopy.noRecord,
                unit: nil,
                caption: LibraryCopy.estimateCaption,
                spoken: nil,
                isAccented: history.e1RM != nil
            ),
            ExerciseHistoryModel.Stat(
                id: 1,
                value: best?.weight.formatted(in: input.units) ?? LibraryCopy.noRecord,
                unit: best.map { LibraryCopy.reps($0.reps.value, locale: input.locale) },
                caption: LibraryCopy.bestSetCaption,
                spoken: nil,
                isAccented: false
            ),
            ExerciseHistoryModel.Stat(
                id: 2,
                value: String(history.sessions),
                unit: nil,
                caption: LibraryCopy.sessionsCaption(history.sessions, locale: input.locale),
                spoken: LibraryCopy.sessions(history.sessions, locale: input.locale),
                isAccented: false
            )
        ]
    }

    private static func chart(
        _ weeks: [ExerciseHistory.Week],
        _ input: ExerciseHistoryInput
    ) -> ExerciseHistoryModel.Chart {
        let numbers = weeks.map { $0.e1RM?.wholeValue(in: input.units) }
        let shown = numbers.compactMap(\.self)
        let (lowest, highest) = (shown.min() ?? 0, shown.max() ?? 0)
        // The lowest week stands at `lowestLevel`, the highest at 100, and one alone at 100.
        let level = { (number: Int) in
            highest == lowest ? 100 : lowestLevel + (number - lowest) * (100 - lowestLevel) / (highest - lowest)
        }
        let bars = numbers.enumerated().map { place, number in
            ExerciseHistoryModel.Bar(
                id: place,
                week: LibraryCopy.week(place + 1, locale: input.locale),
                number: number,
                value: number.map { String($0) } ?? LibraryCopy.noRecord,
                level: number.map(level) ?? 0,
                isAccented: number != nil && place == numbers.count - 1
            )
        }
        let change = shown.count < 2 ? nil : (shown.last ?? 0) - (shown.first ?? 0)
        let empty = shown.isEmpty ? LibraryCopy.noChart : nil
        return ExerciseHistoryModel.Chart(
            title: LibraryCopy.chartTitle,
            delta: change.map {
                LibraryCopy.change(String(abs($0)), sign: $0, units: input.units, locale: input.locale)
            },
            bars: bars,
            empty: empty,
            spokenTitle: LibraryCopy.spokenChartTitle,
            spokenSummary: change.map {
                LibraryCopy.spokenChange(String(abs($0)), sign: $0, units: input.units, locale: input.locale)
            } ?? empty,
            weekAxis: LibraryCopy.weekAxis,
            valueAxis: LibraryCopy.unitAxis(input.units)
        )
    }

    private static func entry(
        _ entry: ExerciseHistory.Entry,
        _ input: ExerciseHistoryInput
    ) -> ExerciseHistoryModel.Entry {
        let tag = switch entry.tag {
        case .record: LibraryCopy.record
        case let .heavier(step): heavier(step, input)
        case .same: LibraryCopy.noRecord
        }
        let sets = entry.sets.map {
            LibraryCopy.set($0.weight.formatted(in: input.units), reps: $0.reps.value, locale: input.locale)
        }
        return ExerciseHistoryModel.Entry(
            id: entry.workoutID,
            date: date(entry.date, input),
            tag: tag,
            isRecord: entry.tag == .record,
            sets: sets.joined(separator: setSeparator),
            spokenValue: ([tag] + sets).joined(separator: LibraryPresentation.spokenSeparator),
            route: .openWorkout(entry.workoutID)
        )
    }

    /// "+5 lb", or "—" for a step that is no step as shown: one that rounds to zero in the lifter's units, as a
    /// change of units makes (100 kg, then 220.5 lb, is 0.04 lb up), reads as the two sets do (F12-S2-1).
    private static func heavier(_ step: Weight, _ input: ExerciseHistoryInput) -> String {
        let shown = step.formatted(in: input.units)
        guard shown != Weight.zero.formatted(in: input.units) else {
            return LibraryCopy.noRecord
        }
        return LibraryCopy.change(shown, sign: 1, units: input.units, locale: input.locale)
    }

    /// "Aug 12" in the current year, "Aug 12, 2025" in another (N14), in the injected calendar's time zone.
    private static func date(_ date: Date, _ input: ExerciseHistoryInput) -> String {
        let calendar = input.calendar
        var style = Date.FormatStyle(locale: input.locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.month(.abbreviated).day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: input.now) {
            style = style.year()
        }
        return style.format(date)
    }
}
