import Foundation
import LedgerDomain

/// The training days: the summary, one card per day and "+ Add training day". The days are shared by every
/// week, so a card counts its slots' own numbers, not a week's prescription (a deload week trains a set fewer).
nonisolated extension ProgramPresentation {
    /// How many exercises a card names before "+2".
    static let namedExercises = 4

    static func trainingDays(_ context: Context) -> ProgramBuilderModel.TrainingDays {
        let days = context.program.days
        let sets = days.reduce(0) { $0 + setCount(of: $1) }
        let summary = [
            ProgramCopy.days(days.count, locale: context.locale),
            ProgramCopy.setsAWeek(sets, locale: context.locale)
        ]
        return ProgramBuilderModel.TrainingDays(
            title: ProgramCopy.trainingDays,
            summary: summary.joined(separator: separator),
            helper: ProgramCopy.sharedByEveryWeek,
            cards: days.map { card(of: $0, context) },
            addDay: ProgramBuilderModel.Control(
                title: ProgramCopy.addTrainingDay,
                action: .addDay(name: ProgramCopy.newDay, weekIndex: context.selected)
            )
        )
    }

    /// A day's sets as the brief counts them: every slot's sets and its drop sets.
    static func setCount(of day: DayTemplate) -> Int {
        day.slots.reduce(0) { $0 + $1.sets + $1.dropSets }
    }

    static func card(of day: DayTemplate, _ context: Context) -> ProgramBuilderModel.DayCard {
        let meta = meta(of: day, locale: context.locale)
        let named = day.slots.prefix(namedExercises).map { slot in
            context.input.exercises[slot.exerciseID]?.shortName ?? ProgramCopy.unknownExercise
        }
        let others = day.slots.dropFirst(namedExercises).count
        return ProgramBuilderModel.DayCard(
            id: day.id,
            tag: day.tag,
            name: day.name,
            meta: meta,
            chips: named + (others > 0 ? [ProgramCopy.more(others, locale: context.locale)] : []),
            spokenLabel: day.name,
            spokenValue: meta,
            action: .route(.day(day.id, weekIndex: context.selected))
        )
    }

    /// "5 exercises · 18 sets · ~39 min", the minutes `TimeEstimate`'s for the slots as they are written; "No
    /// exercises yet" for a day with no slot.
    static func meta(of day: DayTemplate, locale: Locale) -> String {
        guard !day.slots.isEmpty else {
            return ProgramCopy.noExercisesYet
        }
        return [
            ProgramCopy.exercises(day.slots.count, locale: locale),
            ProgramCopy.sets(setCount(of: day), locale: locale),
            ProgramCopy.estimate(minutes: TimeEstimate.minutes(day: day, prescriptions: [:]), locale: locale)
        ]
        .joined(separator: separator)
    }
}
