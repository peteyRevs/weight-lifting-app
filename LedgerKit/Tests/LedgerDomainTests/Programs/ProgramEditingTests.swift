import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criteria 2 and 3: names and weeks, on the spec's seed block (`Fixtures.fourDayProgram()`).
/// The schedule is in `ProgramEditingScheduleTests`, the days in `ProgramEditingDaysTests`.
@Suite("ProgramEditing", .tags(.domain))
struct ProgramEditingTests {
    private typealias Support = EditingTestSupport

    struct NameRow: Sendable, CustomStringConvertible {
        let text: String
        let cleaned: String?
        let description: String

        static let all: [NameRow] = [
            NameRow(text: "  Upper A \n", cleaned: "Upper A", description: "trimmed at both ends"),
            NameRow(text: "Push\u{0} day", cleaned: "Push day", description: "U+0000 removed"),
            NameRow(
                text: "A\tB\r\nC",
                cleaned: "ABC",
                description: "tab and line breaks are removed, not turned into blanks"
            ),
            NameRow(text: "\u{0}\u{7}\u{1B}\u{7F}\u{85}\u{9F}", cleaned: nil, description: "only control characters"),
            NameRow(text: " \u{0} ", cleaned: nil, description: "blanks around a control character"),
            NameRow(text: "", cleaned: nil, description: "empty"),
            NameRow(text: " \u{3000}\u{A0}\u{200B} ", cleaned: nil, description: "only blanks of other widths"),
            NameRow(text: "\u{3000}Legs\u{A0}", cleaned: "Legs", description: "wide and non-breaking blanks trimmed"),
            NameRow(text: "E\u{301}paules", cleaned: "E\u{301}paules", description: "a combining mark is kept"),
            NameRow(text: " \u{301} ", cleaned: "\u{301}", description: "a lone combining mark is a name"),
            NameRow(text: "Upper A — Push focus", cleaned: "Upper A — Push focus", description: "unchanged")
        ]
    }

    let program: Program

    init() throws {
        program = try Fixtures.fourDayProgram()
    }

    /// A week's strip from Monday to Sunday, as tags, with "REST" where nothing is scheduled.
    static func strip(_ program: Program, week: Int) -> [String] {
        Weekday.allCases.map { weekday in
            guard let id = program.weeks[week].schedule[weekday] else {
                return "REST"
            }
            return program.days.first { $0.id == id }?.tag ?? "?"
        }
    }

    static let trainingWeek = ["UA", "REST", "LA", "REST", "UB", "LB", "REST"]
    static let deloadWeek = ["UA", "REST", "LA", "REST", "UB", "REST", "REST"]

    // MARK: - Names

    @Test(
        "A name loses its control characters, then the blanks at its ends; nothing left is no name",
        arguments: NameRow.all
    )
    func cleanedName_removesControlCharactersAndTrims(row: NameRow) {
        let cleaned = ProgramEditing.cleanedName(row.text)
        #expect(cleaned == row.cleaned)
        #expect(cleaned.flatMap(ProgramEditing.cleanedName) == cleaned, "a cleaned name cleans to itself")
    }

    @Test("A name of 10,000 characters is kept whole: the model sets no length")
    func cleanedName_longName_isKept() {
        let name = String(repeating: "Lower B ", count: 1250)
        #expect(ProgramEditing.cleanedName(name)?.count == 9999)
    }

    @Test("Renaming the program stores the cleaned name and touches nothing else")
    func renameProgram_setsTheCleanedName() {
        let renamed = ProgramEditing.renameProgram(program, to: " Push\u{0} / Pull \n")
        #expect(renamed.name == "Push / Pull")
        var expected = program
        expected.name = "Push / Pull"
        #expect(Support.difference(renamed, expected).isEmpty)
    }

    @Test("A blank program name is not stored: the name stays", arguments: ["", "   ", "\u{0}\n\t"])
    func renameProgram_blank_changesNothing(name: String) {
        let renamed = ProgramEditing.renameProgram(program, to: name)
        #expect(renamed.name == "Upper / Lower")
        #expect(Support.difference(renamed, program).isEmpty)
    }

    // MARK: - Weeks (F11 criterion 4)

