import Foundation

// MARK: - Training days (rule 8)

public extension ProgramEditing {
    /// "+ Add training day" (rule 8): appends a day with the cleaned `name`, no slots, and the tag "D{n}",
    /// where n is the new number of days, or the next number above it whose tag no day has. No schedule
    /// changes. A blank name, or an `id` that a day of the program already has, adds nothing.
    static func addDay(_ program: Program, id: DayTemplateID, name: String) -> Program {
        guard let cleaned = cleanedName(name), !program.days.contains(where: { $0.id == id }) else {
            return program
        }
        var edited = program
        edited.days.append(DayTemplate(id: id, name: cleaned, tag: freeTag(in: program.days)))
        return edited
    }

    /// Sets the day's cleaned name. A blank name, or a day the program does not hold, changes nothing.
    static func renameDay(_ program: Program, day: DayTemplateID, to name: String) -> Program {
        guard let cleaned = cleanedName(name) else {
            return program
        }
        return updateDay(program, day: day) { current in
            var renamed = current
            renamed.name = cleaned
            return renamed
        }
    }

    /// Removes the day, and every schedule entry that names it becomes rest.
    static func deleteDay(_ program: Program, day: DayTemplateID) -> Program {
        guard program.days.contains(where: { $0.id == day }) else {
            return program
        }
        var edited = program
        edited.days.removeAll { $0.id == day }
        for week in edited.weeks.indices {
            edited.weeks[week].schedule = edited.weeks[week].schedule.filter { $0.value != day }
        }
        return edited
    }

    /// Replaces the day by `change(day)`: how a `DayEditing` function is applied inside a program. A result
    /// with another id is ignored, so a change can never put another day in this one's place.
    static func updateDay(
        _ program: Program,
        day: DayTemplateID,
        _ change: (DayTemplate) -> DayTemplate
    ) -> Program {
        guard let place = program.days.firstIndex(where: { $0.id == day }) else {
            return program
        }
        let changed = change(program.days[place])
        guard changed.id == day else {
            return program
        }
        var edited = program
        edited.days[place] = changed
        return edited
    }

    /// Rule 8's tag for a day added to `days`: "D{n}" for the new number of days, counting up past every
    /// tag a day already has (a day was deleted and another added).
    private static func freeTag(in days: [DayTemplate]) -> String {
        let taken = Set(days.map(\.tag))
        var number = days.count + 1
        while taken.contains("D\(number)") {
            number += 1
        }
        return "D\(number)"
    }
}
