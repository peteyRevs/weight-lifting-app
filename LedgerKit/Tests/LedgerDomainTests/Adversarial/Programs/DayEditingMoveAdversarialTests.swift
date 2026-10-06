import Foundation
@testable import LedgerDomain
import Testing

/// Slice criterion 9: "Group-aware move, defined" and its six properties, exhaustively. Every day of 0 to 8
/// slots with every pattern of flags (511 days, the first slot's flag set as well), every slot, both
/// directions: 7,172 moves, each compared with `EditAdv.moved`, the definition applied to the groups.
@Suite("DayEditing move (adversarial)", .tags(.domain))
struct DayEditingMoveAdversarialTests {
    /// How the sequence of groups changed.
    enum Change {
        case nothing, membersSwapped, groupsSwapped, somethingElse
    }

    /// One move of the exhaustive set.
    struct Case {
        let day: DayTemplate
        let slot: SlotID
        let direction: MoveDirection

        var groups: [[SlotID]] {
            EditAdv.groups(day.slots)
        }

        var opposite: MoveDirection {
            direction == .upward ? .downward : .upward
        }

        var note: String {
            "[\(EditAdv.brief(day.slots))] \(EditAdv.number(slot.rawValue)) \(direction)"
        }
    }

    static func cases() throws -> [Case] {
        try (0 ... 8).flatMap { count in
            try EditAdv.flagPatterns(count: count).flatMap { flags in
                let day = try EditAdv.day(flags: flags)
                return day.slots.flatMap { slot in
                    [MoveDirection.upward, .downward].map { Case(day: day, slot: slot.id, direction: $0) }
                }
            }
        }
    }

    /// Whether `after` is `before` with two neighbours changed over.
    static func isNeighbourSwap<Element: Equatable>(_ before: [Element], _ after: [Element]) -> Bool {
        guard before.count == after.count else {
            return false
        }
        let differing = before.indices.filter { before[$0] != after[$0] }
        guard differing.count == 2, differing[1] == differing[0] + 1 else {
            return false
        }
        return before[differing[0]] == after[differing[1]] && before[differing[1]] == after[differing[0]]
    }

    /// Property 4, without the reference move: nothing, one swap of two neighbouring members inside one
    /// group, or one swap of two neighbouring groups.
    static func change(from before: [[SlotID]], to after: [[SlotID]]) -> Change {
        if before == after {
            return .nothing
        }
        if isNeighbourSwap(before, after) {
            return .groupsSwapped
        }
        let differing = before.indices.filter { !after.indices.contains($0) || before[$0] != after[$0] }
        if before.count == after.count, differing.count == 1, isNeighbourSwap(
            before[differing[0]],
            after[differing[0]]
        ) {
            return .membersSwapped
        }
        return .somethingElse
    }
}

extension DayEditingMoveAdversarialTests {
    @Test("Every move of every day of up to eight slots gives the order and the flags of the definition.")
    func move_everyCase_matchesTheDefinition() throws {
        var tally = Tally()
        for item in try Self.cases() {
            let expected = EditAdv.moved(item.groups, slot: item.slot, item.direction)
            let result = DayEditing.move(item.day, slot: item.slot, item.direction)
            let holds = result.slots.map(\.id) == expected.flatMap(\.self)
                && result.slots.map(\.isSupersetWithPrevious) == EditAdv.flags(expected)
            tally.check(holds, "\(item.note) gave [\(EditAdv.brief(result.slots))]")
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 7172)
    }

    @Test(
        "Properties 1 to 3: the same slots each once, only flags changed, normal form, and the same supersets as sets."
    )
    func move_everyCase_keepsSlotsNormalFormAndMembership() throws {
        var tally = Tally()
        for item in try Self.cases() {
            let result = DayEditing.move(item.day, slot: item.slot, item.direction)
            let before = Dictionary(item.day.slots.map { ($0.id, EditAdv.unflagged($0)) }) { first, _ in first }
            let sameSlots = result.slots.count == item.day.slots.count
                && Set(result.slots.map(\.id)).count == result.slots.count
                && result.slots.allSatisfy { before[$0.id] == EditAdv.unflagged($0) }
            tally.check(sameSlots, "\(item.note): a slot was lost, doubled or changed")
            tally.check(result.slots.first?.isSupersetWithPrevious == false, "\(item.note): not in normal form")
            let membership = Set(DayEditing.groups(of: result).map(Set.init)) == Set(item.groups.map(Set.init))
            tally.check(membership, "\(item.note): who is in a superset with whom changed")
            let named = result.id == item.day.id && result.name == item.day.name && result.tag == item.day.tag
            tally.check(named, "\(item.note): the day's id, name or tag changed")
        }
        #expect(tally.passed, tally.summary)
    }

    @Test(
        "Property 4: a move changes nothing, swaps two neighbours inside a group, or swaps two neighbouring groups."
    )
    func move_everyCase_changesByOneSwapAtMost() throws {
        var tally = Tally()
        var seen: [Change: Int] = [:]
        for item in try Self.cases() {
            let result = DayEditing.move(item.day, slot: item.slot, item.direction)
            let change = Self.change(from: item.groups, to: EditAdv.groups(result.slots))
            seen[change, default: 0] += 1
            tally.check(change != .somethingElse, "\(item.note) gave [\(EditAdv.brief(result.slots))]")
        }
        #expect(tally.passed, tally.summary)
        #expect(seen[.nothing] == 1020, "the first slot up and the last slot down, in each of the 510 days with a slot")
        #expect(seen[.membersSwapped, default: 0] > 0)
        #expect(seen[.groupsSwapped, default: 0] > 0)
    }

    @Test(
        "Property 5: the first member of the first group up and the last member of the last group down return the day."
    )
    func move_atTheDaysEdge_returnsTheDay() throws {
        var tally = Tally()
        for item in try Self.cases() {
            let isEdge = item.direction == .upward ? item.day.slots.first?.id == item.slot : item.day.slots.last?
                .id == item.slot
            guard isEdge else {
                continue
            }
            let result = DayEditing.move(item.day, slot: item.slot, item.direction)
            let sameOrder = result.slots.map(\.id) == item.day.slots.map(\.id)
            let sameFlags = result.slots.map(\.isSupersetWithPrevious) == EditAdv.flags(item.groups)
            tally.check(sameOrder && sameFlags, "\(item.note) gave [\(EditAdv.brief(result.slots))]")
            let isNormal = item.day.slots.first?.isSupersetWithPrevious == false
            tally.check(!isNormal || result == item.day, "\(item.note): the day changed")
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 1020 * 2)
    }

    @Test(
        "Property 6: the opposite move restores a swap inside a group and a lone slot, never a group moved as one."
    )
    func move_thenTheOpposite_restoresOrNot() throws {
        var tally = Tally()
        var unrestored = 0
        for item in try Self.cases() {
            let result = DayEditing.move(item.day, slot: item.slot, item.direction)
            let change = Self.change(from: item.groups, to: EditAdv.groups(result.slots))
            guard change == .membersSwapped || change == .groupsSwapped else {
                continue
            }
            let back = DayEditing.move(result, slot: item.slot, item.opposite)
            let restored = EditAdv.groups(back.slots) == item.groups
            let alone = item.groups.first { $0.contains(item.slot) }?.count == 1
            let mustRestore = change == .membersSwapped || alone
            unrestored += mustRestore ? 0 : 1
            tally.check(restored == mustRestore, "\(item.note), then back: [\(EditAdv.brief(back.slots))]")
        }
        #expect(tally.passed, tally.summary)
        #expect(unrestored > 0, "the documented case, a group of two or more moved from its edge, was never met")
    }
}
