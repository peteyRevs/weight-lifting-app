import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criteria 6 and 8: slots added and removed, progression, drop set, superset, and the normal
/// form's rules for each. The fields are in `DayEditingFieldsTests`, the start load's stepper in
/// `DayEditingStartLoadTests`, the move in `DayEditingMoveTests`, totality in `DayEditingNormalFormTests`.
@Suite("DayEditing", .tags(.domain))
struct DayEditingTests {
    private typealias Support = EditingSupport

    let upperA: DayTemplate
    let newID = SlotID(Fixtures.uuid(900))

    init() throws {
        upperA = try Fixtures.upperA()
    }

    private func newSlot(_ number: Int, _ exercise: Exercise = Fixtures.bench) throws -> Slot {
        try DayEditing.newSlot(id: Support.slot(number), exercise: exercise, units: .lb, defaultRest: .defaultRest)
    }

    private func custom(_ loads: [Units: Weight]) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(40)),
            name: "Custom Press",
            shortName: "CUSTOM",
            equipment: .dumbbell,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: loads,
            isCustom: true
        )
    }

    // MARK: - newSlot (rule 7, F11 criterion 12)

    @Test("A picked exercise becomes 3 × 8, top 10, RPE 8, linear, the default rest and its start load (rule 7)")
    func newSlot_hasRule7Defaults() throws {
        let slot = try DayEditing.newSlot(id: newID, exercise: Fixtures.bench, units: .lb, defaultRest: .defaultRest)
        #expect(slot.id == newID)
        #expect(slot.exerciseID == Fixtures.bench.id)
        let numbers = [slot.sets, slot.reps, slot.repsHi, slot.rest.seconds, slot.dropSets]
        #expect(numbers == [3, 8, 10, 90, 0], "sets, reps, top of range, rest, drop sets")
        #expect(slot.rpe.value == 8)
        #expect(slot.progression == .linear)
        #expect(slot.startLoad == .pounds(180))
        #expect(slot.step == nil, "the step stays the equipment's, in whatever unit is shown")
        #expect(!slot.isSupersetWithPrevious)
        #expect(slot.misses.isEmpty)
        let accepted = try Support.rebuilt(slot) == slot
        #expect(accepted, "Slot.init accepts it as it is")
    }

    @Test("The start load is the exercise's in the lifter's unit, and the rest is the lifter's default")
    func newSlot_kilogramsAndAnotherDefaultRest() throws {
        let rest = try Fixtures.rest(120)
        let slot = try DayEditing.newSlot(id: newID, exercise: Fixtures.inclineDB, units: .kg, defaultRest: rest)
        #expect(slot.startLoad == .kilograms(22.5))
        #expect(slot.rest.seconds == 120)
    }

    @Test("A custom exercise with one unit's load gives the other unit's on its step; with none, zero")
    func newSlot_exerciseWithOneUnitOrNone_stillHasAStartLoad() throws {
        let poundsOnly = custom([.lb: .pounds(100)])
        let inKilograms = try DayEditing.newSlot(id: newID, exercise: poundsOnly, units: .kg, defaultRest: .defaultRest)
        #expect(inKilograms.startLoad == .kilograms(45), "100 lb is 45.36 kg, on the 1.25 kg step 45")
        let bare = try DayEditing.newSlot(id: newID, exercise: custom([:]), units: .lb, defaultRest: .defaultRest)
        #expect(bare.startLoad == .zero)
    }

    @Test("A custom exercise whose start load is below zero cannot become a slot: newSlot throws")
    func newSlot_negativeStartLoad_throws() {
        let exercise = custom([.lb: .pounds(-10), .kg: .kilograms(-5)])
        #expect(throws: SlotValidationError.negativeStartLoad(.pounds(-10))) {
            try DayEditing.newSlot(id: newID, exercise: exercise, units: .lb, defaultRest: .defaultRest)
        }
        // The throw is typed: this closure compiles only while newSlot throws SlotValidationError alone.
        let inKilograms = Result { () throws(SlotValidationError) in
            try DayEditing.newSlot(id: newID, exercise: exercise, units: .kg, defaultRest: .defaultRest)
        }
        let refused = inKilograms == .failure(.negativeStartLoad(.kilograms(-5)))
        #expect(refused)
    }

    // MARK: - addSlots, removeSlot (slice S1 criterion 6)

    @Test("Picked slots are appended in the order picked, and the day's own slots stay as they were")
    func addSlots_appendsInOrder() throws {
        let added = try DayEditing.addSlots(upperA, [newSlot(901, Fixtures.backSquat), newSlot(900), newSlot(902)])
        #expect(Support.ids(added) == [301, 302, 303, 304, 305, 901, 900, 902])
        #expect(Support.groups(added) == [[301], [302], [303], [304, 305], [901], [900], [902]])
        #expect(added.slots[5].exerciseID == Fixtures.backSquat.id)
        var expected = upperA
        expected.slots += added.slots.suffix(3)
        #expect(Support.difference(added, expected).isEmpty)
        #expect(Support.faults(in: added).isEmpty)
    }

    @Test("The same exercise may be in a day twice, under two ids")
    func addSlots_sameExerciseTwice_isAllowed() throws {
        let added = try DayEditing.addSlots(upperA, [newSlot(900), newSlot(901)])
        #expect(added.slots.filter { $0.exerciseID == Fixtures.bench.id }.map(\.id) == [301, 900, 901]
            .map(Support.slot))
    }

    @Test("A slot whose id the day holds is left out, also when the id comes twice in one call")
    func addSlots_idTheDayHolds_isLeftOut() throws {
        var held = try newSlot(303, Fixtures.backSquat)
        held.sets = 9
        let added = try DayEditing.addSlots(upperA, [held, newSlot(900), newSlot(900, Fixtures.backSquat)])
        #expect(Support.ids(added) == [301, 302, 303, 304, 305, 900])
        #expect(added.slots[2].sets == 4, "the day's own slot 303 is not replaced")
        #expect(added.slots[5].exerciseID == Fixtures.bench.id, "the first of the two wins")
        #expect(Support.difference(DayEditing.addSlots(upperA, []), upperA).isEmpty)
        #expect(Support.difference(DayEditing.addSlots(upperA, [held]), upperA).isEmpty)
    }

    @Test("The first slot of a day is never joined to a previous one, however it arrives")
    func addSlots_toAnEmptyDay_firstSlotIsNeverJoined() throws {
        let empty = DayTemplate(id: upperA.id, name: "New day", tag: "D5")
        var first = try newSlot(900)
        var second = try newSlot(901)
        first.isSupersetWithPrevious = true
        second.isSupersetWithPrevious = true
        let added = DayEditing.addSlots(empty, [first, second])
        #expect(Support.flags(added) == [false, true])
        #expect(Support.groups(added) == [[900, 901]])
    }

    @Test("Removing the first exercise of a superset leaves the next member leading what is left")
    func removeSlot_firstOfAGroup_theNextMemberLeads() throws {
        let removed = DayEditing.removeSlot(upperA, slot: Support.slot(304))
        #expect(Support.ids(removed) == [301, 302, 303, 305])
        #expect(Support.flags(removed) == [false, false, false, false], "305 is not joined to 303")
        let three = try Support.day(joined: [false, false, true, true, false])
        let shorter = DayEditing.removeSlot(three, slot: Support.slot(2))
        #expect(Support.groups(shorter) == [[1], [3, 4], [5]])
        #expect(Support.flags(shorter) == [false, false, true, false])
    }

    @Test("Removing a later member, or a slot beside a superset, leaves the others grouped as they were")
    func removeSlot_otherPlaces_keepTheGroups() throws {
        let day = try Support.day(joined: [false, false, true, true, false])
        #expect(Support.groups(DayEditing.removeSlot(day, slot: Support.slot(3))) == [[1], [2, 4], [5]])
        #expect(Support.groups(DayEditing.removeSlot(day, slot: Support.slot(4))) == [[1], [2, 3], [5]])
        #expect(Support.groups(DayEditing.removeSlot(day, slot: Support.slot(1))) == [[2, 3, 4], [5]])
        #expect(Support.groups(DayEditing.removeSlot(day, slot: Support.slot(5))) == [[1], [2, 3, 4]])
        let first = DayEditing.removeSlot(day, slot: Support.slot(1))
        #expect(Support.flags(first) == [false, true, true, false])
        var expected = day
        expected.slots.remove(at: 4)
        #expect(Support.difference(DayEditing.removeSlot(day, slot: Support.slot(5)), expected).isEmpty)
    }

    @Test("Removing the only slot leaves an empty day")
    func removeSlot_onlySlot_leavesAnEmptyDay() throws {
        let single = try Support.day(joined: [false])
        let removed = DayEditing.removeSlot(single, slot: Support.slot(1))
        #expect(Support.ids(removed) == [])
        #expect(removed.id == single.id)
        #expect(DayEditing.groups(of: removed).isEmpty)
    }
}

