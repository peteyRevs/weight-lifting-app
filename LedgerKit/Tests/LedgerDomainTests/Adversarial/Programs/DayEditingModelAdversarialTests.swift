import Foundation
@testable import LedgerDomain
import Testing

/// Slice criteria 1, 6 to 9 and 12 over seeded sequences of every `DayEditing` function: after every edit
/// the day is the one `DayModel` expects (order, superset flags, every field of every slot), it is in normal
/// form, `Slot.init` accepts each slot, and no slot that was there before has other misses or another
/// exercise.
@Suite("DayEditing against a model (adversarial)", .tags(.domain, .property))
struct DayEditingModelAdversarialTests {
    /// A day of 0 to 6 valid slots with seeded superset flags, in pounds or in kilograms.
    static func start(using generator: inout SeededGenerator) -> DayModel {
        var model = DayModel(units: Units.allCases.randomElement(using: &generator) ?? .lb)
        let rows = (0 ..< Int.random(in: 0 ... 6, using: &generator)).map { offset in
            SlotRow.random(id: 5000 + offset, using: &generator)
        }
        model.add(rows, joined: rows.map { _ in Bool.random(using: &generator) })
        return model
    }

    /// What is wrong with `day` after an edit of `before`, or `nil`.
    static func problem(_ day: DayTemplate, model: DayModel, before: DayTemplate) -> String? {
        if let difference = model.difference(from: day) {
            return difference
        }
        if day.slots.first?.isSupersetWithPrevious == true {
            return "the day's first slot is joined to a previous one"
        }
        if let rejection = EditAdv.rejection(of: day.slots) {
            return rejection
        }
        if day.id != before.id || day.name != before.name || day.tag != before.tag {
            return "the day's id, name or tag changed"
        }
        return written(day.slots, before: before.slots)
    }

    /// Slice criterion 12: a slot of `before` that is still there with other misses or another exercise.
    static func written(_ slots: [Slot], before: [Slot]) -> String? {
        let old = Dictionary(before.map { ($0.id, $0) }) { first, _ in first }
        let changed = slots.first { slot in
            old[slot.id].map { $0.exerciseID != slot.exerciseID || $0.misses != slot.misses } ?? false
        }
        return changed.map { "the misses or the exercise of slot \(EditAdv.number($0.id.rawValue)) were written" }
    }
}

extension DayEditingModelAdversarialTests {
    @Test("Eighty seeded edits of a day give the model's day at every step.", arguments: PropertySeed.all)
    func editSequence_matchesTheModelAtEveryStep(seed: PropertySeed) throws {
        var generator = seed.generator
        var model = Self.start(using: &generator)
        var day = try model.day()
        for step in 0 ..< 80 {
            let edit = DayEdit.random(ids: model.ids, step: step, using: &generator)
            let before = day
            edit.apply(to: &model)
            day = try edit.applied(to: day, units: model.units)
            if let problem = Self.problem(day, model: model, before: before) {
                Issue.record("\(seed), \(model.units), step \(step), \(edit): \(problem)")
                return
            }
        }
        let decoded = try Adversarial.roundTrip(day) == day
        #expect(decoded, "\(seed): the edited day does not survive encoding and decoding")
    }

    @Test(
        "An edit applied twice from the same day gives the same day: the functions are pure.",
        arguments: PropertySeed.all.prefix(40)
    )
    func edit_appliedTwice_givesTheSameDay(seed: PropertySeed) throws {
        var generator = seed.generator
        var model = Self.start(using: &generator)
        var day = try model.day()
        for step in 0 ..< 30 {
            let edit = DayEdit.random(ids: model.ids, step: step, using: &generator)
            edit.apply(to: &model)
            let first = try edit.applied(to: day, units: model.units)
            let second = try edit.applied(to: day, units: model.units)
            let same = first == second
            #expect(same, "\(seed), step \(step), \(edit)")
            day = first
        }
    }

    @Test(
        "A slot added under an id the day holds is left out, and the slot the day holds keeps its exercise and misses."
    )
    func addSlots_idTheDayHolds_leavesTheDaysSlot() throws {
        let day = try EditAdv.day(flags: [false, true, false])
        var impostor = try EditAdv.distinctSlot(7, id: 5001, joined: false)
        impostor.misses = [6]
        let fresh = try EditAdv.distinctSlot(8, id: 5008, joined: false)
        let added = DayEditing.addSlots(day, [impostor, fresh])
        #expect(added.slots.map(\.id) == [5000, 5001, 5002, 5008].map(EditAdv.slotID))
        let untouched = Array(added.slots.prefix(3)) == day.slots
        #expect(untouched)
        let appended = added.slots.last == fresh
        #expect(appended)
    }

    @Test("The same new slot twice in one call is added once: a day never holds an id twice.")
    func addSlots_sameSlotTwiceInOneCall_addsItOnce() throws {
        let day = try EditAdv.day(flags: [false, false])
        let fresh = try EditAdv.distinctSlot(8, id: 5008, joined: false)
        var twin = try EditAdv.distinctSlot(9, id: 5008, joined: false)
        twin.misses = [1]
        let added = DayEditing.addSlots(day, [fresh, twin, fresh])
        #expect(added.slots.map { EditAdv.number($0.id.rawValue) } == [5000, 5001, 5008])
    }

    @Test("Adding no slots, or only slots the day holds, changes nothing.")
    func addSlots_nothingNew_changesNothing() throws {
        let day = try EditAdv.day(flags: [false, true, false])
        let none = DayEditing.addSlots(day, []) == day
        #expect(none)
        let held = DayEditing.addSlots(day, day.slots.reversed()) == day
        #expect(held)
    }
}
