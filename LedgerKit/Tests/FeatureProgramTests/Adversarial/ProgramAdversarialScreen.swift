@testable import FeatureProgram
import Foundation
import LedgerDomain

/// F11 S5 adversarial rounds 1 and 2: the tester's own model of the Program builder in English, from the
/// brief's "Copy (exact)" and the slice's criteria 1 to 16, as a flat list of named lines; `lines(of:)` gives
/// the feature's model in the same form, so a difference is reported as a few short strings.
nonisolated enum AdvScreen {
    enum Value: Equatable, CustomStringConvertible {
        case text(String)
        case flag(Bool)
        case action(ProgramBuilderAction?)

        var description: String {
            switch self {
            case let .text(text): "\"\(text.prefix(60))\""
            case let .flag(flag): "\(flag)"
            case let .action(action): action.map { String(describing: $0).prefix(90).description } ?? "disabled"
            }
        }
    }

    typealias Line = (path: String, value: Value)

    static let weekdayNames: [Weekday: String] = [
        .monday: "Monday", .tuesday: "Tuesday", .wednesday: "Wednesday", .thursday: "Thursday",
        .friday: "Friday", .saturday: "Saturday", .sunday: "Sunday"
    ]

    static let helper = "Shared by every week. The schedule above decides which day you train, and when."

    static func counted(_ count: Int, _ one: String, _ other: String) -> String {
        "\(count) \(count == 1 ? one : other)"
    }

    static func order(from start: Weekday) -> [Weekday] {
        (0 ..< 7).compactMap { Weekday(rawValue: (start.rawValue - 1 + $0) % 7 + 1) }
    }

    /// The place read for a selection: the nearest week of the block.
    static func place(_ input: ProgramBuilderInput) -> Int {
        min(max(input.selectedWeek, 0), input.program.weeks.count - 1)
    }

    static func sets(of day: DayTemplate) -> Int {
        day.slots.reduce(0) { $0 + $1.sets + $1.dropSets }
    }

    static func meta(of day: DayTemplate) -> String {
        guard !day.slots.isEmpty else {
            return "No exercises yet"
        }
        return [
            counted(day.slots.count, "exercise", "exercises"),
            counted(sets(of: day), "set", "sets"),
            "~\(TimeEstimate.minutes(day: day, prescriptions: [:])) min"
        ].joined(separator: " · ")
    }

    /// What a tap on `weekday` assigns: the day after the one there, the first from rest, rest after the last.
    static func next(_ program: Program, place: Int, weekday: Weekday) -> DayTemplate? {
        let now = program.weeks[place].schedule[weekday].flatMap { id in program.days.firstIndex { $0.id == id } }
        let following = now.map { $0 + 1 } ?? 0
        return program.days.indices.contains(following) ? program.days[following] : nil
    }
}