// MARK: - Progression, drop set, superset (slice S1 criterion 8)

extension DayEditingTests {
    @Test("Choosing Double makes the top of the range at least reps + 2 (F11 criterion 9)")
    func setProgression_double_widensTheRangeToTwo() throws {
        let narrow = try DayTemplate(id: upperA.id, name: "Day", tag: "DY", slots: [
            Fixtures.slot(Fixtures.bench, id: 1, reps: 8, repsHi: 9),
            Fixtures.slot(Fixtures.bench, id: 2, reps: 8, repsHi: 12),
            Fixtures.slot(Fixtures.bench, id: 3, reps: 30, repsHi: 31)
        ])
        let tops = [1, 2, 3].map { number in
            let edited = DayEditing.setProgression(.double, slot: Support.slot(number), in: narrow)
            return edited.slots[number - 1]
        }
        #expect(tops.map(\.repsHi) == [10, 12, 32])
        #expect(tops.map(\.progression) == [.double, .double, .double])
        #expect(Support.changedFields(narrow.slots[0], tops[0]) == ["repsHi", "progression"])
        #expect(Support.changedFields(narrow.slots[1], tops[1]) == ["progression"])
    }

    @Test("Leaving Double keeps the top of the range, hidden", arguments: [Progression.linear, .fixed])
    func setProgression_awayFromDouble_keepsTheTop(progression: Progression) {
        let edited = DayEditing.setProgression(progression, slot: Support.slot(302), in: upperA)
        #expect(edited.slots[1].progression == progression)
        #expect(edited.slots[1].repsHi == 12)
        #expect(Support.changedFields(upperA.slots[1], edited.slots[1]) == ["progression"])
        #expect(Support.difference(DayEditing.setProgression(.double, slot: Support.slot(302), in: edited), upperA)
            .isEmpty)
    }

    @Test("A drop set is one or none, and nothing else changes")
    func setDropSet_isOneOrNone() {
        let withDrop = DayEditing.setDropSet(true, slot: Support.slot(303), in: upperA)
        #expect(withDrop.slots.map(\.dropSets) == [0, 0, 1, 0, 0])
        #expect(Support.changedFields(upperA.slots[2], withDrop.slots[2]) == ["dropSets"])
        #expect(DayEditing.setDropSet(true, slot: Support.slot(303), in: withDrop).slots[2].dropSets == 1)
        #expect(Support.difference(DayEditing.setDropSet(false, slot: Support.slot(303), in: withDrop), upperA).isEmpty)
    }

    @Test(
        "\"Superset with next\" on the fourth of five joins the fifth; \"Break out\" detaches it (F11 criterion 11)"
    )
    func setSuperset_joinsAndBreaksOut() throws {
        let day = try Support.day(joined: [false, false, false, false, false])
        let joined = DayEditing.setSuperset(true, slot: Support.slot(5), in: day)
        #expect(Support.groups(joined) == [[1], [2], [3], [4, 5]])
        #expect(Support.flags(joined) == [false, false, false, false, true])
        let brokenOut = DayEditing.setSuperset(false, slot: Support.slot(5), in: joined)
        #expect(Support.groups(brokenOut) == [[1], [2], [3], [4], [5]])
        #expect(Support.difference(brokenOut, day).isEmpty)
    }

    @Test("\"Break out\" in the middle of A, B, C splits the group there: B and C stay together")
    func setSuperset_off_inTheMiddle_splitsTheGroupThere() throws {
        let day = try Support.day(joined: [false, true, true])
        let split = DayEditing.setSuperset(false, slot: Support.slot(2), in: day)
        #expect(Support.groups(split) == [[1], [2, 3]])
        #expect(Support.groups(DayEditing.setSuperset(false, slot: Support.slot(3), in: day)) == [[1, 2], [3]])
    }

    @Test("\"Superset with next\" when the next exercise leads a superset makes the two groups one")
    func setSuperset_on_mergesWithTheGroupAhead() throws {
        let day = try Support.day(joined: [false, true, false, true])
        let merged = DayEditing.setSuperset(true, slot: Support.slot(3), in: day)
        #expect(Support.groups(merged) == [[1, 2, 3, 4]])
        #expect(Support.changedFields(day.slots[2], merged.slots[2]) == ["superset"])
    }

    @Test("The day's first slot has no slot before it: joining it changes nothing")
    func setSuperset_onTheFirstSlot_staysOff() {
        let joined = DayEditing.setSuperset(true, slot: Support.slot(301), in: upperA)
        #expect(Support.flags(joined) == [false, false, false, false, true])
        #expect(Support.difference(joined, upperA).isEmpty)
    }

    @Test("groups(of:) gives the slot ids in their superset groups, in order (rule 44)")
    func groups_followTheFlags() throws {
        #expect(Support.groups(upperA) == [[301], [302], [303], [304, 305]])
        #expect(try Support.groups(Support.day(joined: [true, true, false, true, true])) == [[1, 2], [3, 4, 5]])
        #expect(DayEditing.groups(of: DayTemplate(id: upperA.id, name: "New day", tag: "D5")).isEmpty)
    }
}
