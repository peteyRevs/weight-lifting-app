import Foundation
@testable import LedgerDomain
import Testing

// A model of the block written from the plan's table "What each function does, and the rule it enforces"
// (S1): the reference the seeded sequences of `ProgramEditing` edits are compared with.

/// One edit of the Program builder's list of days.
enum DayListEdit {
    case add(DayTemplateID, name: String)
    case rename(DayTemplateID, name: String)
    case delete(DayTemplateID)
}

/// One edit of the Program builder, as the model and `ProgramEditing` both take it.
enum BlockEdit: CustomStringConvertible {
    case rename(String)
    case addWeek(WeekID)
    case removeLastWeek(logged: Set<Int>)
    case toggleDeload(week: Int)
    case cycle(week: Int, Weekday)
    case copyPrevious(week: Int)
    case applyLater(week: Int)
    case days(DayListEdit)

    /// Short, with a name as its length: a failure message must stay small and printable.
    var description: String {
        switch self {
        case let .rename(name): "rename(\(name.unicodeScalars.count) scalars)"
        case let .addWeek(id): "addWeek(\(EditAdv.number(id.rawValue)))"
        case let .removeLastWeek(logged): "removeLastWeek(\(logged.sorted()))"
        case let .toggleDeload(week): "toggleDeload(\(week))"
        case let .cycle(week, weekday): "cycle(\(week), \(weekday))"
        case let .copyPrevious(week): "copyPrevious(\(week))"
        case let .applyLater(week): "applyLater(\(week))"
        case let .days(edit): edit.description
        }
    }

    /// The edit through the code under test.
    func applied(to program: Program) throws(ProgramEditError) -> Program {
        switch self {
        case let .rename(name): ProgramEditing.renameProgram(program, to: name)
        case let .addWeek(id): ProgramEditing.addWeek(program, id: id)
        case let .removeLastWeek(logged): try ProgramEditing.removeLastWeek(program, loggedWeeks: logged)
        case let .toggleDeload(week): ProgramEditing.toggleDeload(program, week: week)
        case let .cycle(week, weekday): ProgramEditing.cycleSchedule(program, week: week, weekday: weekday)
        case let .copyPrevious(week): ProgramEditing.copyPreviousWeek(program, week: week)
        case let .applyLater(week): ProgramEditing.applyToLaterWeeks(program, week: week)
        case let .days(edit): edit.applied(to: program)
        }
    }
}

extension DayListEdit {
    var description: String {
        switch self {
        case let .add(id, name): "addDay(\(EditAdv.number(id.rawValue)), \(name.unicodeScalars.count) scalars)"
        case let .rename(id, name): "renameDay(\(EditAdv.number(id.rawValue)), \(name.unicodeScalars.count) scalars)"
        case let .delete(id): "deleteDay(\(EditAdv.number(id.rawValue)))"
        }
    }

    func applied(to program: Program) -> Program {
        switch self {
        case let .add(id, name): ProgramEditing.addDay(program, id: id, name: name)
        case let .rename(id, name): ProgramEditing.renameDay(program, day: id, to: name)
        case let .delete(id): ProgramEditing.deleteDay(program, day: id)
        }
    }
}

/// The block as the plan describes it.
struct BlockModel {
    struct WeekRow {
        var id: WeekID
        var isDeload: Bool
        var schedule: [Weekday: DayTemplateID]
    }

    struct DayRow {
        var id: DayTemplateID
        var name: String
        var tag: String
    }

    var name: String
    var weeks: [WeekRow]
    var days: [DayRow]

    init(_ program: Program) {
        name = program.name
        weeks = program.weeks.map { WeekRow(id: $0.id, isDeload: $0.isDeload, schedule: $0.schedule) }
        days = program.days.map { DayRow(id: $0.id, name: $0.name, tag: $0.tag) }
    }

    /// Applies `edit`; returns the error `removeLastWeek` must throw, when it must.
    mutating func apply(_ edit: BlockEdit) -> ProgramEditError? {
        switch edit {
        case let .rename(typed): name = EditAdv.referenceNameText(typed) ?? name
        case let .addWeek(id): addWeek(id)
        case let .removeLastWeek(logged): return removeLastWeek(logged: logged)
        case let .toggleDeload(week): toggleDeload(week)
        case let .cycle(week, weekday): cycle(week, weekday)
        case let .copyPrevious(week): copyPrevious(week)
        case let .applyLater(week): applyLater(week)
        case let .days(edit): apply(edit)
        }
        return nil
    }

    private mutating func apply(_ edit: DayListEdit) {
        switch edit {
        case let .add(id, typed): addDay(id, typed)
        case let .rename(id, typed): renameDay(id, typed)
        case let .delete(id): deleteDay(id)
        }
    }
}

// MARK: - Weeks and the schedule (rules 4 and 5)

extension BlockModel {
    /// The next index, the last week's schedule, not a deload; an id in use adds nothing.
    private mutating func addWeek(_ id: WeekID) {
        guard !weeks.contains(where: { $0.id == id }), let last = weeks.last else {
            return
        }
        weeks.append(WeekRow(id: id, isDeload: false, schedule: last.schedule))
    }