nonisolated extension AdvScreen {
    static func expected(_ input: ProgramBuilderInput) -> [Line] {
        header(input) + block(input) + week(input) + days(input) + [("notice", .text(notice(input.notice)))]
    }

    static func notice(_ notice: ProgramBuilderNotice?) -> String {
        switch notice {
        case nil: "none"
        case .minimumTwoWeeks: "A block needs at least 2 weeks."
        case let .weekHasLoggedSessions(number): "Week \(number) has logged sessions and can't be removed."
        case .dayHasNoExercises: "Add at least one exercise before scheduling this day."
        }
    }

    static func header(_ input: ProgramBuilderInput) -> [Line] {
        [
            ("header.eyebrow", .text("MY PROGRAM")),
            ("header.name", .text(input.program.name)),
            ("header.namePlaceholder", .text("Program name"))
        ]
    }

    static func block(_ input: ProgramBuilderInput) -> [Line] {
        let weeks = input.program.weeks
        let last = weeks.count - 1
        let remove: ProgramBuilderAction = if weeks.count <= 2 {
            .notice(.minimumTwoWeeks)
        } else if input.loggedWeeks.contains(last) {
            .notice(.weekHasLoggedSessions(weekNumber: weeks.count))
        } else {
            .edit(.removeLastWeek(loggedWeeks: input.loggedWeeks), notice: nil)
        }
        var lines: [Line] = [
            ("block.title", .text("BLOCK · \(counted(weeks.count, "WEEK", "WEEKS"))")),
            ("block.spokenValue", .text(counted(weeks.count, "week", "weeks"))),
            ("block.removeWeek", .action(remove)),
            ("block.addWeek", .action(.addWeek(selecting: weeks.count))),
            ("block.chips.count", .text("\(weeks.count)"))
        ]
        for (index, week) in weeks.enumerated() {
            let held = Set(input.program.days.map(\.id))
            let trained = Weekday.allCases.count { week.schedule[$0].map(held.contains) == true }
            let path = "chip\(index + 1)"
            lines += [
                ("\(path).title", .text("W\(index + 1)")),
                ("\(path).subtitle", .text(week.isDeload ? "DELOAD" : counted(trained, "DAY", "DAYS"))),
                ("\(path).isDeload", .flag(week.isDeload)),
                ("\(path).isSelected", .flag(index == place(input))),
                ("\(path).spokenLabel", .text("Week \(index + 1)")),
                ("\(path).spokenValue", .text(week.isDeload ? "Deload" : counted(trained, "day", "days"))),
                ("\(path).action", .action(.selectWeek(index)))
            ]
        }
        return lines
    }

    static func week(_ input: ProgramBuilderInput) -> [Line] {
        let program = input.program
        let place = place(input)
        let week = program.weeks[place]
        let isLast = place == program.weeks.count - 1
        var lines: [Line] = [
            ("week.title", .text("WEEK \(place + 1)" + (week.isDeload ? " · DELOAD" : ""))),
            ("week.hint", .text(program.days.isEmpty ? "absent" : "Tap to assign")),
            ("week.copyPrevious.title", .text(place == 0 ? "First week" : "Copy week \(place)")),
            ("week.copyPrevious.action", .action(place == 0 ? nil : .edit(.copyPreviousWeek(week: place)))),
            ("week.applyToLater.title", .text(isLast ? "absent" : "Apply to later weeks")),
            ("week.applyToLater.action", .action(isLast ? nil : .edit(.applyToLaterWeeks(week: place)))),
            ("week.deload.title", .text("Deload")),
            ("week.deload.isOn", .flag(week.isDeload)),
            ("week.deload.action", .action(.edit(.setDeload(!week.isDeload, week: place)))),
            ("week.cells.count", .text("7"))
        ]
        for (index, weekday) in order(from: input.settings.weekStart).enumerated() {
            let day = week.schedule[weekday].flatMap { id in program.days.first { $0.id == id } }
            let assigned = next(program, place: place, weekday: weekday)
            let notice: ProgramBuilderNotice? = assigned.map(\.slots.isEmpty) == true ? .dayHasNoExercises : nil
            let path = "cell\(index + 1)"
            lines += [
                ("\(path).weekday", .text("\(weekday)")),
                ("\(path).label", .text(day?.tag ?? "REST")),
                ("\(path).isRest", .flag(day == nil)),
                ("\(path).spokenLabel", .text(weekdayNames[weekday] ?? "")),
                ("\(path).spokenValue", .text(day?.shortTitle ?? "Rest")),
                ("\(path).spokenHint", .text(program.days.isEmpty ? "absent" : "Double-tap to assign")),
                ("\(path).action", .action(program.days.isEmpty ? nil : .edit(
                    .setSchedule(week: place, weekday: weekday, day: assigned?.id), notice: notice
                )))
            ]
        }
        return lines
    }

    static func days(_ input: ProgramBuilderInput) -> [Line] {
        let days = input.program.days
        let total = days.reduce(0) { $0 + sets(of: $1) }
        let summary = counted(days.count, "day", "days") + " · " + counted(total, "set", "sets") + " a week"
        var lines: [Line] = [
            ("days.title", .text("TRAINING DAYS")),
            ("days.summary", .text(summary)),
            ("days.helper", .text(helper)),
            ("days.addDay.title", .text("+ Add training day")),
            ("days.addDay.action", .action(.addDay(name: "New day", weekIndex: place(input)))),
            ("days.cards.count", .text("\(days.count)"))
        ]
        for (index, day) in days.enumerated() {
            let path = "card\(index + 1)"
            lines += [
                ("\(path).id", .text("\(day.id)")),
                ("\(path).tag", .text(day.tag)),
                ("\(path).name", .text(day.name)),
                ("\(path).meta", .text(meta(of: day))),
                ("\(path).chips.count", .text("\(min(day.slots.count, 4) + (day.slots.count > 4 ? 1 : 0))")),
                ("\(path).more", .text(day.slots.count > 4 ? "+\(day.slots.count - 4)" : "none")),
                ("\(path).spokenLabel", .text(day.name)),
                ("\(path).spokenValue", .text(meta(of: day))),
                ("\(path).action", .action(.route(.day(day.id, weekIndex: place(input)))))
            ]
            for (slot, held) in day.slots.prefix(4).enumerated() {
                if let exercise = input.exercises[held.exerciseID] {
                    lines.append(("\(path).chip\(slot + 1)", .text(exercise.shortName)))
                }
            }
        }
        return lines
    }
}

// MARK: - The feature's model, in the same form

