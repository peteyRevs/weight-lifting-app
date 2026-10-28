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
        var setTexts = SetTexts(input)
        return ExerciseHistoryModel(
            eyebrow: [LibraryCopy.equipment(exercise.equipment), LibraryCopy.muscle(exercise.primaryMuscle)]
                .joined(separator: LibraryPresentation.separator),
            title: exercise.name,
            // Criterion 10: only the lifter's own exercise is edited; a catalog one has no "Edit".
            edit: exercise.isCustom ? LibraryCopy.edit : nil,
            stats: stats(history, input),
            chart: chart(history.weeks, input),
            log: ExerciseHistoryModel.Log(
                title: LibraryCopy.sessionLog,
                entries: history.log.map { entry($0, input, sets: $0.sets.map { setTexts.text($0) }) },
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
            sessionsStat(history.sessions, locale: input.locale)
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
        // No session at all, or sessions with no set of 12 reps or fewer in the 8 weeks (F12-S2-R1-5).
        let empty = !shown.isEmpty ? nil : input.sessions.isEmpty ? LibraryCopy.noChart : LibraryCopy.noEstimate
        return ExerciseHistoryModel.Chart(
            title: LibraryCopy.chartTitle,
            delta: change.map {
                LibraryCopy.change(String(abs($0)), sign: $0, units: input.units, locale: input.locale)
            },
            bars: bars,
            empty: empty,
            spokenTitle: LibraryCopy.spokenChartTitle,
            spokenSummary: change.map { spokenChange($0, numbers, input) } ?? empty,
            weekAxis: LibraryCopy.weekAxis,
            valueAxis: LibraryCopy.unitAxis(input.units)
        )
    }

    private static func entry(
        _ entry: ExerciseHistory.Entry,
        _ input: ExerciseHistoryInput,
        sets: [String]
    ) -> ExerciseHistoryModel.Entry {
        let tag = switch entry.tag {
        case .record: LibraryCopy.record
        case let .heavier(step): heavier(step, input)
        case .same: LibraryCopy.noRecord
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

nonisolated extension ExerciseHistoryPresentation {
    /// The sessions tile: the count as the counted lookup writes it (F12-S2-R1-8), over that lookup's words, so the
    /// catalog picks the plural form (F12-S2-2) and VoiceOver reads the whole text, "1 session". The caption is
    /// "34 sessions" less its number, here and not in the copy file, which holds lookups only (standards §7);
    /// `LibraryCopyTests` holds every form of "%lld sessions" to the number, one space, then words (F12-S2-R1-4).
    /// Follow-up, Pete's call: a caption key whose forms hold no number, with an exception in the catalog audit.
    static func sessionsStat(_ count: Int, locale: Locale) -> ExerciseHistoryModel.Stat {
        let number = count.formatted(.number.locale(locale.forCountedText))
        let counted = LibraryCopy.sessions(count, locale: locale)
        let words = counted.range(of: number).map { counted.replacingCharacters(in: $0, with: "") } ?? counted
        return ExerciseHistoryModel.Stat(
            id: 2,
            value: number,
            unit: nil,
            caption: words.trimmingCharacters(in: .whitespaces),
            spoken: counted,
            isAccented: false
        )
    }

    /// "Up 28 pounds over 4 weeks": the change, over the weeks from the first with a value to the last, both
    /// counted, so from W5 it is 4 (F12-S2-R1-7).
    private static func spokenChange(_ change: Int, _ numbers: [Int?], _ input: ExerciseHistoryInput) -> String {
        let span = (numbers.lastIndex { $0 != nil } ?? 0) - (numbers.firstIndex { $0 != nil } ?? 0) + 1
        let (size, units) = (String(abs(change)), input.units)
        return LibraryCopy.spokenChange(size, sign: change, weeks: span, units: units, locale: input.locale)
    }

    /// The log's sets as it writes them, "180×5", each weight × reps once per model: a lifter repeats a few, and
    /// the lookups were most of a model's time at 2,000 sets (F12-S2-R1-2).
    struct SetTexts {
        private let input: ExerciseHistoryInput
        private var written: [Weight: [Int: String]] = [:]

        init(_ input: ExerciseHistoryInput) {
            self.input = input
        }

        mutating func text(_ set: LoggedSet) -> String {
            let reps = set.reps.value
            if let text = written[set.weight]?[reps] {
                return text
            }
            let text = LibraryCopy.set(set.weight.formatted(in: input.units), reps: reps, locale: input.locale)
            written[set.weight, default: [:]][reps] = text
            return text
        }
    }
}
