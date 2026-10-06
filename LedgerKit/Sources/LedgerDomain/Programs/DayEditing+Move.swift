import Foundation

// MARK: - Move (F11 criterion 10)

public extension DayEditing {
    /// "Move up" and "Move down", with a superset moving as one.
    ///
    /// Within its superset group the slot changes places with the member next to it on that side; the group
    /// keeps its place and its size. From the edge of its group (always, for a slot on its own) the whole
    /// group changes places with the group next to it, each keeping its members' order. At the day's edge
    /// nothing changes.
    ///
    /// Only the order of slots and their `isSupersetWithPrevious` flags can change, and who is in a superset
    /// with whom never does. Moving a group from its edge and then moving the same slot back does not
    /// restore the day: the second move changes its place inside the group.
    ///
    /// Product decision pending (F11 notes, "Decisions for Pete" 2): the other rule, in which a move carries
    /// one slot and can take it out of its superset, would replace this function alone.
    static func move(_ day: DayTemplate, slot: SlotID, _ direction: MoveDirection) -> DayTemplate {
        var moved = normalized(day)
        let slots = moved.slots
        var groups = SupersetRounds.groups(joiningPrevious: slots.map(\.isSupersetWithPrevious))
        guard let index = slots.firstIndex(where: { $0.id == slot }),
              let place = groups.firstIndex(where: { $0.contains(index) }),
              let member = groups[place].firstIndex(of: index)
        else {
            return moved
        }
        let side = direction == .downward ? 1 : -1
        if groups[place].indices.contains(member + side) {
            groups[place].swapAt(member, member + side)
        } else if groups.indices.contains(place + side) {
            groups.swapAt(place, place + side)
        }
        moved.slots = groups.flatMap { group in
            group.enumerated().map { position, slotIndex in
                var placed = slots[slotIndex]
                placed.isSupersetWithPrevious = position > 0
                return placed
            }
        }
        return moved
    }
}
