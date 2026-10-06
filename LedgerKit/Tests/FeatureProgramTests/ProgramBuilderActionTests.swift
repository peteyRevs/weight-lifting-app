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
            (.toggleDeload(week: 2), ProgramEditing.toggleDeload(program, week: 2)),
            (
                .cycleSchedule(week: 1, weekday: .tuesday),
                ProgramEditing.cycleSchedule(program, week: 1, weekday: .tuesday)
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
        #expect(pairs.count == 8)
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
            .toggleDeload(week: 8), .cycleSchedule(week: -1, weekday: .monday), .copyPreviousWeek(week: 0),
            .applyToLaterWeeks(week: 40), .addWeek(program.weeks[0].id), .addDay(program.days[0].id, name: "New day"),
            .renameProgram("\n")
        ]
        for edit in edits {
            let isSame = try edit.applied(to: program) == program
            #expect(isSame, "\(edit)")
        }
    }

    @Test("The relative edits applied twice do not give what one application gives: they are sent once")
    func relativeEdits_appliedTwice_differ() throws {
        let program = try Fixtures.seedProgram()
        let relative: [ProgramBuilderEdit] = [
            .toggleDeload(week: 2), .cycleSchedule(week: 1, weekday: .tuesday), .removeLastWeek(loggedWeeks: [])
        ]
        for edit in relative {
            let once = try edit.applied(to: program)
            let twice = try edit.applied(to: once)
            #expect(once != twice, "\(edit)")
        }
        let absolute: [ProgramBuilderEdit] = [
            .renameProgram("Winter"), .addWeek(WeekID(Fixtures.uuid(901))), .copyPreviousWeek(week: 7),
            .applyToLaterWeeks(week: 2), .addDay(DayTemplateID(Fixtures.uuid(902)), name: "New day")
        ]
        for edit in absolute {
            let once = try edit.applied(to: program)
            let isSame = try edit.applied(to: once) == once
            #expect(isSame, "\(edit)")
        }
    }
}
