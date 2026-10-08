@testable import FeatureProgram
import Foundation
import LedgerDomain

/// F11 S6 adversarial round 1: the tester's own model of the Day editor, written from the brief's "Copy
/// (exact)", product spec §3.4 and the slice's criteria 2 to 6. It reads the input and the Domain
/// (`DayEditing`, `ProgressionRules`, `TimeEstimate`, `Weight.formatted`, the labels of `RPE` and
/// `RestDuration`) and never the feature. It writes the screen as lines "key=value", and so does `lines(of:)`
/// for the feature's model, so that two screens are compared line by line and a difference is short.
///
/// It models a day whose every slot has a stored exercise and no miss; the suites that leave that ground say
/// what they expect themselves. One line follows what the feature was seen to do and not the brief, which is
/// silent: a row's sub line prints the shown week's RPE (two lower in a deload week), as its scheme and load
/// are the week's (finding F11-S6-1).
nonisolated struct AdvDayScreen {
    let input: DayEditorInput
    let day: DayTemplate
    let week: Int

    init?(_ input: DayEditorInput) {
        guard let held = input.program.days.first(where: { $0.id == input.day }), !input.program.weeks.isEmpty else {
            return nil
        }
        self.input = input
        day = held
        week = Swift.min(Swift.max(input.weekIndex, 0), input.program.weeks.count - 1)
    }

    var units: Units {
        input.settings.units
    }

    var unit: String {
        units == .lb ? "lb" : "kg"
    }

    static let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
    static let equipment: [Equipment: String] = [
        .barbell: "Barbell", .dumbbell: "Dumbbell", .cable: "Cable", .machine: "Machine",
        .bodyweight: "Bodyweight", .kettlebell: "Kettlebell", .band: "Band"
    ]

    func exercise(_ slot: Slot) -> Exercise? {
        input.exercises[slot.exerciseID]
    }

    func prescriptions(_ slot: Slot) -> [Prescription] {
        guard let exercise = exercise(slot) else {
            return []
        }
        return ProgressionRules.prescriptions(for: slot, weeks: input.program.weeks, exercise: exercise, units: units)
    }

    func load(_ weight: Weight) -> String {
        "\(weight.formatted(in: units)) \(unit)"
    }

    static func counted(_ count: Int, _ one: String, _ other: String) -> String {
        "\(count) \(count == 1 ? one : other)"
    }

    // MARK: The header

    var meta: String {
        var shown: [SlotID: Prescription] = [:]
        for slot in day.slots where exercise(slot) != nil {
            shown[slot.id] = prescriptions(slot)[week]
        }
        let sets = day.slots.reduce(0) { $0 + (shown[$1.id]?.sets ?? $1.sets) + $1.dropSets }
        let minutes = TimeEstimate.minutes(day: day, prescriptions: shown)
        return [
            "Week \(week + 1)", Self.counted(day.slots.count, "exercise", "exercises"),
            Self.counted(sets, "set", "sets"), "~\(minutes) min"
        ].joined(separator: " · ")
    }

    var scheduledWeeks: Int {
        input.program.weeks.count { $0.schedule.values.contains(day.id) }
    }

    var header: [String] {
        let place = (input.program.days.firstIndex { $0.id == day.id } ?? 0) + 1
        let message = switch scheduledWeeks {
        case 0: "nil"
        case 1: "It's scheduled in 1 week. Those days become rest."
        default: "It's scheduled in \(scheduledWeeks) weeks. Those days become rest."
        }
        return [
            "id=\(day.id)",
            "back=Program|\(DayEditorAction.route(.closeDay))",
            "position=DAY \(place) OF \(input.program.days.count)",
            "done=Done|\(DayEditorAction.route(.closeDay))",
            "name=\(day.name)",
            "tag=\(day.tag)",
            "meta=\(day.slots.isEmpty ? "(empty)" : meta)",
            "add=+ Add exercise from library|\(DayEditorAction.openLibrary)",
            "delete=Delete day",
            "confirm.title=Delete \(day.shortTitle)?",
            "confirm.message=\(message)",
            "confirm.confirm=Delete|\(String(describing: DayEditorEdit.deleteDay(day.id)))",
            "confirm.cancel=Cancel"
        ]
    }

    // MARK: The rows

    func progressionMark(_ slot: Slot, _ shown: Prescription) -> String {
        switch slot.progression {
        case .linear: "+\(shown.step.formatted(in: units))/wk"
        case .double: "Reps \(slot.reps)–\(slot.repsHi)"
        case .fixed: "Fixed"
        }
    }

    func rows() -> [String] {
        var lines: [String] = []
        let slots = Dictionary(uniqueKeysWithValues: day.slots.map { ($0.id, $0) })
        for (place, ids) in DayEditing.groups(of: day).enumerated() {
            let last = ids.count - 1
            let title = ids.count > 1
                ? "SUPERSET|\(ids.count) exercises back to back · rest after \(Self.letters[last])|Superset"
                : "nil"
            lines.append("group\(place + 1).header=\(title)")
            for (position, id) in ids.enumerated() {
                guard let slot = slots[id], let exercise = exercise(slot) else {
                    continue
                }
                let shown = prescriptions(slot)[week]
                let index = ids.count > 1 ? "\(place + 1)\(Self.letters[position])" : "\(place + 1)"
                // Criterion 11: after the last member, the rest the workout takes: the longest of the group's.
                let longest = ids.compactMap { slots[$0]?.rest }.max() ?? slot.rest
                let rest = position < last ? "no rest" : "\(longest.label) rest"
                let sub = [
                    Self.equipment[exercise.equipment] ?? "?", progressionMark(slot, shown),
                    slot.dropSets > 0 ? "drop" : nil, "RPE \(shown.rpe.label)", rest
                ].compactMap(\.self).joined(separator: " · ")
                let scheme = "\(shown.sets)×\(shown.reps)"
                let isOpen = input.openSlot == id
                lines += [
                    "row \(index).id=\(id)", "row \(index).name=\(exercise.name)", "row \(index).sub=\(sub)",
                    "row \(index).scheme=\(scheme)", "row \(index).load=\(load(shown.load))",
                    "row \(index).drop=\(slot.dropSets > 0)", "row \(index).open=\(isOpen)",
                    "row \(index).spoken=\(index), \(exercise.name)|\(scheme) · \(load(shown.load)) · \(sub)",
                    "row \(index).action=\(DayEditorAction.open(isOpen ? nil : id))"
                ]
                if isOpen {
                    lines += AdvDayPanel(screen: self, slot: slot, exercise: exercise).lines()
                }
            }
        }
        return lines
    }

    /// The whole screen as the tester expects it.
    func lines() -> [String] {
        header + rows()
    }
}

