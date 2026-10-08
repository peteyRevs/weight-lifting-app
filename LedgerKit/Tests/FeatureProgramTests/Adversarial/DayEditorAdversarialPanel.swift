@testable import FeatureProgram
import Foundation
import LedgerDomain

/// F11 S6 adversarial round 1: the tester's own model of the open slot's panel (brief criteria 7 to 11,
/// "Copy (exact)"; product spec §3.4 a to f), as lines, and the feature's panel as the same lines.
nonisolated struct AdvDayPanel {
    let screen: AdvDayScreen
    let slot: Slot
    let exercise: Exercise

    var units: Units {
        screen.units
    }

    var start: Weight {
        slot.startLoad ?? exercise.startLoad(in: units)
    }

    var step: Weight {
        slot.step ?? exercise.equipment.defaultStep(in: units)
    }

    func edit(_ slotEdit: SlotEdit, closes: Bool = false) -> DayEditorAction {
        .edit(.slot(slotEdit, day: screen.day.id), closesPanel: closes)
    }

    // MARK: The week's line and the strip

    func weekLines() -> [String] {
        let weeks = screen.prescriptions(slot)
        let shown = weeks[screen.week]
        let mark = shown.isDeload ? " · DELOAD" : (shown.isHeld ? " · HELD" : "")
        let entries = weeks.enumerated().map { place, week in
            "W\(place + 1) \(week.load.formatted(in: units))\(week.isDeload ? " (deload)" : "")"
        }
        var lines = [
            "week.eyebrow=WEEK \(screen.week + 1)\(mark)",
            "week.flags=\(shown.isDeload)|\(shown.isHeld)",
            "week.line=\(shown.sets) × \(shown.reps) @ \(screen.load(shown.load)) · RPE \(shown.rpe.label)",
            "strip.text=\(entries.joined(separator: " · "))"
        ]
        for (place, week) in weeks.enumerated() {
            lines.append("strip.\(place + 1)=\(entries[place])|\(week.isDeload)|\(week.isHeld)|\(place == screen.week)")
        }
        return lines
    }

    // MARK: The steppers

    func fieldLines() -> [String] {
        let isDouble = slot.progression == .double
        var fields: [(SlotField.Kind, [String])] = [
            (.sets, ["SETS", "\(slot.sets)", "Sets"]),
            (.reps, [isDouble ? "REP FLOOR" : "REPS", "\(slot.reps)", isDouble ? "Rep floor" : "Reps"])
        ]
        if isDouble {
            fields.append((.repsHi, ["TOP OF RANGE", "\(slot.repsHi)", "Top of range"]))
        }
        fields += [
            (.startLoad, ["START LOAD", screen.load(start), "Start load"]),
            (.rpe, ["TARGET RPE", slot.rpe.label, "Target RPE"]),
            (.rest, ["REST", slot.rest.label, "Rest"])
        ]
        return fields.flatMap { kind, texts in
            let down = DayEditing.stepped(kind, .downward, of: slot, exercise: exercise, units: units)
            let upward = DayEditing.stepped(kind, .upward, of: slot, exercise: exercise, units: units)
            return [
                "field \(texts[0])=\(texts[1])|\(texts[2])",
                "field \(texts[0]) −=\(edit(.set(down, slot: slot.id)))",
                "field \(texts[0]) +=\(edit(.set(upward, slot: slot.id)))"
            ]
        }
    }

    // MARK: Progression and drop set

    var note: String {
        let unit = screen.unit
        let stepText = step.formatted(in: units)
        let from = start.formatted(in: units)
        return switch slot.progression {
        case .linear: "Adds \(stepText) \(unit) a week from \(from) \(unit). A week with a missed set holds the load."
        case .double: "Adds a rep each week up to \(slot.repsHi), then +\(stepText) \(unit) back at \(slot.reps)."
        case .fixed: "Stays at \(from) \(unit) for the whole block."
        }
    }

    func progressionLines() -> [String] {
        let titles: [(Progression, String)] = [(.linear, "Linear"), (.double, "Double"), (.fixed, "Fixed")]
        let chips = titles.map { progression, title in
            let isSelected = slot.progression == progression
            let action = isSelected ? "nil" : "\(edit(.setProgression(progression, slot: slot.id)))"
            return "chip \(title)=\(isSelected)|\(action)"
        }
        let isOn = slot.dropSets > 0
        let dropNote = isOn
            ? "One extra set at −15%, straight after the last working set."
            : "One extra set at −15% after the last working set."
        return ["progression=PROGRESSION", "note=\(note)"] + chips + [
            "drop=Drop set|\(dropNote)|\(isOn)|\(edit(.setDropSet(!isOn, slot: slot.id)))"
        ]
    }

    // MARK: Superset, move, remove

    /// Product spec §3.4 e and f. "Break out" on a slot joined to the one before it; "Superset with next" on
    /// the last of a group that is not the day's last slot, naming the next slot; both close the panel. A
    /// move is offered when `DayEditing.move` changes the day, and keeps the panel open.
    func actionLines() -> [String] {
        let slots = screen.day.slots
        let place = slots.firstIndex { $0.id == slot.id } ?? 0
        let isJoined = place > 0 && slot.isSupersetWithPrevious
        var superset: [String] = []
        if isJoined {
            superset.append("Break out|\(edit(.setSuperset(false, slot: slot.id), closes: true))")
        }
        if place + 1 < slots.count, !slots[place + 1].isSupersetWithPrevious {
            superset.append("Superset with next|\(edit(.setSuperset(true, slot: slots[place + 1].id), closes: true))")
        }
        let canMoveUp = DayEditing.move(screen.day, slot: slot.id, .upward) != screen.day
        let canMoveDown = DayEditing.move(screen.day, slot: slot.id, .downward) != screen.day
        return [
            "superset=\(superset.joined(separator: " + "))",
            "moveUp=\(canMoveUp ? "Move up|\(edit(.move(.upward, slot: slot.id)))" : "nil")",
            "moveDown=\(canMoveDown ? "Move down|\(edit(.move(.downward, slot: slot.id)))" : "nil")",
            "remove=Remove|\(String(describing: SlotEdit.remove(slot: slot.id)))"
        ]
    }

    func lines() -> [String] {
        weekLines() + fieldLines() + progressionLines() + actionLines()
    }
}

