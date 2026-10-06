import Foundation
@testable import LedgerDomain
import Testing

/// Slice criterion 5 beyond the worked examples: the tag of an added day after adds and deletes ("the next
/// number whose tag is free"), ids in use, blank names, `updateDay`, and programs with no day or one day.
@Suite("ProgramEditing days (adversarial)", .tags(.domain))
struct ProgramEditingDaysAdversarialTests {
    let program: Program
    let ids = EditAdv.fourDayIDs

    init() throws {
        program = try EditAdv.fourDayProgram()
    }

    /// `count` days added one after another under the ids 340, 341, …
    static func adding(_ count: Int, to program: Program, from first: Int = 340) -> Program {
        (0 ..< count).reduce(program) { current, offset in
            ProgramEditing.addDay(current, id: EditAdv.dayID(first + offset), name: "New day")
        }
    }
}

// MARK: - Tags (rule 8, behaviour 4)

extension ProgramEditingDaysAdversarialTests {
    @Test("Three days added in a row are tagged D5, D6, D7.")
    func addDay_threeInARow_countsUp() {
        let added = Self.adding(3, to: program)
        #expect(added.days.map(\.tag) == ["UA", "LA", "UB", "LB", "D5", "D6", "D7"])
    }

    @Test("Add, delete, add: the last day deleted and another added is D5 again.")
    func addDay_afterDeletingTheLast_reusesItsNumber() {
        let added = Self.adding(1, to: program)
        let deleted = ProgramEditing.deleteDay(added, day: EditAdv.dayID(340))
        let again = ProgramEditing.addDay(deleted, id: EditAdv.dayID(341), name: "New day")
        #expect(again.days.map(\.tag) == ["UA", "LA", "UB", "LB", "D5"])
    }

    @Test("Add D5 and D6, delete D5, add: six days would be D6, which is taken, so the new day is D7.")
    func addDay_whenTheCountsTagIsTaken_takesTheNextFreeNumber() {
        let added = Self.adding(2, to: program)
        let deleted = ProgramEditing.deleteDay(added, day: EditAdv.dayID(340))
        let again = ProgramEditing.addDay(deleted, id: EditAdv.dayID(342), name: "New day")
        #expect(again.days.map(\.tag) == ["UA", "LA", "UB", "LB", "D6", "D7"])
        #expect(Set(again.days.map(\.tag)).count == again.days.count)
    }

    @Test("Add D5, D6, D7, delete D5 and D6, add twice: the new days are D6 and then D8, never a second D7.")
    func addDay_aroundATagAhead_skipsIt() {
        let added = Self.adding(3, to: program)
        let fewer = [340, 341].reduce(added) { ProgramEditing.deleteDay($0, day: EditAdv.dayID($1)) }
        let again = Self.adding(2, to: fewer, from: 350)
        #expect(again.days.map(\.tag) == ["UA", "LA", "UB", "LB", "D7", "D6", "D8"])
    }

    @Test("A deleted first day does not shift the count: with LA, UB, LB left, the new day is D4.")
    func addDay_afterDeletingAnOriginalDay_usesTheNewCount() {
        let deleted = ProgramEditing.deleteDay(program, day: ids[0])
        let added = ProgramEditing.addDay(deleted, id: EditAdv.dayID(340), name: "New day")
        #expect(added.days.map(\.tag) == ["LA", "UB", "LB", "D4"])
    }

    @Test("A day the lifter's program already tags D5 pushes the added day to D6.")
    func addDay_whenAnExistingDayHoldsTheTag_skipsIt() throws {
        var days = program.days
        days[1].tag = "D5"
        let tagged = try EditAdv.program(weeks: program.weeks, days: days)
        let added = ProgramEditing.addDay(tagged, id: EditAdv.dayID(340), name: "New day")
        #expect(added.days.map(\.tag) == ["UA", "D5", "UB", "LB", "D6"])
    }

    @Test("The first day of a program with none is D1, and the block stays valid.")
    func addDay_toAProgramWithNoDays_isD1() throws {
        let empty = try EditAdv.program(weeks: EditAdv.restWeeks(2), days: [])
        let added = ProgramEditing.addDay(empty, id: EditAdv.dayID(340), name: "New day")
        #expect(added.days.map(\.tag) == ["D1"])
        #expect(added.days.map(\.id) == [EditAdv.dayID(340)])
        #expect(EditAdv.rejection(of: added) == nil)
    }
}

// MARK: - Ids, names, schedules

extension ProgramEditingDaysAdversarialTests {
    @Test("An id a day already has adds nothing, wherever that day is.", arguments: [300, 310, 330])
    func addDay_idInUse_addsNothing(number: Int) {
        let unchanged = ProgramEditing.addDay(program, id: EditAdv.dayID(number), name: "New day") == program
        #expect(unchanged)
    }

    @Test("A blank name adds no day.")
    func addDay_blankName_addsNothing() {
        for name in ["", " ", "\t\n", "\u{0}", " \u{7F}\u{85} ", "\u{3000}\u{A0}"] {
            let unchanged = ProgramEditing.addDay(program, id: EditAdv.dayID(340), name: name) == program
            #expect(unchanged, "a day was added under a blank name of \(name.unicodeScalars.count) scalars")
        }
    }

    @Test("The added day's name is the cleaned name, and the day is appended after the others.")
    func addDay_cleansTheName() {
        let added = ProgramEditing.addDay(program, id: EditAdv.dayID(340), name: "  Arm\u{0} day\n")
        #expect(added.days.last?.name == "Arm day")
        #expect(added.days.last?.tag == "D5")
    }

