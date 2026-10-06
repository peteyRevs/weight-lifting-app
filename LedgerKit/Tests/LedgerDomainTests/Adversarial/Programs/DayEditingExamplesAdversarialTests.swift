import Foundation
@testable import LedgerDomain
import Testing

/// The brief's criteria 8 to 12 as the plan restates them ("Inputs the implementer needs › S2", "The criteria
/// as input → output"), value for value, and the plan's behaviours 7 to 12.
@Suite("DayEditing worked examples (adversarial)", .tags(.domain))
struct DayEditingExamplesAdversarialTests {
    static let slot = EditAdv.slotID(1)

    /// A day of one bench slot: 3 × `reps`, top of range `top`, RPE 8, 150 s of rest, linear.
    static func day(reps: Int = 8, top: Int = 10, progression: Progression = .linear) throws -> DayTemplate {
        let bench = try Fixtures.slot(
            Fixtures.bench,
            id: 1,
            reps: reps,
            repsHi: top,
            rest: 150,
            progression: progression
        )
        return DayTemplate(id: EditAdv.dayID(4000), name: "Upper A", tag: "UA", slots: [bench])
    }

    /// Reps and the top of the range of the day's one slot after `field` is set.
    static func range(setting field: SlotField, in day: DayTemplate) -> [Int] {
        let edited = DayEditing.set(field, slot: slot, in: day)
        return edited.slots.flatMap { [$0.reps, $0.repsHi] }
    }

    static func set(_ field: SlotField, in day: DayTemplate) throws -> Slot {
        try #require(DayEditing.set(field, slot: slot, in: day).slots.first)
    }

    /// Five slots numbered 5000 to 5004 with these flags.
    static func numbers(_ day: DayTemplate) -> [Int] {
        day.slots.map { EditAdv.number($0.id.rawValue) }
    }
}

// MARK: - Criteria 8 and 9: fields and progression

extension DayEditingExamplesAdversarialTests {
    @Test("Criterion 8: from reps 8 and top 10, reps 9 leaves the top, reps 10 pushes it to 11, and top 8 snaps to 9.")
    func set_repsAndTop_keepTheTopAboveReps() throws {
        let day = try Self.day()
        #expect(Self.range(setting: .reps(9), in: day) == [9, 10])
        #expect(Self.range(setting: .reps(10), in: day) == [10, 11])
        #expect(Self.range(setting: .reps(11), in: day) == [11, 12])
        #expect(Self.range(setting: .repsHi(8), in: day) == [8, 9])
        #expect(Self.range(setting: .repsHi(9), in: day) == [8, 9])
        #expect(Self.range(setting: .repsHi(3), in: day) == [8, 9])
        #expect(Self.range(setting: .repsHi(11), in: day) == [8, 11])
    }

    @Test(
        "Criterion 8: sets 0 and 13, RPE 4.5 and 10.5, rest 15 and 315 and a load of −5 lb are held at the limits."
    )
    func set_beyondTheLimits_isHeld() throws {
        let day = try Self.day()
        #expect(try Self.set(.sets(0), in: day).sets == 1)
        #expect(try Self.set(.sets(13), in: day).sets == 12)
        #expect(try Self.set(.rpe(4.5), in: day).rpe == Fixtures.rpe(5))
        #expect(try Self.set(.rpe(10.5), in: day).rpe == Fixtures.rpe(10))
        #expect(try Self.set(.restSeconds(15), in: day).rest.seconds == 30)
        #expect(try Self.set(.restSeconds(315), in: day).rest.seconds == 300)
        #expect(try Self.set(.startLoad(.pounds(-5)), in: day).startLoad == .zero)
    }

    @Test("Criterion 8: \"+\" on a rest of 150 s asks for 165 s, and set stores it.")
    func stepped_restUp_isFifteenSecondsMore() throws {
        let day = try Self.day()
        let slot = try #require(day.slots.first)
        let field = DayEditing.stepped(.rest, .upward, of: slot, exercise: Fixtures.bench, units: .lb)
        #expect(field == .restSeconds(165))
        #expect(try Self.set(field, in: day).rest.seconds == 165)
        let down = DayEditing.stepped(.rest, .downward, of: slot, exercise: Fixtures.bench, units: .lb)
        #expect(down == .restSeconds(135))
    }