// MARK: - The feature's panel, as lines

nonisolated extension AdvDayPanel {
    static func lines(of panel: SlotEditorModel) -> [String] {
        var lines: [String] = []
        if let details = panel.details {
            let week = details.week
            lines += [
                "week.eyebrow=\(week.eyebrow)", "week.flags=\(week.isDeload)|\(week.isHeld)",
                "week.line=\(week.line)", "strip.text=\(details.strip.text)"
            ]
            for (place, entry) in details.strip.entries.enumerated() {
                lines.append("strip.\(place + 1)=\(entry.text)|\(entry.isDeload)|\(entry.isHeld)|\(entry.isShown)")
            }
            for field in details.fields {
                lines += [
                    "field \(field.label)=\(field.value)|\(field.spokenLabel)",
                    "field \(field.label) −=\(field.decrement)", "field \(field.label) +=\(field.increment)"
                ]
            }
            lines += ["progression=\(details.progression.title)", "note=\(details.progression.note)"]
            lines += details.progression.chips.map { chip in
                "chip \(chip.title)=\(chip.isSelected)|\(chip.action.map { "\($0)" } ?? "nil")"
            }
            let drop = details.dropSet
            lines.append("drop=\(drop.title)|\(drop.note)|\(drop.isOn)|\(drop.action)")
        }
        let removed = AdvDay.slotEdit(of: panel.remove.action).map { String(describing: $0) } ?? "no edit"
        return lines + [
            "superset=\(panel.supersetActions.map { "\($0.title)|\($0.action)" }.joined(separator: " + "))",
            "moveUp=\(panel.moveUp.map { "\($0.title)|\($0.action)" } ?? "nil")",
            "moveDown=\(panel.moveDown.map { "\($0.title)|\($0.action)" } ?? "nil")",
            "remove=\(panel.remove.title)|\(removed)"
        ]
    }
}