    @Test("Deleting a day the program does not hold changes nothing.")
    func deleteDay_unknownID_changesNothing() {
        let unchanged = ProgramEditing.deleteDay(program, day: EditAdv.dayID(999)) == program
        #expect(unchanged)
    }

    @Test("Every day deleted: no days, every weekday of every week at rest, and the block is still valid.")
    func deleteDay_everyDay_leavesAnEmptyValidBlock() {
        let emptied = ids.reduce(program) { ProgramEditing.deleteDay($0, day: $1) }
        #expect(emptied.days.isEmpty)
        let everyWeekdayRests = emptied.weeks.allSatisfy(\.schedule.isEmpty)
        #expect(everyWeekdayRests)
        #expect(emptied.weeks.count == 8)
        #expect(EditAdv.rejection(of: emptied) == nil)
        let tapped = ProgramEditing.cycleSchedule(emptied, week: 0, weekday: .monday) == emptied
        #expect(tapped, "a tap in a block with no days must leave the weekday at rest")
    }

    @Test("With one day a weekday goes rest, that day, rest.")
    func cycleSchedule_oneDay_alternates() throws {
        let single = try EditAdv.program(weeks: EditAdv.restWeeks(2), days: [program.days[2]])
        let once = ProgramEditing.cycleSchedule(single, week: 1, weekday: .friday)
        #expect(once.weeks[1].schedule == [.friday: ids[2]])
        let twice = ProgramEditing.cycleSchedule(once, week: 1, weekday: .friday) == single
        #expect(twice)
    }

    @Test("After the first day is deleted the cycle follows the days that are left, in their order.")
    func cycleSchedule_afterADelete_followsTheRemainingDays() {
        let deleted = ProgramEditing.deleteDay(program, day: ids[0])
        var current = deleted
        var seen: [DayTemplateID?] = []
        for _ in 1 ... 4 {
            current = ProgramEditing.cycleSchedule(current, week: 0, weekday: .tuesday)
            seen.append(current.weeks[0].schedule[.tuesday])
        }
        #expect(seen == [ids[1], ids[2], ids[3], nil])
    }

    @Test("An added day is the last stop of the cycle before rest.")
    func cycleSchedule_afterAnAdd_reachesTheNewDayLast() {
        var current = Self.adding(1, to: program)
        var seen: [DayTemplateID?] = []
        for _ in 1 ... 6 {
            current = ProgramEditing.cycleSchedule(current, week: 7, weekday: .sunday)
            seen.append(current.weeks[7].schedule[.sunday])
        }
        #expect(seen == [ids[0], ids[1], ids[2], ids[3], EditAdv.dayID(340), nil])
    }
}

// MARK: - updateDay and renameDay

extension ProgramEditingDaysAdversarialTests {
    @Test("updateDay replaces the one day with the change's result and leaves the rest.")
    func updateDay_replacesThatDay() throws {
        let slot = try EditAdv.distinctSlot(0, id: 5000, joined: false)
        let updated = ProgramEditing.updateDay(program, day: ids[1]) { day in
            DayTemplate(id: day.id, name: "Legs", tag: day.tag, slots: [slot])
        }
        var expected = program
        expected.days[1].name = "Legs"
        expected.days[1].slots = [slot]
        let onlyThatDay = updated == expected
        #expect(onlyThatDay)
    }

    @Test("updateDay ignores a result with another id, even the id of another day of the program.")
    func updateDay_resultWithAnotherID_isIgnored() {
        let stranger = ProgramEditing.updateDay(program, day: ids[1]) { day in
            DayTemplate(id: EditAdv.dayID(999), name: "Other", tag: day.tag)
        } == program
        #expect(stranger)
        let sibling = ProgramEditing.updateDay(program, day: ids[1]) { _ in program.days[0] } == program
        #expect(sibling)
    }

    @Test("updateDay for a day the program does not hold changes nothing and does not ask for the change.")
    func updateDay_unknownDay_changesNothing() {
        var asked = 0
        let unchanged = ProgramEditing.updateDay(program, day: EditAdv.dayID(999)) { day in
            asked += 1
            return day
        } == program
        #expect(unchanged)
        #expect(asked == 0)
    }

    @Test("renameDay sets the cleaned name of that day alone; a blank name or an unknown day changes nothing.")
    func renameDay_setsTheCleanedName() {
        let renamed = ProgramEditing.renameDay(program, day: ids[2], to: "\u{1F} Pull\u{9}day ")
        var expected = program
        expected.days[2].name = "Pullday"
        let onlyThatName = renamed == expected
        #expect(onlyThatName)
        let blank = ProgramEditing.renameDay(program, day: ids[2], to: " \u{0}\n") == program
        #expect(blank)
        let unknown = ProgramEditing.renameDay(program, day: EditAdv.dayID(999), to: "Pull") == program
        #expect(unknown)
    }

    @Test("renameProgram sets the cleaned name and nothing else; a blank name keeps the stored one.")
    func renameProgram_setsTheCleanedName() {
        let renamed = ProgramEditing.renameProgram(program, to: "\tPush\u{0} / Pull  ")
        var expected = program
        expected.name = "Push / Pull"
        let onlyTheName = renamed == expected
        #expect(onlyTheName)
        for blank in ["", "   ", "\u{0}\u{1}", "\r\n", "\u{2028}\u{2029}"] {
            let kept = ProgramEditing.renameProgram(program, to: blank) == program
            #expect(kept, "a blank name was stored")
        }
    }
}