    @Test("Criterion 9: with reps 8, Double makes a top of 9 into 10 and leaves a top of 12.")
    func setProgression_double_makesTheTopAtLeastRepsPlusTwo() throws {
        let narrow = try DayEditing.setProgression(.double, slot: Self.slot, in: Self.day(top: 9))
        #expect(narrow.slots.map(\.repsHi) == [10])
        #expect(narrow.slots.map(\.reps) == [8])
        #expect(narrow.slots.map(\.progression) == [.double])
        let wide = try DayEditing.setProgression(.double, slot: Self.slot, in: Self.day(top: 12))
        #expect(wide.slots.map(\.repsHi) == [12])
        let exact = try DayEditing.setProgression(.double, slot: Self.slot, in: Self.day(top: 10))
        #expect(exact.slots.map(\.repsHi) == [10])
    }

    @Test("Behaviour 12: leaving Double keeps the top of the range, for Linear and for Fixed.")
    func setProgression_awayFromDouble_keepsTheTop() throws {
        let day = try Self.day(top: 9, progression: .double)
        for progression in [Progression.linear, .fixed] {
            let left = DayEditing.setProgression(progression, slot: Self.slot, in: day)
            #expect(left.slots.map(\.repsHi) == [9])
            #expect(left.slots.map(\.progression) == [progression])
        }
    }

    @Test("Behaviour 10: 180 lb read in kilograms (81.6) steps up to 82.5 kg and down to 80 kg.")
    func stepped_startLoadOffTheSteps_goesToTheNextMultiple() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, startLoad: .pounds(180))
        let above = DayEditing.stepped(.startLoad, .upward, of: slot, exercise: Fixtures.bench, units: .kg)
        #expect(above == .startLoad(.kilograms(82.5)))
        let below = DayEditing.stepped(.startLoad, .downward, of: slot, exercise: Fixtures.bench, units: .kg)
        #expect(below == .startLoad(.kilograms(80)))
    }
}

// MARK: - Criteria 10 and 11: move and supersets

extension DayEditingExamplesAdversarialTests {
    @Test("Criterion 10: \"Move down\" on 2 in [1, 2, 3A, 3B, 4] carries it past the superset.")
    func move_soloDownPastAGroup_passesTheWholeGroup() throws {
        let day = try EditAdv.day(flags: [false, false, false, true, false])
        let moved = DayEditing.move(day, slot: EditAdv.slotID(5001), .downward)
        #expect(Self.numbers(moved) == [5000, 5002, 5003, 5001, 5004])
        #expect(moved.slots.map(\.isSupersetWithPrevious) == [false, false, true, false, false])
    }

    @Test("Criterion 10: \"Move down\" on 3A swaps it with 3B inside the superset.")
    func move_firstMemberDown_swapsInsideTheGroup() throws {
        let day = try EditAdv.day(flags: [false, false, false, true, false])
        let moved = DayEditing.move(day, slot: EditAdv.slotID(5002), .downward)
        #expect(Self.numbers(moved) == [5000, 5001, 5003, 5002, 5004])
        #expect(moved.slots.map(\.isSupersetWithPrevious) == [false, false, false, true, false])
    }

    @Test("Criterion 10: \"Move up\" on 3A carries the whole superset above 2.")
    func move_firstMemberUp_movesTheGroupAsOne() throws {
        let day = try EditAdv.day(flags: [false, false, false, true, false])
        let moved = DayEditing.move(day, slot: EditAdv.slotID(5002), .upward)
        #expect(Self.numbers(moved) == [5000, 5002, 5003, 5001, 5004])
        #expect(moved.slots.map(\.isSupersetWithPrevious) == [false, false, true, false, false])
    }

    @Test("Property 6's exception: after \"Move down\" on 2B in [2A, 2B], [3], \"Move up\" on 2B swaps it with 2A.")
    func move_groupFromItsEdge_thenBack_doesNotRestore() throws {
        let day = try EditAdv.day(flags: [false, true, false])
        let down = DayEditing.move(day, slot: EditAdv.slotID(5001), .downward)
        #expect(Self.numbers(down) == [5002, 5000, 5001])
        #expect(down.slots.map(\.isSupersetWithPrevious) == [false, false, true])
        let back = DayEditing.move(down, slot: EditAdv.slotID(5001), .upward)
        #expect(Self.numbers(back) == [5002, 5001, 5000])
        #expect(back.slots.map(\.isSupersetWithPrevious) == [false, false, true])
    }