    /// Two weeks or fewer first, then a logged last week; otherwise the last week goes.
    private mutating func removeLastWeek(logged: Set<Int>) -> ProgramEditError? {
        guard weeks.count > 2 else {
            return .minimumTwoWeeks
        }
        guard !logged.contains(weeks.count - 1) else {
            return .weekHasLoggedSessions(weekNumber: weeks.count)
        }
        weeks.removeLast()
        return nil
    }

    private mutating func toggleDeload(_ week: Int) {
        guard weeks.indices.contains(week) else {
            return
        }
        weeks[week].isDeload.toggle()
    }

    /// Rest, then each day in the order of the days, then rest; rest is no entry.
    private mutating func cycle(_ week: Int, _ weekday: Weekday) {
        guard weeks.indices.contains(week) else {
            return
        }
        weeks[week].schedule[weekday] = next(after: weeks[week].schedule[weekday])
    }

    func next(after current: DayTemplateID?) -> DayTemplateID? {
        guard let current else {
            return days.first?.id
        }
        guard let place = days.firstIndex(where: { $0.id == current }), place + 1 < days.count else {
            return nil
        }
        return days[place + 1].id
    }

    /// The schedule of the week before; the first week has none before it.
    private mutating func copyPrevious(_ week: Int) {
        guard week > 0, weeks.indices.contains(week) else {
            return
        }
        weeks[week].schedule = weeks[week - 1].schedule
    }

    /// Every later week takes this week's schedule; no flag changes.
    private mutating func applyLater(_ week: Int) {
        guard weeks.indices.contains(week) else {
            return
        }
        for later in weeks.indices where later > week {
            weeks[later].schedule = weeks[week].schedule
        }
    }
}

// MARK: - Days (rule 8)

extension BlockModel {
    /// The cleaned name, "D{n}" for the new number of days or the next number whose tag is free; an id in
    /// use or a blank name adds nothing.
    private mutating func addDay(_ id: DayTemplateID, _ typed: String) {
        guard !days.contains(where: { $0.id == id }), let cleaned = EditAdv.referenceNameText(typed) else {
            return
        }
        let taken = Set(days.map(\.tag))
        var number = days.count + 1
        while taken.contains("D\(number)") {
            number += 1
        }
        days.append(DayRow(id: id, name: cleaned, tag: "D\(number)"))
    }

    private mutating func renameDay(_ id: DayTemplateID, _ typed: String) {
        guard let place = days.firstIndex(where: { $0.id == id }), let cleaned = EditAdv.referenceNameText(typed) else {
            return
        }
        days[place].name = cleaned
    }

    /// The day goes, and every schedule entry that names it becomes rest.
    private mutating func deleteDay(_ id: DayTemplateID) {
        days.removeAll { $0.id == id }
        for week in weeks.indices {
            weeks[week].schedule = weeks[week].schedule.filter { $0.value != id }
        }
    }
}

// MARK: - Comparison

extension BlockModel {
    /// The first thing in which `program` is not this block, or `nil` when it is it.
    func difference(from program: Program) -> String? {
        weekDifference(from: program) ?? dayDifference(from: program)
    }

    private func weekDifference(from program: Program) -> String? {
        if Array(program.name.unicodeScalars) != Array(name.unicodeScalars) {
            return "the name has \(program.name.unicodeScalars.count) scalars, expected \(name.unicodeScalars.count)"
        }
        if program.weeks.map(\.id) != weeks.map(\.id) {
            return "week ids \(program.weeks.map { EditAdv.number($0.id.rawValue) })"
        }
        if program.weeks.map(\.index) != Array(weeks.indices) {
            return "week indices \(program.weeks.map(\.index))"
        }
        if program.weeks.map(\.isDeload) != weeks.map(\.isDeload) {
            return "deload flags \(program.weeks.map(\.isDeload)), expected \(weeks.map(\.isDeload))"
        }
        if let week = weeks.indices.first(where: { program.weeks[$0].schedule != weeks[$0].schedule }) {
            let found = Self.brief(program.weeks[week].schedule)
            return "the schedule of week index \(week) is \(found), expected \(Self.brief(weeks[week].schedule))"
        }
        return nil
    }

    private func dayDifference(from program: Program) -> String? {
        if program.days.map(\.id) != days.map(\.id) {
            return "day ids \(program.days.map { EditAdv.number($0.id.rawValue) })"
        }
        if program.days.map(\.tag) != days.map(\.tag) {
            return "tags \(program.days.map(\.tag)), expected \(days.map(\.tag))"
        }
        if program.days.map({ Array($0.name.unicodeScalars) }) != days.map({ Array($0.name.unicodeScalars) }) {
            return "a day's name"
        }
        return nil
    }

    /// "300 - 310 - 320 330 -": the day each weekday trains, Monday first.
    static func brief(_ schedule: [Weekday: DayTemplateID]) -> String {
        Weekday.allCases.map { schedule[$0].map { String(EditAdv.number($0.rawValue)) } ?? "-" }.joined(separator: " ")
    }
}