// MARK: - The feature's model, as lines

nonisolated extension AdvDayScreen {
    static func lines(of model: DayEditorModel) -> [String] {
        guard case let .editing(content) = model else {
            return ["gone"]
        }
        let header = content.header
        let confirmation = content.deleteDay.confirmation
        let confirmed = AdvDay.edit(of: confirmation.confirm.action).map { String(describing: $0) } ?? "no edit"
        var lines = [
            "id=\(content.id)",
            "back=\(header.back.title)|\(header.back.action)",
            "position=\(header.position)",
            "done=\(header.done.title)|\(header.done.action)",
            "name=\(header.name)",
            "tag=\(header.tag)",
            "meta=\(content.groups.isEmpty ? "(empty)" : header.meta)",
            "add=\(content.addExercise.title)|\(content.addExercise.action)",
            "delete=\(content.deleteDay.title)",
            "confirm.title=\(confirmation.title)",
            "confirm.message=\(confirmation.message ?? "nil")",
            "confirm.confirm=\(confirmation.confirm.title)|\(confirmed)",
            "confirm.cancel=\(confirmation.cancel)"
        ]
        for (place, group) in content.groups.enumerated() {
            let title = group.header.map { "\($0.title)|\($0.note)|\($0.spokenLabel)" } ?? "nil"
            lines.append("group\(place + 1).header=\(title)")
            for row in group.rows {
                let index = row.index
                lines += [
                    "row \(index).id=\(row.id)", "row \(index).name=\(row.name)", "row \(index).sub=\(row.sub)",
                    "row \(index).scheme=\(row.scheme)", "row \(index).load=\(row.load ?? "nil")",
                    "row \(index).drop=\(row.hasDropSet)", "row \(index).open=\(row.isOpen)",
                    "row \(index).spoken=\(row.spokenLabel)|\(row.spokenValue)",
                    "row \(index).action=\(row.action)"
                ]
                if let panel = row.panel {
                    lines += AdvDayPanel.lines(of: panel)
                }
            }
        }
        return lines
    }

    /// The lines that differ between the tester's screen and the feature's model of `input`; empty when they
    /// agree. At most six, each as "expected ≠ actual".
    static func differences(_ input: DayEditorInput) -> [String] {
        let actual = lines(of: DayEditorPresentation.make(input))
        guard let expected = AdvDayScreen(input)?.lines() else {
            return actual == ["gone"] ? [] : ["expected gone ≠ \(actual.first ?? "")"]
        }
        var found: [String] = []
        for place in 0 ..< Swift.max(expected.count, actual.count) {
            let want = place < expected.count ? expected[place] : "(no line)"
            let have = place < actual.count ? actual[place] : "(no line)"
            if want != have {
                found.append("\(want) ≠ \(have)")
            }
        }
        return Array(found.prefix(6))
    }
}
