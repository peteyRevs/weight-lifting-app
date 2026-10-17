@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport

/// F11 S10, gate G2, round 1: a Day editor's model rebuilt with its strings changed, one by one or all at
/// once, and with or without the two facts that may pick the accent. A view takes any model, so a test can
/// hand it words the Domain would need a long detour to reach (a load of five digits, a superset's note of
/// three lines) and can ask of each string of the model whether it is drawn, spoken, or neither.
///
/// Every string has a path, as `DayViewsText.paths(of:)` lists them: "header.meta", "row.2.name",
/// "panel.field.0.value". The rows are numbered through the day, the superset headers by their group.
nonisolated struct DayViewsText {
    /// What a string becomes: its path and what the model holds.
    var change: (_ path: String, _ text: String) -> String = { _, text in text }
    /// False: no week line says that it is a deload week or a held one, so nothing may be orange.
    var keepsItsOrange = true

    func content(_ model: DayEditorModel.Content) -> DayEditorModel.Content {
        var place = 0
        let groups = model.groups.enumerated().map { number, group in
            let header = group.header.map {
                DayEditorModel.SupersetHeader(
                    title: change("group.\(number).title", $0.title),
                    note: change("group.\(number).note", $0.note),
                    spokenLabel: change("group.\(number).spokenLabel", $0.spokenLabel)
                )
            }
            let rows = group.rows.map { row in
                defer { place += 1 }
                return self.row(row, at: place)
            }
            return DayEditorModel.Group(header: header, rows: rows)
        }
        return DayEditorModel.Content(
            id: model.id,
            header: header(model.header),
            groups: groups,
            addExercise: control("add", model.addExercise),
            deleteDay: deleteDay(model.deleteDay)
        )
    }

    private func control(_ path: String, _ control: DayEditorModel.Control) -> DayEditorModel.Control {
        DayEditorModel.Control(title: change(path, control.title), action: control.action)
    }

    private func header(_ header: DayEditorModel.Header) -> DayEditorModel.Header {
        DayEditorModel.Header(
            back: control("header.back", header.back),
            position: change("header.position", header.position),
            done: control("header.done", header.done),
            name: change("header.name", header.name),
            nameLabel: change("header.nameLabel", header.nameLabel),
            tag: change("header.tag", header.tag),
            meta: change("header.meta", header.meta)
        )
    }

    private func deleteDay(_ model: DayEditorModel.DeleteDay) -> DayEditorModel.DeleteDay {
        let asked = model.confirmation
        return DayEditorModel.DeleteDay(
            title: change("delete", model.title),
            confirmation: DayEditorModel.Confirmation(
                title: change("confirm.title", asked.title),
                message: asked.message.map { change("confirm.message", $0) },
                confirm: control("confirm.confirm", asked.confirm),
                cancel: change("confirm.cancel", asked.cancel)
            )
        )
    }

    private func row(_ row: DayEditorModel.Row, at place: Int) -> DayEditorModel.Row {
        let path = "row.\(place)"
        return DayEditorModel.Row(
            id: row.id,
            index: change("\(path).index", row.index),
            name: change("\(path).name", row.name),
            sub: change("\(path).sub", row.sub),
            scheme: change("\(path).scheme", row.scheme),
            load: row.load.map { change("\(path).load", $0) },
            hasDropSet: row.hasDropSet,
            isOpen: row.isOpen,
            spokenLabel: change("\(path).spokenLabel", row.spokenLabel),
            spokenValue: change("\(path).spokenValue", row.spokenValue),
            action: row.action,
            panel: row.panel.map(panel)
        )
    }

    private func panel(_ panel: SlotEditorModel) -> SlotEditorModel {
        SlotEditorModel(
            details: panel.details.map(details),
            supersetActions: panel.supersetActions.enumerated().map { control("panel.superset.\($0)", $1) },
            moveUp: panel.moveUp.map { control("panel.moveUp", $0) },
            moveDown: panel.moveDown.map { control("panel.moveDown", $0) },
            remove: control("panel.remove", panel.remove)
        )
    }

    private func details(_ details: SlotEditorModel.Details) -> SlotEditorModel.Details {
        let week = details.week
        let fields = details.fields.enumerated().map { place, field in
            SlotEditorModel.Field(
                kind: field.kind,
                label: change("panel.field.\(place).label", field.label),
                value: change("panel.field.\(place).value", field.value),
                spokenLabel: change("panel.field.\(place).spokenLabel", field.spokenLabel),
                decrement: field.decrement,
                increment: field.increment
            )
        }
        return SlotEditorModel.Details(
            week: SlotEditorModel.WeekLine(
                eyebrow: change("panel.week.eyebrow", week.eyebrow),
                isDeload: keepsItsOrange && week.isDeload,
                isHeld: keepsItsOrange && week.isHeld,
                line: change("panel.week.line", week.line)
            ),
            fields: fields,
            progression: progression(details.progression),
            dropSet: SlotEditorModel.DropSet(
                title: change("panel.drop.title", details.dropSet.title),
                note: change("panel.drop.note", details.dropSet.note),
                isOn: details.dropSet.isOn,
                action: details.dropSet.action
            ),
            strip: strip(details.strip)
        )
    }

    private func progression(_ picker: SlotEditorModel.ProgressionPicker) -> SlotEditorModel.ProgressionPicker {
        SlotEditorModel.ProgressionPicker(
            title: change("panel.progression.title", picker.title),
            chips: picker.chips.enumerated().map { place, chip in
                SlotEditorModel.Chip(
                    progression: chip.progression,
                    title: change("panel.chip.\(place)", chip.title),
                    isSelected: chip.isSelected,
                    action: chip.action
                )
            },
            note: change("panel.progression.note", picker.note)
        )
    }

    private func strip(_ strip: SlotEditorModel.WeekStrip) -> SlotEditorModel.WeekStrip {
        SlotEditorModel.WeekStrip(
            text: change("panel.strip.text", strip.text),
            entries: strip.entries.enumerated().map { place, entry in
                SlotEditorModel.Entry(
                    text: change("panel.entry.\(place)", entry.text),
                    isDeload: entry.isDeload,
                    isHeld: entry.isHeld,
                    isShown: entry.isShown
                )
            }
        )
    }
}

