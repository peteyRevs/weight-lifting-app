@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// An edit is exactly one `ProgramEditing` call: each case gives the program that call gives, and throws
/// what it throws.
@Suite("ProgramBuilderEdit", .tags(.feature))
nonisolated struct ProgramBuilderActionTests {
    /// Each edit beside the `ProgramEditing` call it stands for.
    static func pairs(on program: Program) throws -> [(edit: ProgramBuilderEdit, expected: Program)] {
        let week = WeekID(Fixtures.uuid(901))
        let day = DayTemplateID(Fixtures.uuid(902))
        return try [
            (.renameProgram(" Winter "), ProgramEditing.renameProgram(program, to: " Winter ")),
            (.addWeek(week), ProgramEditing.addWeek(program, id: week)),
            (.removeLastWeek(loggedWeeks: [0]), ProgramEditing.removeLastWeek(program, loggedWeeks: [0])),
            (.setDeload(true, week: 2), ProgramEditing.setDeload(program, true, week: 2)),
            (.setDeload(false, week: 7), ProgramEditing.setDeload(program, false, week: 7)),
            (
                .setSchedule(week: 1, weekday: .tuesday, day: program.days[3].id),
                ProgramEditing.setSchedule(program, week: 1, weekday: .tuesday, day: program.days[3].id)
            ),
            (
                .setSchedule(week: 1, weekday: .monday, day: nil),
                ProgramEditing.setSchedule(program, week: 1, weekday: .monday, day: nil)
            ),
            (.copyPreviousWeek(week: 7), ProgramEditing.copyPreviousWeek(program, week: 7)),
            (.applyToLaterWeeks(week: 7), ProgramEditing.applyToLaterWeeks(program, week: 7)),
            (.addDay(day, name: "New day"), ProgramEditing.addDay(program, id: day, name: "New day"))
        ]
    }

    @Test("Each edit gives the program its one ProgramEditing call gives, and all but two change the seed program")
    func applied_isTheOneProgramEditingCall() throws {
        let program = try Fixtures.seedProgram()
        let pairs = try Self.pairs(on: program)
        #expect(pairs.count == 10)
        var unchanged: [ProgramBuilderEdit] = []
        for (edit, expected) in pairs {
            let isSame = try edit.applied(to: program) == expected
            #expect(isSame, "\(edit)")
            if expected == program {
                unchanged.append(edit)
            }
        }
        // Applying week 8's schedule to later weeks has none to change; the others are seen to do something.
        #expect(unchanged == [.applyToLaterWeeks(week: 7)])
    }

    @Test("Removing the last week throws what the Domain throws, and nothing else throws")
    func applied_removeLastWeek_throwsTheDomainsErrors() throws {
        let program = try Fixtures.seedProgram()
        #expect(throws: ProgramEditError.weekHasLoggedSessions(weekNumber: 8)) {
            try ProgramBuilderEdit.removeLastWeek(loggedWeeks: [7]).applied(to: program)
        }
        let short = try ProgramFixtures.program(weekCount: 2, days: [])
        #expect(throws: ProgramEditError.minimumTwoWeeks) {
            try ProgramBuilderEdit.removeLastWeek(loggedWeeks: []).applied(to: short)
        }
    }

    @Test("An edit that names a week or an id the program does not hold changes nothing")
    func applied_unknownPlace_changesNothing() throws {
        let program = try Fixtures.seedProgram()
        let edits: [ProgramBuilderEdit] = [
            .setDeload(false, week: 8), .setSchedule(week: -1, weekday: .monday, day: program.days[0].id),
            .setSchedule(week: 0, weekday: .tuesday, day: DayTemplateID(Fixtures.uuid(999))),
            .copyPreviousWeek(week: 0), .applyToLaterWeeks(week: 40), .addWeek(program.weeks[0].id),
            .addDay(program.days[0].id, name: "New day"), .renameProgram("\n")
        ]
        for edit in edits {
            let isSame = try edit.applied(to: program) == program
            #expect(isSame, "\(edit)")
        }
    }

    @Test("Every edit but the removal of the last week gives, applied twice, what one application gives")
    func edits_appliedTwice_onlyRemoveLastWeekDiffers() throws {
        let program = try Fixtures.seedProgram()
        // Removing the last week names "the last", so it is relative: it is sent once.
        let removal = ProgramBuilderEdit.removeLastWeek(loggedWeeks: [])
        let shorter = try removal.applied(to: program)
        let isRelative = try removal.applied(to: shorter) != shorter
        #expect(isRelative)
        // A weekday and a deload are edited by what they become (criterion 12); the others hold an id or a place.
        let absolute: [ProgramBuilderEdit] = [
            .setDeload(true, week: 2), .setDeload(false, week: 7),
            .setSchedule(week: 1, weekday: .tuesday, day: program.days[1].id),
            .setSchedule(week: 1, weekday: .monday, day: nil),
            .renameProgram("Winter"), .addWeek(WeekID(Fixtures.uuid(901))), .copyPreviousWeek(week: 7),
            .applyToLaterWeeks(week: 2), .addDay(DayTemplateID(Fixtures.uuid(902)), name: "New day")
        ]
        for edit in absolute {
            let once = try edit.applied(to: program)
            let hasChanged = once != program
            #expect(hasChanged, "\(edit) is seen to do something")
            let isSame = try edit.applied(to: once) == once
            #expect(isSame, "\(edit)")
        }
    }

    @Test("The name field's action is the rename edit with the text as typed")
    func rename_isTheRenameEditWithTheTypedText() {
        #expect(ProgramBuilderAction.rename("Upper ") == .edit(.renameProgram("Upper "), notice: nil))
    }
}
