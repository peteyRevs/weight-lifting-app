import Foundation
import LedgerDomain

/// The day's exercises: one group per superset or per exercise on its own, a header over a superset, and each
/// exercise's row with the shown week's numbers.
nonisolated extension DayEditorPresentation {
    /// Where a slot stands: the number of its group, and its place among the group's members.
    struct Place {
        /// The group's number in the day, 1 for the first.
        let number: Int
        /// "A", "B", …; empty for an exercise on its own.
        let letter: String
        /// Whether the slot is the last member of its group, the one the lifter rests after.
        let isLast: Bool
    }

    static func groups(_ context: Context) -> [DayEditorModel.Group] {
        // `DayEditing.groups` gives the day's slots in order, cut into runs: each run takes the next slots.
        var remaining = ArraySlice(context.day.slots)
        return context.groups.enumerated().map { offset, ids in
            let members = remaining.prefix(ids.count)
            remaining = remaining.dropFirst(ids.count)
            let isSuperset = members.count > 1
            let rows = members.enumerated().map { position, slot in
                let place = Place(
                    number: offset + 1,
                    letter: isSuperset ? SupersetRounds.letter(forMemberAt: position) : "",
                    isLast: position == members.count - 1
                )
                return row(of: slot, place, context)
            }
            return DayEditorModel.Group(
                header: isSuperset ? supersetHeader(memberCount: members.count, context) : nil,
                rows: rows
            )
        }
    }

    /// "SUPERSET" and "2 exercises back to back · rest after B": the letter is the last member's.
    static func supersetHeader(memberCount: Int, _ context: Context) -> DayEditorModel.SupersetHeader {
        let note = [
            ProgramCopy.backToBack(memberCount, locale: context.locale),
            ProgramCopy.restAfter(SupersetRounds.letter(forMemberAt: memberCount - 1), locale: context.locale)
        ]
        return DayEditorModel.SupersetHeader(
            title: ProgramCopy.supersetMark,
            note: note.joined(separator: separator),
            spokenLabel: ProgramCopy.supersetSpoken
        )
    }

    /// A row shows the shown week's prescription: its sets, reps, load and RPE. A slot whose exercise is not
    /// stored has no prescription: it is named by a dash and shows its own sets, reps and RPE, and no load.
    static func row(of slot: Slot, _ place: Place, _ context: Context) -> DayEditorModel.Row {
        let locale = context.locale
        let shown = context.shown[slot.id]
        let index = ProgramCopy.slotIndex(place.number, letter: place.letter, locale: locale)
        let name = shown?.exercise.name ?? ProgramCopy.unknownExercise
        let scheme = ProgramCopy.scheme(
            sets: shown?.prescription.sets ?? slot.sets,
            reps: shown?.prescription.reps ?? slot.reps,
            locale: locale
        )
        let load = shown.map {
            ProgramCopy.load($0.prescription.load.formatted(in: context.units), units: context.units, locale: locale)
        }
        let sub = subLine(of: slot, shown, place, context)
        let isOpen = context.input.openSlot == slot.id
        return DayEditorModel.Row(
            id: slot.id,
            index: index,
            name: name,
            sub: sub,
            scheme: scheme,
            load: load,
            hasDropSet: slot.dropSets > 0,
            isOpen: isOpen,
            spokenLabel: ProgramCopy.spokenRow(index: index, name: name, locale: locale),
            spokenValue: ([scheme] + (load.map { [$0] } ?? []) + [sub]).joined(separator: separator),
            action: .open(isOpen ? nil : slot.id),
            panel: isOpen ? SlotEditorPresentation.panel(of: slot, shown, context) : nil
        )
    }

    /// "Barbell · +5/wk · RPE 8 · 2:30 rest", with "drop" after the progression for a drop set, and "no rest"
    /// in place of the rest for a member of a superset that is not its last.
    static func subLine(of slot: Slot, _ shown: Shown?, _ place: Place, _ context: Context) -> String {
        let locale = context.locale
        var parts: [String] = []
        if let shown {
            parts.append(ProgramCopy.equipment(shown.exercise.equipment))
            parts.append(progressionMark(of: slot, step: shown.prescription.step, context))
        }
        if slot.dropSets > 0 {
            parts.append(ProgramCopy.dropMark)
        }
        parts.append(ProgramCopy.rpe((shown?.prescription.rpe ?? slot.rpe).label, locale: locale))
        parts.append(place.isLast ? ProgramCopy.restOf(slot.rest.label, locale: locale) : ProgramCopy.noRest)
        return parts.joined(separator: separator)
    }

    /// "+5/wk", "Reps 10–12" or "Fixed".
    static func progressionMark(of slot: Slot, step: Weight, _ context: Context) -> String {
        switch slot.progression {
        case .linear: ProgramCopy.stepAWeek(step.formatted(in: context.units), locale: context.locale)
        case .double: ProgramCopy.repRange(slot.reps, slot.repsHi, locale: context.locale)
        case .fixed: ProgramCopy.fixed
        }
    }
}
