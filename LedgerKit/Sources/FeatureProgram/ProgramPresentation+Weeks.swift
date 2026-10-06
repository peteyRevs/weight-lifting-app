import Foundation
import LedgerDomain

/// The block (its length, "−" and "+", one chip per week) and the selected week (its title, the schedule strip
/// and the week's three actions).
nonisolated extension ProgramPresentation {
    static func block(_ context: Context) -> ProgramBuilderModel.Block {
        let weeks = context.program.weeks
        return ProgramBuilderModel.Block(
            title: ProgramCopy.block(weeks: weeks.count, locale: context.locale),
            spokenLabel: ProgramCopy.blockLength,
            spokenValue: ProgramCopy.weeks(weeks.count, locale: context.locale),
            removeWeek: removeWeek(context),
            // Criterion 4: the week "+" appends is the one selected, and it takes the place after the last.
            addWeek: .addWeek(selecting: weeks.count),
            chips: weeks.indices.map { chip(ofWeek: $0, context) }
        )
    }

    /// "−": `ProgramEditing` is asked whether the last week of the program on screen can go. The edit when it
    /// can; when it cannot, the notice that says why, and nothing to apply.
    static func removeWeek(_ context: Context) -> ProgramBuilderAction {
        let loggedWeeks = context.input.loggedWeeks
        do {
            _ = try ProgramEditing.removeLastWeek(context.program, loggedWeeks: loggedWeeks)
            return .edit(.removeLastWeek(loggedWeeks: loggedWeeks))
        } catch {
            return .notice(ProgramBuilderNotice(error))
        }
    }

    static func chip(ofWeek place: Int, _ context: Context) -> ProgramBuilderModel.WeekChip {
        let isDeload = context.program.weeks[place].isDeload
        let scheduled = Weekday.allCases.count { scheduledDay(in: context.program, week: place, on: $0) != nil }
        return ProgramBuilderModel.WeekChip(
            title: ProgramCopy.weekChip(place + 1, locale: context.locale),
            subtitle: isDeload ? ProgramCopy.deloadMark : ProgramCopy.scheduledDays(scheduled, locale: context.locale),
            isDeload: isDeload,
            isSelected: place == context.selected,
            spokenLabel: ProgramCopy.week(place + 1, locale: context.locale),
            spokenValue: isDeload ? ProgramCopy.deload : ProgramCopy.days(scheduled, locale: context.locale),
            action: .selectWeek(place)
        )
    }
}

// MARK: - The selected week

nonisolated extension ProgramPresentation {
    static func selectedWeek(_ context: Context) -> ProgramBuilderModel.SelectedWeek {
        let place = context.selected
        let weeks = context.program.weeks
        // A block always has the selected week; a program emptied of its weeks reads as a week of rest.
        let isDeload = weeks.indices.contains(place) && weeks[place].isDeload
        let title = [ProgramCopy.weekTitle(place + 1, locale: context.locale)] +
            (isDeload ? [ProgramCopy.deloadMark] : [])
        return ProgramBuilderModel.SelectedWeek(
            title: title.joined(separator: separator),
            hint: context.program.days.isEmpty ? nil : ProgramCopy.tapToAssign,
            cells: context.weekdays.map { cell(of: $0, context) },
            copyPrevious: copyPrevious(context),
            applyToLater: weeks.indices.contains(place + 1)
                ? ProgramBuilderModel.Control(
                    title: ProgramCopy.applyToLaterWeeks,
                    action: .edit(.applyToLaterWeeks(week: place))
                )
                : nil,
            deload: ProgramBuilderModel.Toggle(
                title: ProgramCopy.deload,
                isOn: isDeload,
                action: .edit(.setDeload(!isDeload, week: place))
            )
        )
    }

    /// "Copy week 2" on week 3: the week before the selected one has the selected week's place as its number.
    /// The first week has none before it: "First week", disabled.
    static func copyPrevious(_ context: Context) -> ProgramBuilderModel.Control {
        let place = context.selected
        guard place > 0 else {
            return ProgramBuilderModel.Control(title: ProgramCopy.firstWeek, action: nil)
        }
        return ProgramBuilderModel.Control(
            title: ProgramCopy.copyWeek(place, locale: context.locale),
            action: .edit(.copyPreviousWeek(week: place))
        )
    }

    static func cell(of weekday: Weekday, _ context: Context) -> ProgramBuilderModel.Cell {
        let day = scheduledDay(in: context.program, week: context.selected, on: weekday)
        let action = cycle(weekday, context)
        return ProgramBuilderModel.Cell(
            weekday: weekday,
            letter: context.letter(of: weekday),
            label: day?.tag ?? ProgramCopy.rest,
            isRest: day == nil,
            spokenLabel: context.name(of: weekday),
            spokenValue: day?.shortTitle ?? ProgramCopy.restSpoken,
            spokenHint: action.map { _ in ProgramCopy.assignHint },
            action: action
        )
    }

    /// A tap on a weekday, as the edit that names what the weekday becomes. The order of the cycle is
    /// `ProgramEditing`'s: it is asked for the value after the one the week holds. A day with no exercise is
    /// assigned all the same, and the action carries the notice that says so. A program with no training day
    /// has nothing to assign: no action.
    static func cycle(_ weekday: Weekday, _ context: Context) -> ProgramBuilderAction? {
        let program = context.program
        let place = context.selected
        guard !program.days.isEmpty else {
            return nil
        }
        let current = program.weeks.indices.contains(place) ? program.weeks[place].schedule[weekday] : nil
        let next = ProgramEditing.nextInCycle(after: current, in: program)
        let isEmpty = program.days.first { $0.id == next }.map(\.slots.isEmpty) ?? false
        return .edit(
            .setSchedule(week: place, weekday: weekday, day: next),
            notice: isEmpty ? .dayHasNoExercises : nil
        )
    }
}
