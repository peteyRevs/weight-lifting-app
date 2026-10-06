import Foundation
@testable import LedgerDomain
import Testing

/// Seeded properties of `ProgramEditing` (F11 slice S1, criteria 1, 3 and 4). A failure names its seed; add
/// that seed as a fixed case before fixing it (testing-strategy §3 rule 5).
@Suite("ProgramEditing properties", .tags(.domain, .property))
struct ProgramEditingPropertyTests {
    private typealias Support = EditingSupport

    @Test(
        "Thirty random edits of a block keep it one that Program.init and Slot.init accept",
        arguments: PropertySeed.all
    )
    func randomEdits_keepTheProgramValid(seed: PropertySeed) throws {
        var generator = seed.generator
        var program = try Support.randomProgram(using: &generator)
        #expect(Support.faults(in: program).isEmpty, "\(seed): the seeded program")
        for step in 0 ..< 30 {
            let edit = try #require(Support.programEdits.randomElement(using: &generator))
            let edited = try edit.apply(program, 50000 + step, &generator)
            #expect(Support.faults(in: edited).isEmpty, "\(seed), step \(step): \(edit.name)")
            #expect(edited.id == program.id && edited.startDate == program.startDate, "\(seed): \(edit.name)")
            #expect(edited.weeks.count >= 2, "\(seed), step \(step): \(edit.name)")
            program = edited
        }
    }

    @Test(
        "Tapping one weekday once more than there are days comes back to where it started",
        arguments: PropertySeed.all
    )
    func cycleSchedule_daysPlusOneTimes_returnsToTheStart(seed: PropertySeed) throws {
        var generator = seed.generator
        let program = try Support.randomProgram(using: &generator)
        let week = Int.random(in: 0 ..< program.weeks.count, using: &generator)
        let weekday = try #require(Weekday.allCases.randomElement(using: &generator))
        var cycled = program
        var seen: [DayTemplateID?] = []
        for _ in 0 ... program.days.count {
            seen.append(cycled.weeks[week].schedule[weekday])
            cycled = ProgramEditing.cycleSchedule(cycled, week: week, weekday: weekday)
            #expect(Support.faults(in: cycled).isEmpty, "\(seed)")
        }
        #expect(Support.difference(cycled, program).isEmpty, "\(seed)")
        #expect(Set(seen).count == program.days.count + 1, "\(seed): rest and every day are each seen once")
    }

    @Test("Adding a week and removing the last week gives the block back", arguments: PropertySeed.all)
    func addWeek_thenRemoveLastWeek_isTheIdentity(seed: PropertySeed) throws {
        var generator = seed.generator
        let program = try Support.randomProgram(using: &generator)
        let logged = Set(program.weeks.indices.filter { _ in Bool.random(using: &generator) })
        let added = ProgramEditing.addWeek(program, id: WeekID(Fixtures.uuid(50000)))
        #expect(added.weeks.count == program.weeks.count + 1, "\(seed)")
        #expect(added.weeks.last?.schedule == program.weeks.last?.schedule, "\(seed)")
        #expect(added.weeks.last?.isDeload == false, "\(seed)")
        #expect(Support.faults(in: added).isEmpty, "\(seed)")
        let removed = try ProgramEditing.removeLastWeek(added, loggedWeeks: logged)
        #expect(Support.difference(removed, program).isEmpty, "\(seed)")
    }

    @Test(
        "\"−\" throws exactly when the rule says, with the right error, and otherwise drops one week",
        arguments: PropertySeed.all
    )
    func removeLastWeek_followsRuleFour(seed: PropertySeed) throws {
        var generator = seed.generator
        var program = try Support.randomProgram(using: &generator)
        program.weeks.removeLast(Int.random(in: 0 ... program.weeks.count - 2, using: &generator))
        let count = program.weeks.count
        let logged = Set((0 ..< 3).map { _ in Int.random(in: -1 ... count, using: &generator) })
        let result = Result { () throws(ProgramEditError) in try ProgramEditing.removeLastWeek(
            program,
            loggedWeeks: logged
        ) }
        switch result {
        case let .success(shortened):
            #expect(count > 2 && !logged.contains(count - 1), "\(seed)")
            #expect(shortened.weeks.map(\.id) == Array(program.weeks.map(\.id).dropLast()), "\(seed)")
            #expect(Support.faults(in: shortened).isEmpty, "\(seed)")
        case let .failure(error):
            let expected: ProgramEditError = count <= 2 ? .minimumTwoWeeks : .weekHasLoggedSessions(weekNumber: count)
            #expect(error == expected, "\(seed)")
            #expect(count <= 2 || logged.contains(count - 1), "\(seed)")
        }
    }

    @Test(
        "An id the program does not hold, and a week outside the block, leave every function's input unchanged",
        arguments: PropertySeed.all
    )
    func unknownIDsAndWeeks_changeNothing(seed: PropertySeed) throws {
        var generator = seed.generator
        let program = try Support.randomProgram(using: &generator)
        let day = DayTemplateID(Support.unknown)
        let week = Bool.random(using: &generator) ? -1 - Int.random(in: 0 ... 3, using: &generator) : program.weeks
            .count
        let weekday = try #require(Weekday.allCases.randomElement(using: &generator))
        let results = [
            "toggleDeload": ProgramEditing.toggleDeload(program, week: week),
            "cycleSchedule": ProgramEditing.cycleSchedule(program, week: week, weekday: weekday),
            "copyPreviousWeek": ProgramEditing.copyPreviousWeek(program, week: week),
            "applyToLaterWeeks": ProgramEditing.applyToLaterWeeks(program, week: week),
            "renameDay": ProgramEditing.renameDay(program, day: day, to: "Arms"),
            "deleteDay": ProgramEditing.deleteDay(program, day: day),
            "updateDay": ProgramEditing.updateDay(program, day: day) { DayEditing.addSlots(
                $0,
                program.days.flatMap(\.slots)
            ) }
        ]
        for (name, result) in results {
            #expect(Support.difference(result, program).isEmpty, "\(seed): \(name)")
        }
        for existing in program.days {
            for edit in Support.dayEdits.dropFirst() {
                let emptied = DayTemplate(id: existing.id, name: existing.name, tag: existing.tag)
                let edited = try edit.apply(emptied, 50000, &generator)
                #expect(Support.difference(edited, emptied).isEmpty, "\(seed): \(edit.name) on a day with no slots")
            }
            let unknown = SlotID(Support.unknown)
            #expect(Support.difference(DayEditing.removeSlot(existing, slot: unknown), existing).isEmpty, "\(seed)")
            #expect(
                Support.difference(DayEditing.set(.sets(2), slot: unknown, in: existing), existing).isEmpty,
                "\(seed)"
            )
            #expect(
                Support.difference(DayEditing.move(existing, slot: unknown, .downward), existing).isEmpty,
                "\(seed)"
            )
        }
    }
}