nonisolated extension DayViewsText {
    /// The path of every string of `model`, in the model's order.
    static func paths(of model: DayEditorModel.Content) -> [String] {
        var paths: [String] = []
        _ = DayViewsText(change: { path, text in
            paths.append(path)
            return text
        }).content(model)
        return paths
    }

    /// `model` with the one string at `path` changed to `text`.
    static func changing(_ path: String, to text: String, in model: DayEditorModel.Content) -> DayEditorModel.Content {
        DayViewsText(change: { $0 == path ? text : $1 }).content(model)
    }

    /// `model` with every string empty.
    static func blank(_ model: DayEditorModel.Content) -> DayEditorModel.Content {
        DayViewsText(change: { _, _ in "" }).content(model)
    }

    /// `model` with no week line marked a deload week or a held one.
    static func withoutItsOrange(_ model: DayEditorModel.Content) -> DayEditorModel.Content {
        DayViewsText(keepsItsOrange: false).content(model)
    }

    /// Whether the notes say the string at `path` is drawn, and whether they say VoiceOver reads it (the
    /// S6 tables of the model, "Inputs for the views (S10, S11)", and the plan's tree). The day's name is
    /// drawn in a field the hosted reader cannot read; the placeholder shows only under an empty name; the
    /// confirmation is an alert, on no page.
    static func place(of path: String) -> (isDrawn: Bool, isSpoken: Bool) {
        let leaf = path.split(separator: ".").last.map(String.init) ?? path
        if path.hasPrefix("confirm.") || path == "header.nameLabel" {
            return (false, false)
        }
        // Fix round 1, ruling 17: a stepper draws its spoken label, and its `label` is drawn nowhere.
        if path.hasPrefix("panel.field."), ["label", "spokenLabel"].contains(leaf) {
            return (leaf == "spokenLabel", leaf == "spokenLabel")
        }
        if ["spokenLabel", "spokenValue"].contains(leaf) || path == "panel.strip.text" {
            return (false, true)
        }
        let isRowsText = path.hasPrefix("row.")
        let isDrawnOnly = isRowsText || path
            .hasPrefix("panel.entry.") || (path.hasPrefix("panel.field.") && leaf == "label")
            || (path.hasPrefix("group.") && leaf == "title") || ["header.name", "header.tag"].contains(path)
        return (true, !isDrawnOnly)
    }
}
