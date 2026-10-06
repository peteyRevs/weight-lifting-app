import Foundation
@testable import LedgerDomain
import Testing

/// Slice criterion 8's supersets and criterion 6's removal, exhaustively: every day of 0 to 7 slots with
/// every pattern of flags (the first slot's flag set as well, a day not in normal form), every slot. The
/// expected day is worked on the superset groups by `DayModel`; the flags are derived from the groups.
@Suite("DayEditing supersets (adversarial)", .tags(.domain))
struct DayEditingSupersetAdversarialTests {
    /// Every day of 0 to 7 slots with every flag pattern: 255 days.
    static func days() throws -> [DayTemplate] {
        try (0 ... 7).flatMap { count in
            try EditAdv.flagPatterns(count: count).map { try EditAdv.day(flags: $0) }
        }
    }

    /// The model of `day`'s groups alone (its rows are not needed to join, break out or remove).
    static func model(_ day: DayTemplate) -> DayModel {
        var model = DayModel(units: .lb)
        model.groups = EditAdv.groups(day.slots)
        return model
    }

    /// What is wrong with `result` when the day must now have `groups`, or `nil`: the order, the flags
    /// (normal form), `groups(of:)`, and every other field of every slot as it was in `day`.
    static func problem(_ result: DayTemplate, expected groups: [[SlotID]], from day: DayTemplate) -> String? {
        let orderHolds = result.slots.map(\.id) == groups.flatMap(\.self)
        if !orderHolds || result.slots.map(\.isSupersetWithPrevious) != EditAdv.flags(groups) {
            return "gave [\(EditAdv.brief(result.slots))]"
        }
        if DayEditing.groups(of: result) != groups {
            return "groups(of:) disagrees with the flags"
        }
        let original = Dictionary(day.slots.map { ($0.id, EditAdv.unflagged($0)) }) { first, _ in first }
        if !result.slots.allSatisfy({ original[$0.id] == EditAdv.unflagged($0) }) {
            return "a field other than the flag changed"
        }
        return nil
    }
}

extension DayEditingSupersetAdversarialTests {
    @Test("groups(of:) is the plan's grouping for every day, and ignores the first slot's flag.")
    func groups_everyDay_matchTheDefinition() throws {
        var tally = Tally()
        for day in try Self.days() {
            tally.check(DayEditing.groups(of: day) == EditAdv.groups(day.slots), "[\(EditAdv.brief(day.slots))]")
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 255)
    }

    @Test(
        "Joining and breaking out every slot of every day gives the model's groups in normal form and nothing else."
    )
    func setSuperset_everySlotOfEveryDay_matchesTheModel() throws {
        var tally = Tally()
        for day in try Self.days() {
            for slot in day.slots {
                for isOn in [true, false] {
                    var model = Self.model(day)
                    model.setSuperset(isOn, slot.id)
                    let result = DayEditing.setSuperset(isOn, slot: slot.id, in: day)
                    let problem = Self.problem(result, expected: model.groups, from: day)
                    let note = "[\(EditAdv.brief(day.slots))] superset \(isOn) on \(EditAdv.number(slot.id.rawValue))"
                    tally.check(problem == nil, "\(note) \(problem ?? "")")
                    let again = DayEditing.setSuperset(isOn, slot: slot.id, in: result) == result
                    tally.check(again, "\(note): a second time changed the day")
                }
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 1538 * 4)
    }

    @Test(
        "Removing every slot of every day leaves the other members of its group together, and the next member leading."
    )
    func removeSlot_everySlotOfEveryDay_matchesTheModel() throws {
        var tally = Tally()
        for day in try Self.days() {
            for slot in day.slots {
                var model = Self.model(day)
                model.remove(slot.id)
                let result = DayEditing.removeSlot(day, slot: slot.id)
                let problem = Self.problem(result, expected: model.groups, from: day)
                tally.check(
                    problem == nil,
                    "[\(EditAdv.brief(day.slots))] remove \(EditAdv.number(slot.id.rawValue)) \(problem ?? "")"
                )
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 1538)
    }

    @Test("An id the day does not hold: every function returns the day in normal form with nothing else changed.")
    func unknownSlot_everyFunction_returnsTheDayInNormalForm() throws {
        let unknown = EditAdv.slotID(999)
        var tally = Tally()
        for day in try Self.days() {
            let groups = EditAdv.groups(day.slots)
            let results = [
                DayEditing.removeSlot(day, slot: unknown),
                DayEditing.setSuperset(true, slot: unknown, in: day),
                DayEditing.setSuperset(false, slot: unknown, in: day),
                DayEditing.setDropSet(true, slot: unknown, in: day),
                DayEditing.setProgression(.double, slot: unknown, in: day),
                DayEditing.set(.reps(30), slot: unknown, in: day),
                DayEditing.set(.startLoad(.zero), slot: unknown, in: day),
                DayEditing.move(day, slot: unknown, .upward),
                DayEditing.move(day, slot: unknown, .downward),
                DayEditing.addSlots(day, [])
            ]
            for (place, result) in results.enumerated() {
                let problem = Self.problem(result, expected: groups, from: day)
                tally.check(problem == nil, "[\(EditAdv.brief(day.slots))] function \(place) \(problem ?? "")")
                let isNormal = day.slots.first?.isSupersetWithPrevious != true
                tally.check(
                    !isNormal || result == day,
                    "[\(EditAdv.brief(day.slots))] function \(place) changed the day"
                )
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 255 * 20)
    }

    @Test("Slots that arrive joined: the first slot of an empty day leads, and one added to a day joins its last slot.")
    func addSlots_arrivingJoined_keepsNormalForm() throws {
        let empty = DayTemplate(id: EditAdv.dayID(4000), name: "New day", tag: "D5")
        let arriving = try [true, true, false, true].enumerated().map { index, joined in
            try EditAdv.distinctSlot(index, id: 6000 + index, joined: joined)
        }
        let first = DayEditing.addSlots(empty, [arriving[0]])
        #expect(first.slots.map(\.isSupersetWithPrevious) == [false])
        let four = DayEditing.addSlots(empty, arriving)
        #expect(four.slots.map(\.isSupersetWithPrevious) == [false, true, false, true])
        #expect(DayEditing.groups(of: four).map(\.count) == [2, 2])
        let day = try EditAdv.day(flags: [false, true])
        let grown = DayEditing.addSlots(day, [arriving[0]])
        #expect(DayEditing.groups(of: grown).map(\.count) == [3])
        #expect(EditAdv.rejection(of: four.slots) == nil)
    }

    @Test("A day that arrives with its first slot joined is read as its normal form by every edit of another slot.")
    func firstSlotJoined_anyEdit_returnsNormalForm() throws {
        let day = try EditAdv.day(flags: [true, true, false])
        let last = EditAdv.slotID(5002)
        let results = try [
            DayEditing.set(.sets(4), slot: last, in: day),
            DayEditing.setDropSet(true, slot: last, in: day),
            DayEditing.setProgression(.fixed, slot: last, in: day),
            DayEditing.addSlots(day, [EditAdv.distinctSlot(5, id: 6000, joined: false)])
        ]
        for (place, result) in results.enumerated() {
            #expect(result.slots.first?.isSupersetWithPrevious == false, "function \(place)")
            #expect(
                result.slots.dropFirst().prefix(2).map(\.isSupersetWithPrevious) == [true, false],
                "function \(place)"
            )
        }
    }
}