    @Test(
        "Criterion 11: joining the fifth of five slots makes four groups, the last of two; breaking it out makes five."
    )
    func setSuperset_onTheFifthSlot_joinsItToTheFourth() throws {
        let day = try EditAdv.day(flags: [false, false, false, false, false])
        let ids = day.slots.map(\.id)
        let joined = DayEditing.setSuperset(true, slot: ids[4], in: day)
        #expect(DayEditing.groups(of: joined) == [[ids[0]], [ids[1]], [ids[2]], [ids[3], ids[4]]])
        #expect(joined.slots.map(\.isSupersetWithPrevious) == [false, false, false, false, true])
        let broken = DayEditing.setSuperset(false, slot: ids[4], in: joined)
        #expect(DayEditing.groups(of: broken) == ids.map { [$0] })
        let restored = broken == day
        #expect(restored)
    }

    @Test("Behaviour 7: removing the first of [A, B] leaves B leading, not joined to the exercise before A.")
    func removeSlot_firstOfAGroup_theNextMemberLeads() throws {
        let day = try EditAdv.day(flags: [false, false, true, true])
        let removed = DayEditing.removeSlot(day, slot: EditAdv.slotID(5001))
        #expect(Self.numbers(removed) == [5000, 5002, 5003])
        #expect(removed.slots.map(\.isSupersetWithPrevious) == [false, false, true])
    }

    @Test("Behaviour 8: \"Break out\" on the middle of [A, B, C] leaves [A] and [B, C].")
    func setSuperset_offInTheMiddle_splitsTheGroupThere() throws {
        let day = try EditAdv.day(flags: [false, true, true])
        let ids = day.slots.map(\.id)
        let broken = DayEditing.setSuperset(false, slot: ids[1], in: day)
        #expect(DayEditing.groups(of: broken) == [[ids[0]], [ids[1], ids[2]]])
        #expect(Self.numbers(broken) == [5000, 5001, 5002])
    }

    @Test("Behaviour 9: \"Superset with next\" when the next exercise leads a superset makes the two groups one.")
    func setSuperset_onTheLeaderOfAGroup_mergesTheGroups() throws {
        let day = try EditAdv.day(flags: [false, true, false, true])
        let ids = day.slots.map(\.id)
        let merged = DayEditing.setSuperset(true, slot: ids[2], in: day)
        #expect(DayEditing.groups(of: merged) == [ids])
        #expect(merged.slots.map(\.isSupersetWithPrevious) == [false, true, true, true])
    }
}

// MARK: - Criterion 12: a new slot

extension DayEditingExamplesAdversarialTests {
    @Test(
        "Criterion 12: a bench slot from the library is 3 × 8, top 10, RPE 8, 90 s, linear, from 180 lb, and no more."
    )
    func newSlot_bench_hasRuleSevensDefaults() throws {
        let slot = try DayEditing.newSlot(
            id: Self.slot,
            exercise: Fixtures.bench,
            units: .lb,
            defaultRest: .defaultRest
        )
        let expected = try Slot(
            id: Self.slot,
            exerciseID: Fixtures.bench.id,
            sets: 3,
            reps: 8,
            repsHi: 10,
            rpe: 8,
            restSeconds: 90,
            progression: .linear,
            startLoad: .pounds(180)
        )
        let isRuleSeven = slot == expected
        #expect(isRuleSeven)
        #expect(slot.step == nil)
        #expect(slot.misses.isEmpty)
        #expect(slot.dropSets == 0)
        #expect(slot.isSupersetWithPrevious == false)
    }

    @Test(
        "Criterion 12: in kilograms the start load is the exercise's kilogram load, and the rest the lifter's default."
    )
    func newSlot_inKilograms_takesTheKilogramLoadAndTheDefaultRest() throws {
        let rest = try Fixtures.rest(45)
        let slot = try DayEditing.newSlot(id: Self.slot, exercise: Fixtures.inclineDB, units: .kg, defaultRest: rest)
        #expect(slot.startLoad == .kilograms(22.5))
        #expect(slot.rest.seconds == 45)
        let scheme = [slot.sets, slot.reps, slot.repsHi]
        #expect(scheme == [3, 8, 10])
    }

    @Test("A custom exercise with a start load below zero throws negativeStartLoad instead of making a slot.")
    func newSlot_negativeStartLoad_throws() {
        let custom = Adversarial.catalogExercise(900, .machine, loads: [.lb: .pounds(-10), .kg: .kilograms(-5)])
        #expect(throws: SlotValidationError.negativeStartLoad(.pounds(-10))) {
            try DayEditing.newSlot(id: Self.slot, exercise: custom, units: .lb, defaultRest: .defaultRest)
        }
    }
}
