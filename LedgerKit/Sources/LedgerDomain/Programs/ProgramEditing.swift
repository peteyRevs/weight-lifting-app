import Foundation

/// The Program builder's edits to a block (spec §3.2; rules 4, 5 and 8), as pure functions from a program to
/// the edited program. A store applies them and adds nothing: every rule of the block is enforced here.
///
/// Every function is total. `week` is a week's zero-based index, which is also its place in `weeks`
/// (`Program.init` keeps the two equal). Given a week the block does not have, or an id the program does not
/// hold, a function returns the program unchanged. Given a program `Program.init` accepts, every result is one
/// it accepts too; fields are assigned directly, because each function keeps the block's invariants itself.
///
/// No function here writes a slot of its own accord; `updateDay` stores the day its closure returns, so only
/// `DayEditing`'s functions go in that closure. A slot's misses and its exercise are written by a workout's
/// save alone, so a builder edit and a workout's save give the same program in either order (F11 slice S1,
/// criterion 12).
public enum ProgramEditing {
    // MARK: - Names

    /// `text` as a name that can be stored: every control character removed (Unicode category `Cc`, which
    /// holds U+0000, the tab, LF, CR and NEL), then white space trimmed from both ends. `nil` when nothing
    /// is left. The line and paragraph separators, U+2028 and U+2029, are not of that category: they are
    /// trimmed from the ends as white space and kept inside a name.
    public static func cleanedName(_ text: String) -> String? {
        let cleaned = String(text.unicodeScalars.filter { $0.properties.generalCategory != .control })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Sets the program's cleaned name. A blank name changes nothing.
    public static func renameProgram(_ program: Program, to name: String) -> Program {
        guard let cleaned = cleanedName(name) else {
            return program
        }
        var edited = program
        edited.name = cleaned
        return edited
    }

    // MARK: - Weeks (rule 4)

    /// "+": appends a week with the next index and the last week's schedule, never a deload. An `id` that a
    /// week of the block already has adds nothing.
    public static func addWeek(_ program: Program, id: WeekID) -> Program {
        guard !program.weeks.contains(where: { $0.id == id }) else {
            return program
        }
        var edited = program
        edited.weeks.append(Week(id: id, index: program.weeks.count, schedule: program.weeks.last?.schedule ?? [:]))
        return edited
    }

    /// "−": drops the last week. A block of two weeks throws `.minimumTwoWeeks`, whatever else holds. Then a
    /// last week that is among `loggedWeeks`, the zero-based indices of the weeks holding a finished workout
    /// of this program, throws `.weekHasLoggedSessions` with its one-based number. Indices outside the block
    /// are ignored.
    public static func removeLastWeek(
        _ program: Program,
        loggedWeeks: Set<Int>
    ) throws(ProgramEditError) -> Program {
        let count = program.weeks.count
        guard count > Program.minimumWeeks else {
            throw .minimumTwoWeeks
        }
        guard !loggedWeeks.contains(count - 1) else {
            throw .weekHasLoggedSessions(weekNumber: count)
        }
        var edited = program
        edited.weeks.removeLast()
        return edited
    }

    /// "Deload": flips that week's flag.
    public static func toggleDeload(_ program: Program, week: Int) -> Program {
        editing(program, week: week) { $0[week].isDeload.toggle() }
    }

    // MARK: - Schedule

    /// A tap on a weekday of the schedule strip (rule 5): rest, then each of the program's days in the order
    /// of `days`, then rest again. Rest is the absence of an entry. A program with no days stays at rest.
    public static func cycleSchedule(_ program: Program, week: Int, weekday: Weekday) -> Program {
        let days = program.days.map(\.id)
        return editing(program, week: week) { weeks in
            let place = weeks[week].schedule[weekday].flatMap(days.firstIndex(of:))
            let next = place.map { $0 + 1 } ?? 0
            weeks[week].schedule[weekday] = next < days.count ? days[next] : nil
        }
    }

    /// "Copy week n − 1": the week takes the schedule of the week before and keeps its own deload flag. The
    /// first week has no week before it and is unchanged.
    public static func copyPreviousWeek(_ program: Program, week: Int) -> Program {
        guard week > 0 else {
            return program
        }
        return editing(program, week: week) { $0[week].schedule = $0[week - 1].schedule }
    }

    /// "Apply to later weeks": every later week takes this week's schedule; every deload flag stays.
    public static func applyToLaterWeeks(_ program: Program, week: Int) -> Program {
        editing(program, week: week) { weeks in
            for later in weeks.indices where later > week {
                weeks[later].schedule = weeks[week].schedule
            }
        }
    }

    /// `program` with `change` applied to its weeks when the block has a week at `week`; unchanged otherwise.
    private static func editing(_ program: Program, week: Int, _ change: (inout [Week]) -> Void) -> Program {
        guard program.weeks.indices.contains(week) else {
            return program
        }
        var edited = program
        change(&edited.weeks)
        return edited
    }
}
