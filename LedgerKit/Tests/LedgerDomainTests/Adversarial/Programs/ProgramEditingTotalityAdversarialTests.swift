import Foundation
@testable import LedgerDomain
import Testing

#if os(macOS)
    /// Slice criterion 1, "never traps": each attack runs in a child process (testing-strategy §2.1 exit
    /// tests), so a trap fails one test instead of ending the run. A lifter editing a program must never
    /// crash the app, so these also drive shapes the types allow and the model does not: `Program.weeks` and
    /// `Program.days` are `var`, and `Program.init` checks neither that an id is used once nor anything
    /// about slots.
    @Suite("ProgramEditing never traps (adversarial)", .tags(.domain))
    struct ProgramEditingTotalityAdversarialTests {
        static let extremeWeeks = [Int.min, Int.min + 1, -1, 8, 9, Int.max - 1, Int.max]

        /// Every function of `ProgramEditing` on `program`, for weeks around the block's ends, every
        /// weekday, every day the program holds and one it does not. Returns every result.
        static func everyEdit(of program: Program) -> [Program] {
            var results: [Program] = []
            for week in [-1, 0, 1, program.weeks.count - 1, program.weeks.count] {
                results.append(ProgramEditing.toggleDeload(program, week: week))
                results.append(ProgramEditing.copyPreviousWeek(program, week: week))
                results.append(ProgramEditing.applyToLaterWeeks(program, week: week))
                results += Weekday.allCases.map { ProgramEditing.cycleSchedule(program, week: week, weekday: $0) }
            }
            for day in program.days.map(\.id) + [EditAdv.dayID(999)] {
                results.append(ProgramEditing.deleteDay(program, day: day))
                results.append(ProgramEditing.renameDay(program, day: day, to: "Name"))
                results.append(ProgramEditing.updateDay(program, day: day) { $0 })
                results.append(ProgramEditing.addDay(program, id: day, name: "Name"))
            }
            results.append(ProgramEditing.addWeek(program, id: EditAdv.weekID(60000)))
            results += program.weeks.map { ProgramEditing.addWeek(program, id: $0.id) }
            results.append(ProgramEditing.renameProgram(program, to: "Name"))
            results.append(ProgramEditing.addDay(program, id: EditAdv.dayID(70000), name: "Name"))
            for logged in [[], [program.weeks.count - 1], [Int.min, Int.max]] as [Set<Int>] {
                results.append((try? ProgramEditing.removeLastWeek(program, loggedWeeks: logged)) ?? program)
            }
            return results
        }

        /// Every edit of `program`, then every edit of each result: how many programs came back.
        static func twoRounds(of program: Program) -> Int {
            everyEdit(of: program).reduce(0) { $0 + everyEdit(of: $1).count }
        }

        /// Whether `removeLastWeek` refuses `program` with `minimumTwoWeeks`.
        static func refusesToShorten(_ program: Program) -> Bool {
            do {
                _ = try ProgramEditing.removeLastWeek(program, loggedWeeks: [])
                return false
            } catch {
                return error == .minimumTwoWeeks
            }
        }
    }

    // MARK: - Week indices

    extension ProgramEditingTotalityAdversarialTests {
        @Test("toggleDeload for weeks from Int.min to Int.max returns the block unchanged instead of trapping.")
        func toggleDeload_extremeWeek_changesNothing() async {
            await #expect(processExitsWith: .success) {
                let program = try EditAdv.fourDayProgram()
                let unchanged = Self.extremeWeeks
                    .allSatisfy { ProgramEditing.toggleDeload(program, week: $0) == program }
                exit(unchanged ? 0 : 1)
            }
        }

        @Test("cycleSchedule for weeks from Int.min to Int.max returns the block unchanged instead of trapping.")
        func cycleSchedule_extremeWeek_changesNothing() async {
            await #expect(processExitsWith: .success) {
                let program = try EditAdv.fourDayProgram()
                let unchanged = Self.extremeWeeks.allSatisfy { week in
                    Weekday.allCases
                        .allSatisfy { ProgramEditing.cycleSchedule(program, week: week, weekday: $0) == program }
                }
                exit(unchanged ? 0 : 1)
            }
        }

        @Test("copyPreviousWeek for weeks from Int.min to Int.max returns the block unchanged instead of trapping.")
        func copyPreviousWeek_extremeWeek_changesNothing() async {
            await #expect(processExitsWith: .success) {
                let program = try EditAdv.fourDayProgram()
                let unchanged = Self.extremeWeeks
                    .allSatisfy { ProgramEditing.copyPreviousWeek(program, week: $0) == program }
                exit(unchanged ? 0 : 1)
            }
        }

        @Test("applyToLaterWeeks for weeks from Int.min to Int.max returns the block unchanged instead of trapping.")
        func applyToLaterWeeks_extremeWeek_changesNothing() async {
            await #expect(processExitsWith: .success) {
                let program = try EditAdv.fourDayProgram()
                let unchanged = Self.extremeWeeks
                    .allSatisfy { ProgramEditing.applyToLaterWeeks(program, week: $0) == program }
                exit(unchanged ? 0 : 1)
            }
        }

        @Test("removeLastWeek ignores logged weeks of Int.min and Int.max and drops the last week.")
        func removeLastWeek_extremeLoggedWeeks_areIgnored() async {
            await #expect(processExitsWith: .success) {
                let program = try EditAdv.fourDayProgram()
                let shorter = try ProgramEditing.removeLastWeek(program, loggedWeeks: [Int.min, -1, 8, Int.max])
                let short = try EditAdv.fourDayProgram(weekCount: 2)
                exit(shorter.weeks.count == 7 && Self.refusesToShorten(short) ? 0 : 1)
            }
        }
    }

    // MARK: - Shapes the types allow

    extension ProgramEditingTotalityAdversarialTests {
        @Test(
            "Two rounds of every edit on the seed schedule, on a block with no days and on one with one day never trap."
        )
        func everyEdit_onValidBlocks_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let single = try EditAdv.program(weeks: EditAdv.restWeeks(2), days: [EditAdv.day(flags: [false, true])])
                let blocks = try [
                    EditAdv.fourDayProgram(),
                    EditAdv.program(weeks: EditAdv.restWeeks(2), days: []),
                    single
                ]
                exit(blocks.map(Self.twoRounds).allSatisfy { $0 > 0 } ? 0 : 1)
            }
        }

        @Test(
            "A block left with no weeks or one week (the property is var) refuses \"−\" and survives every other edit."
        )
        func everyEdit_onABlockWithTooFewWeeks_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                var none = try EditAdv.fourDayProgram()
                none.weeks = []
                var one = try EditAdv.fourDayProgram()
                one.weeks = [one.weeks[0]]
                let ran = Self.twoRounds(of: none) > 0 && Self.twoRounds(of: one) > 0
                exit(ran && Self.refusesToShorten(none) && Self.refusesToShorten(one) ? 0 : 1)
            }
        }

        @Test("Two days under one id, which Program.init accepts, survive every edit.")
        func everyEdit_onABlockWithOneDayIDTwice_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let valid = try EditAdv.fourDayProgram()
                let twin = DayTemplate(id: EditAdv.fourDayIDs[0], name: "Twin", tag: "TW")
                let doubled = try EditAdv.program(weeks: valid.weeks, days: valid.days + [twin, twin])
                exit(Self.twoRounds(of: doubled) > 0 ? 0 : 1)
            }
        }

        @Test("Two weeks under one id, which Program.init accepts, survive every edit.")
        func everyEdit_onABlockWithOneWeekIDTwice_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let valid = try EditAdv.fourDayProgram()
                let weeks = valid.weeks.map { Week(id: EditAdv.weekID(200), index: $0.index, schedule: $0.schedule) }
                let doubled = try EditAdv.program(weeks: weeks, days: valid.days)
                exit(Self.twoRounds(of: doubled) > 0 ? 0 : 1)
            }
        }

        @Test(
            "Weeks out of order, indices that are not their places and a schedule naming a lost day survive every edit."
        )
        func everyEdit_onABlockOutOfShape_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                var reversed = try EditAdv.fourDayProgram()
                reversed.weeks.reverse()
                var sparse = try EditAdv.fourDayProgram()
                for place in sparse.weeks.indices {
                    sparse.weeks[place].index = [0, -3, 40, Int.min, 0, 0, 7, Int.max][place]
                }
                var dangling = try EditAdv.fourDayProgram()
                dangling.days.removeAll()
                let ran = [reversed, sparse, dangling].map(Self.twoRounds).allSatisfy { $0 > 0 }
                exit(ran ? 0 : 1)
            }
        }
    }
#endif
