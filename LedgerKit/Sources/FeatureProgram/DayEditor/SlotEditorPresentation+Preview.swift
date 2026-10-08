import Foundation
import LedgerDomain

/// What every week of the block prescribes for the open exercise: the shown week's line, and the strip of
/// each week's load. The numbers are `ProgressionRules`'; a deload week and a week held after a miss are marked.
nonisolated extension SlotEditorPresentation {
    /// "WEEK 8 · DELOAD" over "4 × 5 @ 240 lb · RPE 6".
    static func weekLine(_ prescription: Prescription, _ context: Context) -> SlotEditorModel.WeekLine {
        let locale = context.locale
        let isHeld = isMarkedHeld(prescription)
        var eyebrow = [ProgramCopy.weekTitle(context.shownWeek + 1, locale: locale)]
        if prescription.isDeload {
            eyebrow.append(ProgramCopy.deloadMark)
        } else if isHeld {
            eyebrow.append(ProgramCopy.heldMark)
        }
        let target = ProgramCopy.target(
            sets: prescription.sets,
            reps: prescription.reps,
            load: prescription.load.formatted(in: context.units),
            units: context.units,
            locale: locale
        )
        return SlotEditorModel.WeekLine(
            eyebrow: eyebrow.joined(separator: DayEditorPresentation.separator),
            isDeload: prescription.isDeload,
            isHeld: isHeld,
            line: [target, ProgramCopy.rpe(prescription.rpe.label, locale: locale)]
                .joined(separator: DayEditorPresentation.separator)
        )
    }

    /// "W1 50 · W2 50 · W3 50 · W4 52.5 · … · W8 47.5 (deload)": one entry per week of the block, each with
    /// that week's load in the lifter's unit.
    static func strip(_ weeks: [Prescription], _ context: Context) -> SlotEditorModel.WeekStrip {
        let entries = weeks.enumerated().map { place, prescription in
            let load = prescription.load.formatted(in: context.units)
            let isHeld = isMarkedHeld(prescription)
            let text = if prescription.isDeload {
                ProgramCopy.stripDeloadWeek(place + 1, load: load, locale: context.locale)
            } else if isHeld {
                ProgramCopy.stripHeldWeek(place + 1, load: load, locale: context.locale)
            } else {
                ProgramCopy.stripWeek(place + 1, load: load, locale: context.locale)
            }
            return SlotEditorModel.Entry(
                text: text,
                isDeload: prescription.isDeload,
                isHeld: isHeld,
                isShown: place == context.shownWeek
            )
        }
        return SlotEditorModel.WeekStrip(
            text: entries.map(\.text).joined(separator: DayEditorPresentation.separator),
            entries: entries
        )
    }

    /// A week carries one mark: a deload week reads as a deload even when the week before it was missed.
    static func isMarkedHeld(_ prescription: Prescription) -> Bool {
        prescription.isHeld && !prescription.isDeload
    }
}
