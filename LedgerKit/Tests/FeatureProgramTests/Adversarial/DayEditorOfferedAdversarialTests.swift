@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 1: move, superset, drop set and remove, offered only when they can do something
/// and doing what the brief's criteria 10 and 11 say (criterion 4 of the slice; product spec §3.4 e and f;
/// "Group-aware move, defined").
@Suite("Adversarial F11 S6 · move, superset, drop set and remove", .tags(.feature))
nonisolated struct DayEditorOfferedAdversarialTests {
    /// The brief's day [1, 2, 3A, 3B, 4] (pattern 0b0100), or another grouping of `count` slots.
    static func input(count: Int = 5, pattern: Int = 0b0100, open: Int? = nil) throws -> DayEditorInput {
        let (program, day) = try DayEditorModelAdversarialTests.day(count: count, pattern: pattern)
        return AdvDay.input(
            program, day: day.id, exercises: DayEditorModelAdversarialTests.exercises(),
            open: open.map { day.slots[$0].id }
        )
    }

    /// The rows as "index name", with "Exercise " left out: "3A 2".
    static func order(_ input: DayEditorInput) -> [String] {
        AdvDay.rows(input).map { "\($0.index) \($0.name.replacingOccurrences(of: "Exercise ", with: ""))" }
    }

    static func tapped(_ title: String, _ input: DayEditorInput) throws -> DayEditorInput {
        let panel = try #require(AdvDay.panel(input))
        let controls = panel.supersetActions + [panel.moveUp, panel.moveDown, panel.remove].compactMap(\.self)
        let control = try #require(controls.first { $0.title == title })
        return AdvDay.apply(control.action, to: input).input
    }

    @Test("Criterion 10: Move down on 2 carries it below the superset, and the panel stays open on it")
    func moveDown_onASoloRowAboveASuperset_passesTheWholeSuperset() throws {
        let input = try Self.input(open: 1)
        #expect(Self.order(input) == ["1 0", "2 1", "3A 2", "3B 3", "4 4"])
        let moved = try Self.tapped("Move down", input)
        #expect(Self.order(moved) == ["1 0", "2A 2", "2B 3", "3 1", "4 4"])
        #expect(moved.openSlot == input.openSlot)
        #expect(AdvDay.rows(moved).map(\.isOpen) == [false, false, false, true, false])
    }

    @Test("Criterion 10: Move down on 3A swaps it with 3B, and Move up on 3A carries the superset above 2")
    func move_insideAndFromTheEdgeOfASuperset_swapsOrCarries() throws {
        let input = try Self.input(open: 2)
        #expect(try Self.order(Self.tapped("Move down", input)) == ["1 0", "2 1", "3A 3", "3B 2", "4 4"])
        #expect(try Self.order(Self.tapped("Move up", input)) == ["1 0", "2A 2", "2B 3", "3 1", "4 4"])
        let flags = try Self.tapped("Move up", input).program.days[0].slots.map(\.isSupersetWithPrevious)
        #expect(flags == [false, false, true, false, false])
    }

    @Test(
        "Move up and Move down are offered exactly when DayEditing.move changes the day, in every grouping of up to six"
    )
    func move_isOfferedExactlyWhenItChangesTheDay() throws {
        var wrong: [String] = []
        var panels = 0
        for count in 1 ... 6 {
            for pattern in 0 ..< (1 << (count - 1)) {
                for open in 0 ..< count {
                    let input = try Self.input(count: count, pattern: pattern, open: open)
                    let day = try #require(AdvDay.day(input))
                    let panel = try #require(AdvDay.panel(input))
                    let slot = day.slots[open]
                    let canUp = DayEditing.move(day, slot: slot.id, .upward) != day
                    let canDown = DayEditing.move(day, slot: slot.id, .downward) != day
                    let joined = open > 0 && slot.isSupersetWithPrevious
                    let nextIsFree = open + 1 < count && !day.slots[open + 1].isSupersetWithPrevious
                    let titles = (joined ? ["Break out"] : []) + (nextIsFree ? ["Superset with next"] : [])
                    let isRight = (panel.moveUp != nil) == canUp && (panel.moveDown != nil) == canDown
                        && panel.supersetActions.map(\.title) == titles
                        && panel.moveUp?.title ?? "Move up" == "Move up"
                        && panel.moveDown?.title ?? "Move down" == "Move down"
                        && panel.remove.title == "Remove"
                    if !isRight {
                        wrong.append("\(count) slots, pattern \(pattern), open \(open): \(titles)")
                    }
                    panels += 1
                }
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(4))")
        #expect(panels == 321)
    }

    @Test("The first row has no Move up, the last no Move down, and a day of one exercise neither")
    func move_atTheEdgesOfTheDay_isAbsent() throws {
        #expect(try AdvDay.panel(Self.input(open: 0))?.moveUp == nil)
        #expect(try AdvDay.panel(Self.input(open: 0))?.moveDown != nil)
        #expect(try AdvDay.panel(Self.input(open: 4))?.moveDown == nil)
        #expect(try AdvDay.panel(Self.input(open: 4))?.moveUp != nil)
        let alone = try #require(try AdvDay.panel(Self.input(count: 1, pattern: 0, open: 0)))
        #expect(alone.moveUp == nil && alone.moveDown == nil)
        #expect(alone.supersetActions.isEmpty)
        // The first and the last member of a day that is one superset: inside it they still swap.
        #expect(try AdvDay.panel(Self.input(count: 2, pattern: 1, open: 0))?.moveUp == nil)
        #expect(try AdvDay.panel(Self.input(count: 2, pattern: 1, open: 0))?.moveDown != nil)
        #expect(try AdvDay.panel(Self.input(count: 2, pattern: 1, open: 1))?.moveDown == nil)
    }

    @Test(
        "Criterion 11: Superset with next on 4 of 5 joins 5, the header reads rest after B; Break out undoes it"
    )
    func supersetWithNext_thenBreakOut_readAsTheBrief() throws {
        let input = try Self.input(count: 5, pattern: 0, open: 3)
        #expect(AdvDay.panel(input)?.supersetActions.map(\.title) == ["Superset with next"])
        let joined = try Self.tapped("Superset with next", input)
        #expect(joined.program.days[0].slots.map(\.isSupersetWithPrevious) == [false, false, false, false, true])
        #expect(joined.openSlot == nil)
        #expect(Self.order(joined) == ["1 0", "2 1", "3 2", "4A 3", "4B 4"])
        let content = try #require(AdvDay.content(joined))
        #expect(content.groups.last?.header?.note == "2 exercises back to back · rest after B")
        #expect(content.groups.last?.rows.map(\.sub) == [
            "Barbell · +5/wk · RPE 8 · no rest", "Barbell · +5/wk · RPE 8 · 1:30 rest"
        ])
        var onB = joined
        onB.openSlot = joined.program.days[0].slots[4].id
        #expect(AdvDay.panel(onB)?.supersetActions.map(\.title) == ["Break out"])
        let broken = try Self.tapped("Break out", onB)
        #expect(broken.program.days[0].slots.map(\.isSupersetWithPrevious) == Array(repeating: false, count: 5))
        #expect(broken.openSlot == nil)
        #expect(AdvDay.content(broken)?.groups.allSatisfy { $0.header == nil } == true)
    }

    @Test("Break out and Superset with next both show on the last of a superset that another exercise follows")
    func bothSupersetActions_showOnTheLastMemberThatHasANext() throws {
        let input = try Self.input(open: 3)
        #expect(AdvDay.panel(input)?.supersetActions.map(\.title) == ["Break out", "Superset with next"])
        #expect(try Self.order(Self.tapped("Break out", input)) == ["1 0", "2 1", "3 2", "4 3", "5 4"])
        #expect(try Self.order(Self.tapped("Superset with next", input)) == ["1 0", "2 1", "3A 2", "3B 3", "3C 4"])
        // The first of a superset has neither; a solo row before a superset joins it (behaviour 9).
        #expect(try AdvDay.panel(Self.input(open: 2))?.supersetActions.isEmpty == true)
        let merged = try Self.tapped("Superset with next", Self.input(open: 1))
        #expect(Self.order(merged) == ["1 0", "2A 1", "2B 2", "2C 3", "3 4"])
        // Break out in the middle of [A, B, C] leaves B and C together (behaviour 8).
        let middle = try Self.tapped("Break out", Self.input(count: 3, pattern: 0b11, open: 1))
        #expect(Self.order(middle) == ["1 0", "2A 1", "2B 2"])
    }

    @Test("The drop-set switch names the other state, and the row, the note and the sets follow it")
    func dropSet_switched_isDrawnEverywhere() throws {
        let input = try Self.input(count: 2, pattern: 0, open: 0)
        let off = try #require(AdvDay.panel(input)?.details?.dropSet)
        let open = try #require(input.openSlot)
        #expect(off.isOn == false)
        #expect(AdvDay.slotEdit(of: off.action) == .setDropSet(true, slot: open))
        #expect(AdvDay.content(input)?.header.meta == "Week 1 · 2 exercises · 6 sets · ~13 min")
        let turnedOn = AdvDay.apply(off.action, to: input).input
        let dropSet = try #require(AdvDay.panel(turnedOn)?.details?.dropSet)
        #expect(dropSet.isOn)
        #expect(dropSet.note == "One extra set at −15%, straight after the last working set.")
        #expect(AdvDay.slotEdit(of: dropSet.action) == .setDropSet(false, slot: open))
        #expect(AdvDay.rows(turnedOn).map(\.sub) == [
            "Barbell · +5/wk · drop · RPE 8 · 1:30 rest", "Barbell · +5/wk · RPE 8 · 1:30 rest"
        ])
        #expect(AdvDay.rows(turnedOn).map(\.hasDropSet) == [true, false])
        #expect(AdvDay.content(turnedOn)?.header.meta == "Week 1 · 2 exercises · 7 sets · ~15 min")
        let again = AdvDay.apply(off.action, to: turnedOn).input
        let isSame = again.program == turnedOn.program
        #expect(isSame)
    }

    @Test("Remove on the first of a superset leaves the next to lead, and the removed slot's panel is gone")
    func remove_onTheFirstOfASuperset_leavesTheNextToLead() throws {
        let input = try Self.input(open: 2)
        let removed = try Self.tapped("Remove", input)
        #expect(Self.order(removed) == ["1 0", "2 1", "3 3", "4 4"])
        #expect(AdvDay.rows(removed).allSatisfy { $0.panel == nil && !$0.isOpen })
        #expect(AdvDay.content(removed)?.header.meta.hasPrefix("Week 1 · 4 exercises · 12 sets") == true)
        var last = try Self.input(count: 1, pattern: 0, open: 0)
        last = try Self.tapped("Remove", last)
        #expect(AdvDay.content(last)?.groups.isEmpty == true)
    }
}
