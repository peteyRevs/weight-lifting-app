import Foundation
@testable import LedgerDomain
import Testing

/// Seeded properties of `DayEditing` (F11 slice S1, criteria 1, 7, 8 and 9). A failure names its seed; add
/// that seed as a fixed case before fixing it (testing-strategy §3 rule 5).
@Suite("DayEditing properties", .tags(.domain, .property))
struct DayEditingPropertyTests {
    private typealias Support = EditingTestSupport

    /// Every day one neighbouring swap away from `groups`: two members inside one group, or two groups.
    static func oneSwapAway(from groups: [[SlotID]]) -> [[[SlotID]]] {
        var results: [[[SlotID]]] = []
        for place in groups.indices {
            for member in groups[place].indices.dropLast() {
                var swapped = groups
                swapped[place].swapAt(member, member + 1)
                results.append(swapped)
            }
        }
        for place in groups.indices.dropLast() {
            var swapped = groups
            swapped.swapAt(place, place + 1)
            results.append(swapped)
        }
        return results
    }

    static func opposite(_ direction: MoveDirection) -> MoveDirection {
        direction == .upward ? .downward : .upward
    }

    @Test(
        "A move keeps every slot, every superset and the normal form (the six properties)",
        arguments: PropertySeed.all
    )
    func move_keepsEveryGroupAndTheNormalForm(seed: PropertySeed) throws {
        var generator = seed.generator
        let day = try Support.randomDay(0, using: &generator)
        let slot = Support.someSlot(of: day, using: &generator)
        let direction: MoveDirection = Bool.random(using: &generator) ? .upward : .downward
        let moved = DayEditing.move(day, slot: slot, direction)
        let before = DayEditing.groups(of: day)
        let after = DayEditing.groups(of: moved)

        // 1. The same slots, each once, and nothing but the flag changed in any of them.
        #expect(Support.ids(moved).sorted() == Support.ids(day), "\(seed)")
        let changedFields = day.slots.flatMap { original in
            moved.slots.first { $0.id == original.id }.map { Support.changedFields(original, $0) } ?? ["lost"]
        }
        #expect(Set(changedFields).isSubset(of: ["superset"]), "\(seed)")
        // 2. Normal form, and every slot one the model accepts.
        #expect(Support.faults(in: moved).isEmpty, "\(seed)")
        // 3. Who is in a superset with whom never changes.
        #expect(Set(after.map(Set.init)) == Set(before.map(Set.init)), "\(seed)")
        // 4. Nothing moved, or one neighbouring swap inside a group, or one swap of two neighbouring groups.
        #expect(after == before || Self.oneSwapAway(from: before).contains(after), "\(seed)")
        // 5. The day's edges and an unknown id return the day.
        let held = day.slots.contains { $0.id == slot }
        let atEdge = direction == .upward ? before.first?.first == slot : before.last?.last == slot
        if !held || atEdge {
            #expect(Support.difference(moved, day).isEmpty, "\(seed)")
        } else {
            #expect(after != before, "\(seed): a slot away from the day's edge always moves")
        }
        // 6. A group of one that moved, and a swap inside a group, are undone by the opposite move.
        let groupSize = before.first { $0.contains(slot) }?.count ?? 0
        let swappedInside = after != before && after.map(Set.init) == before.map(Set.init)
        if after != before, groupSize == 1 || swappedInside {
            let back = DayEditing.move(moved, slot: slot, Self.opposite(direction))
            #expect(Support.difference(back, day).isEmpty, "\(seed)")
        }
    }

