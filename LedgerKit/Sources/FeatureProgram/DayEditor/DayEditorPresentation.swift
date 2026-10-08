import Foundation
import LedgerDomain

/// The Day editor's logic and its words: one pure function from a `DayEditorInput` to the `DayEditorModel` the
/// views draw.
///
/// It reads its input and nothing else, and holds no rule of a training day. The groups are `DayEditing`'s, a
/// week's numbers `ProgressionRules`', the minutes `TimeEstimate`'s; whether a move or a superset action can
/// do anything is asked of `DayEditing` by trying it on the day on screen; and every action it hands out is an
/// edit `DayEditing` or `ProgramEditing` applies. Every text comes from `ProgramCopy`; loads, RPEs and rests
/// are printed by the Domain.
///
/// The exercises' rows are in `+Rows`; the panel under the open one is `SlotEditorPresentation`'s.
nonisolated enum DayEditorPresentation {
    typealias Control = DayEditorModel.Control

    static let separator = ProgramPresentation.separator

    static func make(_ input: DayEditorInput) -> DayEditorModel {
        guard let context = Context(input) else {
            return .dayIsGone
        }
        return .editing(DayEditorModel.Content(
            id: context.day.id,
            header: header(context),
            groups: groups(context),
            addExercise: Control(title: ProgramCopy.addExerciseFromLibrary, action: .openLibrary),
            deleteDay: deleteDay(context)
        ))
    }

    static func header(_ context: Context) -> DayEditorModel.Header {
        let day = context.day
        let close = DayEditorAction.route(.closeDay)
        return DayEditorModel.Header(
            back: Control(title: ProgramCopy.backToProgram, action: close),
            position: ProgramCopy.dayPosition(
                context.position + 1,
                of: context.input.program.days.count,
                locale: context.locale
            ),
            done: Control(title: ProgramCopy.done, action: close),
            name: day.name,
            nameLabel: ProgramCopy.dayName,
            tag: day.tag,
            meta: meta(context)
        )
    }

    /// "Week 8 · 5 exercises · 13 sets · ~31 min": the sets and the minutes are those of the shown week's
    /// prescription, so a deload week counts a set fewer for each exercise (behaviour 13).
    static func meta(_ context: Context) -> String {
        let locale = context.locale
        let week = ProgramCopy.week(context.shownWeek + 1, locale: locale)
        let day = context.day
        guard !day.slots.isEmpty else {
            return [week, ProgramCopy.noExercisesYet].joined(separator: separator)
        }
        let prescriptions = context.shown.mapValues(\.prescription)
        let minutes = TimeEstimate.minutes(day: day, prescriptions: prescriptions)
        return [
            week,
            ProgramCopy.exercises(day.slots.count, locale: locale),
            ProgramCopy.sets(ProgramPresentation.setCount(of: day, prescriptions: prescriptions), locale: locale),
            ProgramCopy.estimate(minutes: minutes, locale: locale)
        ]
        .joined(separator: separator)
    }

    /// "Delete day" and its confirmation. The second line counts the weeks that train the day on any weekday,
    /// and is absent for a day no week trains.
    static func deleteDay(_ context: Context) -> DayEditorModel.DeleteDay {
        let day = context.day
        let weeks = context.input.program.weeks.count { $0.schedule.values.contains(day.id) }
        return DayEditorModel.DeleteDay(
            title: ProgramCopy.deleteDay,
            confirmation: DayEditorModel.Confirmation(
                title: ProgramCopy.deleteTitle(day.shortTitle, locale: context.locale),
                message: weeks > 0 ? ProgramCopy.scheduledInWeeks(weeks, locale: context.locale) : nil,
                confirm: Control(title: ProgramCopy.delete, action: .edit(.deleteDay(day.id), closesPanel: true)),
                cancel: ProgramCopy.cancel
            )
        )
    }
}

// MARK: - The input, resolved once

nonisolated extension DayEditorPresentation {
    /// What a slot is shown with when its exercise is stored: the exercise, and the slot's prescription in
    /// every week of the block and in the shown one.
    struct Shown {
        let exercise: Exercise
        /// One per week of the block, in order.
        let weeks: [Prescription]
        /// The shown week's.
        let prescription: Prescription
    }

    /// The input, with what several parts of the model need from it. Built once per `make`; there is none for
    /// a day the program does not hold.
    struct Context {
        let input: DayEditorInput
        let day: DayTemplate
        /// The day's place among the program's days, 0 for the first.
        let position: Int
        /// The shown week's place in the block: the input's when the block has it, else the nearest week.
        let shownWeek: Int
        /// The day's slot ids in their superset groups, as `DayEditing` reads them.
        let groups: [[SlotID]]
        /// By slot. A slot has no entry when its exercise is not stored, or in a program emptied of its weeks.
        let shown: [SlotID: Shown]

        init?(_ input: DayEditorInput) {
            let program = input.program
            guard let place = program.days.firstIndex(where: { $0.id == input.day }) else {
                return nil
            }
            let edited = program.days[place]
            let week = ProgramPresentation.nearestPlace(to: input.weekIndex, in: program.weeks.indices)
            let resolved = edited.slots.compactMap { slot -> (SlotID, Shown)? in
                guard let exercise = input.exercises[slot.exerciseID], program.weeks.indices.contains(week) else {
                    return nil
                }
                let weeks = ProgressionRules.prescriptions(
                    for: slot,
                    weeks: program.weeks,
                    exercise: exercise,
                    units: input.settings.units
                )
                return (slot.id, Shown(exercise: exercise, weeks: weeks, prescription: weeks[week]))
            }
            self.input = input
            day = edited
            position = place
            shownWeek = week
            groups = DayEditing.groups(of: edited)
            shown = Dictionary(resolved) { first, _ in first }
        }

        var units: Units {
            input.settings.units
        }

        var locale: Locale {
            input.locale
        }

        /// The action of one edit of this day's slots.
        func action(_ edit: SlotEdit, closesPanel: Bool = false) -> DayEditorAction {
            .edit(.slot(edit, day: day.id), closesPanel: closesPanel)
        }

        /// Whether `edit` would change the order of the day's exercises or who is in a superset with whom.
        /// `DayEditing` is asked, by applying the edit to the day on screen: a move at the day's edge and a
        /// "Break out" of an exercise that leads its group leave the groups as they are.
        func rearranges(_ edit: SlotEdit) -> Bool {
            DayEditing.groups(of: edit.applied(to: day)) != groups
        }
    }
}