nonisolated extension AdvScreen {
    static func lines(of model: ProgramBuilderModel, exercises: [ExerciseID: Exercise], program: Program) -> [Line] {
        var lines: [Line] = [
            ("header.eyebrow", .text(model.header.eyebrow)),
            ("header.name", .text(model.header.name)),
            ("header.namePlaceholder", .text(model.header.namePlaceholder)),
            ("block.title", .text(model.block.title)),
            ("block.spokenValue", .text(model.block.spokenValue)),
            ("block.removeWeek", .action(model.block.removeWeek)),
            ("block.addWeek", .action(model.block.addWeek)),
            ("block.chips.count", .text("\(model.block.chips.count)"))
        ]
        for (index, chip) in model.block.chips.enumerated() {
            let path = "chip\(index + 1)"
            lines += [
                ("\(path).title", .text(chip.title)),
                ("\(path).subtitle", .text(chip.subtitle)),
                ("\(path).isDeload", .flag(chip.isDeload)),
                ("\(path).isSelected", .flag(chip.isSelected)),
                ("\(path).spokenLabel", .text(chip.spokenLabel)),
                ("\(path).spokenValue", .text(chip.spokenValue)),
                ("\(path).action", .action(chip.action))
            ]
        }
        return lines + weekLines(model.week) + dayLines(model.days, exercises: exercises, program: program)
    }

    static func weekLines(_ week: ProgramBuilderModel.SelectedWeek) -> [Line] {
        var lines: [Line] = [
            ("week.title", .text(week.title)),
            ("week.hint", .text(week.hint ?? "absent")),
            ("week.copyPrevious.title", .text(week.copyPrevious.title)),
            ("week.copyPrevious.action", .action(week.copyPrevious.action)),
            ("week.applyToLater.title", .text(week.applyToLater?.title ?? "absent")),
            ("week.applyToLater.action", .action(week.applyToLater?.action)),
            ("week.deload.title", .text(week.deload.title)),
            ("week.deload.isOn", .flag(week.deload.isOn)),
            ("week.deload.action", .action(week.deload.action)),
            ("week.cells.count", .text("\(week.cells.count)"))
        ]
        for (index, cell) in week.cells.enumerated() {
            let path = "cell\(index + 1)"
            lines += [
                ("\(path).weekday", .text("\(cell.weekday)")),
                ("\(path).label", .text(cell.label)),
                ("\(path).isRest", .flag(cell.isRest)),
                ("\(path).spokenLabel", .text(cell.spokenLabel)),
                ("\(path).spokenValue", .text(cell.spokenValue)),
                ("\(path).spokenHint", .text(cell.spokenHint ?? "absent")),
                ("\(path).action", .action(cell.action))
            ]
        }
        return lines
    }

    /// A chip is compared only where its exercise is stored; one that is not has its own test.
    static func dayLines(
        _ days: ProgramBuilderModel.TrainingDays,
        exercises: [ExerciseID: Exercise],
        program: Program
    ) -> [Line] {
        var lines: [Line] = [
            ("days.title", .text(days.title)),
            ("days.summary", .text(days.summary)),
            ("days.helper", .text(days.helper)),
            ("days.addDay.title", .text(days.addDay.title)),
            ("days.addDay.action", .action(days.addDay.action)),
            ("days.cards.count", .text("\(days.cards.count)"))
        ]
        for (index, card) in days.cards.enumerated() {
            let path = "card\(index + 1)"
            let slots = program.days.indices.contains(index) ? program.days[index].slots : []
            lines += [
                ("\(path).id", .text("\(card.id)")),
                ("\(path).tag", .text(card.tag)),
                ("\(path).name", .text(card.name)),
                ("\(path).meta", .text(card.meta)),
                ("\(path).chips.count", .text("\(card.chips.count)")),
                ("\(path).more", .text(slots.count > 4 ? card.chips.last ?? "missing" : "none")),
                ("\(path).spokenLabel", .text(card.spokenLabel)),
                ("\(path).spokenValue", .text(card.spokenValue)),
                ("\(path).action", .action(card.action))
            ]
            for (slot, held) in slots.prefix(4).enumerated() where exercises[held.exerciseID] != nil {
                lines.append(("\(path).chip\(slot + 1)", .text(slot < card.chips.count ? card.chips[slot] : "missing")))
            }
        }
        return lines
    }

    /// The first lines where the feature's screen of `input` is not the tester's screen of `wanted` (of `input`).
    static func differences(_ input: ProgramBuilderInput, wanted: ProgramBuilderInput? = nil) -> [String] {
        let model = ProgramPresentation.make(input)
        let got = lines(of: model, exercises: input.exercises, program: input.program)
            + [("notice", .text(model.notice ?? "none"))]
        let want = expected(wanted ?? input)
        var found = got.count == want.count ? [] : ["lines: got \(got.count) expected \(want.count)"]
        for (mine, theirs) in zip(want, got) where mine.path != theirs.path || mine.value != theirs.value {
            found.append("\(mine.path): got \(theirs.value) expected \(mine.value)")
        }
        return Array(found.prefix(4))
    }
}