    @Test(
        "Any value set on any field gives a slot the model accepts, and changes that field alone",
        arguments: PropertySeed.all
    )
    func set_anyValue_givesASlotTheModelAccepts(seed: PropertySeed) throws {
        var generator = seed.generator
        let day = try Support.randomDay(0, slots: 1 ... 8, using: &generator)
        let slot = try #require(day.slots.randomElement(using: &generator))
        let wild = Int.random(in: -50 ... 400, using: &generator)
        let values: [SlotField] = Support.fields + [
            .sets(wild), .reps(wild), .repsHi(wild), .restSeconds(wild),
            .rpe(Decimal(wild) / 4), .startLoad(.pounds(Decimal(wild) / 8))
        ]
        let field = try #require(values.randomElement(using: &generator))
        let edited = DayEditing.set(field, slot: slot.id, in: day)
        let after = try #require(edited.slots.first { $0.id == slot.id })

        #expect(Support.faults(in: edited).isEmpty, "\(seed): \(field)")
        let kind = Support.kind(of: field)
        let allowed: Set<String> = kind == .reps ? ["reps", "repsHi"] : ["\(kind)"]
        #expect(Set(Support.changedFields(slot, after)).isSubset(of: allowed), "\(seed): \(field)")
        #expect(after.repsHi > after.reps, "\(seed): \(field)")
        let others = zip(day.slots, edited.slots).filter { $0.0.id != slot.id }
        let othersUnchanged = others.allSatisfy { $0 == $1 }
        #expect(othersUnchanged, "\(seed): another slot changed")
        #expect(
            Support.difference(DayEditing.set(field, slot: slot.id, in: edited), edited).isEmpty,
            "\(seed): set twice"
        )
    }

    @Test(
        "Thirty random edits of a day keep it in normal form, with slots the model accepts",
        arguments: PropertySeed.all
    )
    func randomEdits_keepTheNormalForm(seed: PropertySeed) throws {
        var generator = seed.generator
        var day = try Support.randomDay(0, using: &generator)
        if Bool.random(using: &generator), !day.slots.isEmpty {
            day.slots[0].isSupersetWithPrevious = true
        }
        for step in 0 ..< 30 {
            let edit = try #require(Support.dayEdits.randomElement(using: &generator))
            let edited = try edit.apply(day, 50000 + step, &generator)
            // The first fault ends the seed: one line for a seed, however many steps would have failed.
            try #require(Support.faults(in: edited).isEmpty, "\(seed), step \(step): \(edit.name)")
            let sameDay = edited.id == day.id && edited.name == day.name && edited.tag == day.tag
            try #require(sameDay, "\(seed), step \(step): \(edit.name) changed the day's id, name or tag")
            day = edited
        }
    }

    @Test(
        "The start load's stepper lands on a multiple of the step, one step away at most, never below zero",
        arguments: PropertySeed.all
    )
    func steppedStartLoad_landsOnTheNextMultiple(seed: PropertySeed) throws {
        var generator = seed.generator
        let slot = try Support.randomSlot(id: 1, joined: false, using: &generator)
        let exercise = try #require(Support.exercises.first { $0.id == slot.exerciseID })
        let units = try #require(Units.allCases.randomElement(using: &generator))
        let load = slot.startLoad ?? exercise.startLoad(in: units)
        let step = slot.step ?? exercise.equipment.defaultStep(in: units)
        for direction in [StepDirection.downward, .upward] {
            guard case let .startLoad(next) = DayEditing.stepped(
                .startLoad,
                direction,
                of: slot,
                exercise: exercise,
                units: units
            )
            else {
                Issue.record("\(seed): stepped(.startLoad) gave another field")
                return
            }
            #expect(next >= .zero, "\(seed)")
            #expect(next.rounded(toStep: step) == next, "\(seed): \(next.grams) g is no multiple of \(step.grams) g")
            if direction == .upward {
                #expect(next > load && next - load <= step, "\(seed): up from \(load.grams) g gave \(next.grams) g")
            } else if load > .zero {
                #expect(next < load && load - next <= step, "\(seed): down from \(load.grams) g gave \(next.grams) g")
            } else {
                #expect(next == .zero, "\(seed)")
            }
        }
    }
}

// MARK: - What editing never writes (slice S1 criterion 12)

extension DayEditingPropertyTests {
    /// The fixture numbers of the slots that `after` holds with other misses, or another exercise, than
    /// `before` has under the same id.
    static func rewritten(from before: [Slot], to after: [Slot]) -> [Int] {
        let earlier = Dictionary(before.map { ($0.id, $0) }) { first, _ in first }
        let changed = after.filter { slot in
            earlier[slot.id].map { $0.misses != slot.misses || $0.exerciseID != slot.exerciseID } ?? false
        }
        return Support.numbers(changed.map(\.id.rawValue))
    }

    @Test(
        "No function of ProgramEditing or DayEditing changes the misses or the exercise of a slot that already exists",
        arguments: PropertySeed.all
    )
    func noFunction_changesMissesOrTheExerciseOfAnExistingSlot(seed: PropertySeed) throws {
        var generator = seed.generator
        var program = try Support.randomProgram(using: &generator)
        let original = program.days.flatMap(\.slots)
        for step in 0 ..< 30 {
            let edit = try #require(Support.programEdits.randomElement(using: &generator))
            let before = program.days.flatMap(\.slots)
            program = try edit.apply(program, 50000 + step, &generator)
            // The first breach ends the seed: one line for a seed, not one for each slot of each later step.
            let rewritten = Self.rewritten(from: before, to: program.days.flatMap(\.slots))
            try #require(rewritten.isEmpty, "\(seed), step \(step): \(edit.name) rewrote a slot")
        }
        let sinceTheStart = Self.rewritten(from: original, to: program.days.flatMap(\.slots))
        #expect(sinceTheStart.isEmpty, "\(seed): a slot of the seeded program differs after the thirty edits")
    }

    @Test(
        "Each function of DayEditing, on slots drawn from a seeded day, leaves every slot's misses and exercise",
        arguments: PropertySeed.all
    )
    func everyDayEdit_onDrawnSlots_leavesMissesAndExercise(seed: PropertySeed) throws {
        var generator = seed.generator
        let day = try Support.randomDay(0, slots: 1 ... 6, using: &generator)
        for edit in Support.dayEdits {
            // As many draws as the day has slots; an edit picks its own slot, so some are drawn twice.
            for _ in day.slots {
                let edited = try edit.apply(day, 50000, &generator)
                let rewritten = Self.rewritten(from: day.slots, to: edited.slots)
                try #require(rewritten.isEmpty, "\(seed): \(edit.name) rewrote a slot")
            }
        }
    }
}
