import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criterion 9: "Move up" and "Move down" with a superset moving as one ("Group-aware move,
/// defined" in the F11 notes). Days are written as their groups: `[[1], [2], [3, 4], [5]]` reads 1, 2, 3A,
/// 3B, 4 on screen.
@Suite("DayEditing · move", .tags(.domain))
struct DayEditingMoveTests {
    private typealias Support = EditingSupport

    struct Row: Sendable, CustomStringConvertible {
        let description: String
        let joined: [Bool]
        let slot: Int
        let direction: MoveDirection
        let groups: [[Int]]

        static let criterionTen = [false, false, false, true, false]

        static let all: [Row] = [
            Row(
                description: "a slot on its own passes the whole superset below it",
                joined: criterionTen, slot: 2, direction: .downward, groups: [[1], [3, 4], [2], [5]]
            ),
            Row(
                description: "inside a superset, the two members change places",
                joined: criterionTen, slot: 3, direction: .downward, groups: [[1], [2], [4, 3], [5]]
            ),
            Row(
                description: "from the top edge of a superset, the superset goes above the slot before it",
                joined: criterionTen, slot: 3, direction: .upward, groups: [[1], [3, 4], [2], [5]]
            ),
            Row(
                description: "from the bottom edge of a superset, the superset goes below the slot after it",
                joined: criterionTen, slot: 4, direction: .downward, groups: [[1], [2], [5], [3, 4]]
            ),
            Row(
                description: "the last member moves up inside its superset",
                joined: criterionTen, slot: 4, direction: .upward, groups: [[1], [2], [4, 3], [5]]
            ),
            Row(
                description: "a slot on its own passes the whole superset above it",
                joined: criterionTen, slot: 5, direction: .upward, groups: [[1], [2], [5], [3, 4]]
            ),
            Row(
                description: "two slots on their own change places",
                joined: criterionTen, slot: 1, direction: .downward, groups: [[2], [1], [3, 4], [5]]
            ),
            Row(
                description: "the first slot of the day does not move up",
                joined: criterionTen, slot: 1, direction: .upward, groups: [[1], [2], [3, 4], [5]]
            ),
            Row(
                description: "the last slot of the day does not move down",
                joined: criterionTen, slot: 5, direction: .downward, groups: [[1], [2], [3, 4], [5]]
            ),
            Row(
                description: "the middle of three moves down inside the superset",
                joined: [false, true, true], slot: 2, direction: .downward, groups: [[1, 3, 2]]
            ),
            Row(
                description: "the middle of three moves up and leads the superset",
                joined: [false, true, true], slot: 2, direction: .upward, groups: [[2, 1, 3]]
            ),
            Row(
                description: "a superset that is the whole day stays when moved from its bottom edge",
                joined: [false, true, true], slot: 3, direction: .downward, groups: [[1, 2, 3]]
            ),
            Row(
                description: "a superset that is the whole day stays when moved from its top edge",
                joined: [false, true, true], slot: 1, direction: .upward, groups: [[1, 2, 3]]
            ),
            Row(
                description: "a superset passes another superset as one",
                joined: [false, true, false, true, true], slot: 2, direction: .downward, groups: [[3, 4, 5], [1, 2]]
            ),
            Row(
                description: "a superset passes another superset upwards as one",
                joined: [false, true, false, true, true], slot: 3, direction: .upward, groups: [[3, 4, 5], [1, 2]]
            )
        ]
    }

    /// The flags a day in normal form has for these groups: false for each group's first slot, true after.
    private func flags(for groups: [[Int]]) -> [Bool] {
        groups.flatMap { group in group.indices.map { $0 > 0 } }
    }

    @Test("A superset moves as one, and a member moves inside it (F11 criterion 10)", arguments: Row.all)
    func move_table(row: Row) throws {
        let day = try Support.day(joined: row.joined)
        let moved = DayEditing.move(day, slot: Support.slot(row.slot), row.direction)
        #expect(Support.groups(moved) == row.groups)
        #expect(Support.ids(moved) == Array(row.groups.joined()))
        #expect(Support.flags(moved) == flags(for: row.groups))
        #expect(Support.faults(in: moved).isEmpty)
    }

    @Test("\"Move down\" on slot 2 of 1, 2, 3A, 3B, 4 puts it below the superset (F11 criterion 10)")
    func move_soloSlot_passesTheWholeGroup() throws {
        let day = try Support.day(joined: Row.criterionTen)
        let moved = DayEditing.move(day, slot: Support.slot(2), .downward)
        #expect(Support.ids(moved) == [1, 3, 4, 2, 5])
        #expect(Support.flags(moved) == [false, false, true, false, false])
    }

    @Test("\"Move down\" on 3A swaps it with 3B, and the letters follow the new order (F11 criterion 10)")
    func move_insideAGroup_swapsTheTwoMembers() throws {
        let day = try Support.day(joined: Row.criterionTen)
        let moved = DayEditing.move(day, slot: Support.slot(3), .downward)
        #expect(Support.ids(moved) == [1, 2, 4, 3, 5])
        #expect(Support.flags(moved) == [false, false, false, true, false], "slot 4 now leads; slot 3 is joined to it")
        #expect(Support.difference(DayEditing.move(moved, slot: Support.slot(3), .upward), day).isEmpty, "and back")
    }

    @Test("\"Move up\" on 3A, the first of its superset, carries the superset above slot 2 (F11 criterion 10)")
    func move_fromAGroupsEdge_carriesTheGroup() throws {
        let day = try Support.day(joined: Row.criterionTen)
        let moved = DayEditing.move(day, slot: Support.slot(3), .upward)
        #expect(Support.ids(moved) == [1, 3, 4, 2, 5])
        #expect(Support.flags(moved) == [false, false, true, false, false])
    }

    @Test("Only the order and the superset flags change: every slot keeps its numbers, misses and exercise")
    func move_changesOnlyOrderAndFlags() throws {
        let upperA = try Fixtures.upperA()
        let moved = DayEditing.move(upperA, slot: Support.slot(303), .downward)
        #expect(Support.ids(moved) == [301, 302, 304, 305, 303])
        #expect(Support.flags(moved) == [false, false, false, true, false])
        for slot in upperA.slots {
            let after = try #require(moved.slots.first { $0.id == slot.id })
            #expect(Support.changedFields(slot, after).isEmpty, "slot \(Support.numbers([slot.id.rawValue]))")
        }
        let inside = DayEditing.move(upperA, slot: Support.slot(305), .upward)
        #expect(Support.ids(inside) == [301, 302, 303, 305, 304])
        #expect(Support.changedFields(upperA.slots[4], inside.slots[3]) == ["superset"])
        #expect(Support.changedFields(upperA.slots[3], inside.slots[4]) == ["superset"])
    }

    @Test("Moving a superset from its edge and then the same slot back does not restore the day (decision 2's oddity)")
    func move_groupFromItsEdge_thenBack_swapsInsideTheGroup() throws {
        let day = try Support.day(joined: [false, true, false])
        let down = DayEditing.move(day, slot: Support.slot(2), .downward)
        #expect(Support.groups(down) == [[3], [1, 2]])
        let back = DayEditing.move(down, slot: Support.slot(2), .upward)
        #expect(Support.groups(back) == [[3], [2, 1]], "2B moved up inside its superset, not back above slot 3")
    }

    @Test("A slot the day does not hold, and an empty day, come back unchanged in both directions")
    func move_unknownSlotOrEmptyDay_changesNothing() throws {
        let day = try Support.day(joined: Row.criterionTen)
        let empty = DayTemplate(id: day.id, name: "New day", tag: "D5")
        for direction in [MoveDirection.upward, .downward] {
            #expect(Support.difference(DayEditing.move(day, slot: SlotID(Support.unknown), direction), day).isEmpty)
            #expect(Support.difference(DayEditing.move(empty, slot: Support.slot(1), direction), empty).isEmpty)
        }
    }

    @Test("A day whose first slot arrives joined is moved as its normal form")
    func move_firstSlotArrivesJoined_isReadAsItsNormalForm() throws {
        let arriving = try Support.day(joined: [true, true, false])
        let moved = DayEditing.move(arriving, slot: Support.slot(1), .downward)
        #expect(Support.groups(moved) == [[2, 1], [3]])
        #expect(Support.flags(moved) == [false, true, false])
        let unmoved = DayEditing.move(arriving, slot: Support.slot(1), .upward)
        #expect(
            Support.flags(unmoved) == [false, true, false],
            "nothing moves, and the first slot is joined to nothing"
        )
        #expect(Support.ids(unmoved) == [1, 2, 3])
    }
}