    @Test("\"+\" appends a week with the next index and the last week's schedule, not a deload (rule 4)")
    func addWeek_copiesTheLastWeeksSchedule_notADeload() throws {
        let added = ProgramEditing.addWeek(program, id: WeekID(Fixtures.uuid(208)))
        #expect(added.weeks.count == 9)
        let last = try #require(added.weeks.last)
        #expect(last.id == WeekID(Fixtures.uuid(208)))
        #expect(last.index == 8)
        #expect(!last.isDeload)
        #expect(Self.strip(added, week: 8) == Self.deloadWeek, "week 8's three days, though week 8 is the deload")
        #expect(added.weeks.map(\.isDeload) == [false, false, false, false, false, false, false, true, false])
        #expect(Support.faults(in: added).isEmpty)
        var shortened = added
        shortened.weeks.removeLast()
        #expect(
            Support.difference(shortened, program).isEmpty,
            "the first eight weeks and the days are untouched"
        )
    }

    @Test("A week id the block already has adds nothing")
    func addWeek_idInUse_addsNothing() {
        let added = ProgramEditing.addWeek(program, id: program.weeks[3].id)
        #expect(added.weeks.count == 8)
        #expect(Support.difference(added, program).isEmpty)
    }

    @Test(
        "\"−\" at two weeks throws minimumTwoWeeks, whatever the logged weeks hold (rule 4)",
        arguments: [[], [1], [0, 1], [7, -1]] as [Set<Int>]
    )
    func removeLastWeek_atTwoWeeks_throwsMinimumTwoWeeks(logged: Set<Int>) throws {
        var short = program
        short.weeks.removeLast(6)
        #expect(throws: ProgramEditError.minimumTwoWeeks) {
            try ProgramEditing.removeLastWeek(short, loggedWeeks: logged)
        }
        let three = ProgramEditing.addWeek(short, id: WeekID(Fixtures.uuid(250)))
        #expect(try ProgramEditing.removeLastWeek(three, loggedWeeks: []).weeks.count == 2, "three weeks can lose one")
    }

    @Test("\"−\" on a last week that holds a finished workout throws with its one-based number")
    func removeLastWeek_loggedWeek_throwsWithItsNumber() throws {
        #expect(throws: ProgramEditError.weekHasLoggedSessions(weekNumber: 8)) {
            try ProgramEditing.removeLastWeek(program, loggedWeeks: [7])
        }
        #expect(throws: ProgramEditError.weekHasLoggedSessions(weekNumber: 8)) {
            try ProgramEditing.removeLastWeek(program, loggedWeeks: [0, 7, 99])
        }
        let seven = try ProgramEditing.removeLastWeek(program, loggedWeeks: [])
        #expect(throws: ProgramEditError.weekHasLoggedSessions(weekNumber: 7)) {
            try ProgramEditing.removeLastWeek(seven, loggedWeeks: [6])
        }
    }

    @Test(
        "\"−\" drops the last week when only other weeks, or indices outside the block, are logged",
        arguments: [[], [0, 3], [6], [8, 99, -1, .max, .min]] as [Set<Int>]
    )
    func removeLastWeek_lastWeekNotLogged_dropsIt(logged: Set<Int>) throws {
        let shortened = try ProgramEditing.removeLastWeek(program, loggedWeeks: logged)
        #expect(shortened.weeks.map(\.index) == Array(0 ..< 7))
        #expect(shortened.weeks.map(\.id) == Array(program.weeks.map(\.id).dropLast()))
        #expect(Support.faults(in: shortened).isEmpty)
    }

    @Test("\"−\" leaves every day, every slot and every other week as it was")
    func removeLastWeek_leavesEveryDayAndSlotUntouched() throws {
        let block = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let shortened = try ProgramEditing.removeLastWeek(block, loggedWeeks: [2])
        var expected = block
        expected.weeks.removeLast()
        #expect(shortened.weeks.count == 7)
        #expect(shortened.days.map(\.slots.count) == [5, 1])
        #expect(Support.difference(shortened, expected).isEmpty)
    }

    @Test("\"Deload\" flips one week's flag and nothing else; twice gives the block back (F11 criterion 3)")
    func toggleDeload_flipsOneWeek() {
        let toggled = ProgramEditing.toggleDeload(program, week: 2)
        #expect(toggled.weeks.map(\.isDeload) == [false, false, true, false, false, false, false, true])
        #expect(Self.strip(toggled, week: 2) == Self.trainingWeek)
        #expect(ProgramEditing.toggleDeload(toggled, week: 7).weeks.filter(\.isDeload).map(\.index) == [2])
        #expect(Support.difference(ProgramEditing.toggleDeload(toggled, week: 2), program).isEmpty)
    }
}

// MARK: - Totality (slice S1 criterion 1)

extension ProgramEditingTests {
    @Test("A block emptied of its weeks outside the model makes no function trap; \"+\" gives it a first week at rest")
    func blockWithNoWeeks_noFunctionTraps() {
        var empty = program
        empty.weeks = []
        let first = ProgramEditing.addWeek(empty, id: WeekID(Fixtures.uuid(208)))
        #expect(first.weeks.map(\.index) == [0])
        #expect(first.weeks.map(\.schedule.count) == [0])
        #expect(first.weeks.map(\.isDeload) == [false])
        #expect(throws: ProgramEditError.minimumTwoWeeks) {
            try ProgramEditing.removeLastWeek(empty, loggedWeeks: [0, -1])
        }
        #expect(throws: ProgramEditError.minimumTwoWeeks) {
            try ProgramEditing.removeLastWeek(first, loggedWeeks: [])
        }
        for week in [-1, 0, 1] {
            let results = [
                ProgramEditing.toggleDeload(empty, week: week),
                ProgramEditing.cycleSchedule(empty, week: week, weekday: .monday),
                ProgramEditing.copyPreviousWeek(empty, week: week),
                ProgramEditing.applyToLaterWeeks(empty, week: week)
            ]
            #expect(results.map { Support.difference($0, empty) } == ["", "", "", ""], "week \(week)")
        }
        #expect(ProgramEditing.deleteDay(empty, day: Fixtures.fourDayIDs[0]).days.map(\.tag) == ["LA", "UB", "LB"])
        let added = ProgramEditing.addDay(empty, id: DayTemplateID(Fixtures.uuid(340)), name: "New day")
        #expect(added.days.map(\.tag) == ["UA", "LA", "UB", "LB", "D5"])
    }
}
