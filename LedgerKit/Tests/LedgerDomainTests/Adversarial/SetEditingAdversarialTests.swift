import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S3 adversarial (G2), N11 against ADR-007: a step lands exactly on a multiple, in every unit; its way back is
/// exact only from a multiple; and in any walk of steps every other set, field and exercise stays the same value, not
/// a near one. Property-style over seeded walks.
@Suite("Adversarial F13 S3 · SetEditing's arithmetic and what it leaves alone")
struct SetEditingAdversarialTests {
    private struct Mix: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    private static let steps: [Weight] = [
        .pounds(5), .pounds(2.5), .kilograms(2.5), .kilograms(2), .kilograms(1.25)
    ]

    /// A workout in pounds of two barbell exercises and every state of a set, weights off every multiple included.
    private static func workout(units: Units = .lb) -> WorkoutState {
        var workout = Seeders.workout(number: 3, endedAt: Date(timeIntervalSinceReferenceDate: 811_228_800), [
            .straight(WorkoutRepositoryContract.exercises[0], sets: 4, reps: 5, pounds: 187),
            .straight(WorkoutRepositoryContract.exercises[1], sets: 3, reps: 8, pounds: 225)
        ])
        workout.units = units
        workout.exercises[0].sets[1].weight = .pounds(Decimal(string: "83.9") ?? 0)
        workout.exercises[0].sets[2].doneAt = nil
        workout.exercises[0].sets[3].weight = .kilograms(Decimal(string: "61.37") ?? 0)
        return workout
    }

    private static func isWhole(_ value: Decimal) -> Bool {
        value.rounded(scale: 0, .towardZero) == value
    }

    @Test("From a multiple, up and down are one exact step, and each undoes the other", arguments: steps)
    func onAMultiple_stepsAreExact(step: Weight) {
        for count in 0 ... 800 {
            let weight = Weight.zero.advanced(bySteps: count, of: step)
            let upper = weight.nextMultiple(of: step, .upward)
            #expect(upper == weight.advanced(bySteps: 1, of: step), "\(count) up")
            #expect(upper.nextMultiple(of: step, .downward) == weight, "\(count) up, down")
            guard count > 0 else {
                #expect(weight.nextMultiple(of: step, .downward) == .zero)
                continue
            }
            let down = weight.nextMultiple(of: step, .downward)
            #expect(down == weight.advanced(bySteps: -1, of: step), "\(count) down")
            #expect(down.nextMultiple(of: step, .upward) == weight, "\(count) down, up")
        }
    }

    @Test("From anywhere, a step lands on a multiple on the side tapped, within one step, storable in 10⁻⁷ g")
    func offAMultiple_landsOnAMultiple() {
        var random = Mix(state: 0x0F13_0503)
        for _ in 0 ..< 4000 {
            let step = Self.steps.randomElement(using: &random) ?? .pounds(5)
            let tenths = Decimal(Int.random(in: 1 ... 20000, using: &random)) / 10
            let weight: Weight = Bool.random(using: &random) ? .pounds(tenths) : .kilograms(tenths)
            let upper = weight.nextMultiple(of: step, .upward)
            let down = weight.nextMultiple(of: step, .downward)
            #expect(upper > weight && upper - weight <= step, "\(weight) up by \(step): \(upper)")
            #expect(down < weight && weight - down <= step, "\(weight) down by \(step): \(down)")
            #expect(down >= .zero)
            #expect(Self.isWhole(upper.grams / step.grams), "\(upper) on \(step)")
            #expect(Self.isWhole(down.grams / step.grams), "\(down) on \(step)")
            #expect(Self.isWhole(upper.grams * 10_000_000), "\(upper) is not a whole 10⁻⁷ g")
            #expect(Self.isWhole(down.grams * 10_000_000), "\(down) is not a whole 10⁻⁷ g")
        }
    }

    @Test("A walk of steps moves only the set stepped, only that field, and nothing else of the workout")
    func walk_leavesEverythingElseExact() {
        var random = Mix(state: 0x0F13_0504)
        for seed in 0 ..< 60 {
            let units: Units = seed.isMultiple(of: 2) ? .lb : .kg
            let original = Self.workout()
            var draft = original
            let ids = original.exercises.flatMap(\.sets).map(\.id)
            for _ in 0 ..< 40 {
                let id = ids.randomElement(using: &random) ?? ids[0]
                let field: SetEditing.Field = Bool.random(using: &random) ? .weight : .reps
                let way: StepDirection = Bool.random(using: &random) ? .upward : .downward
                let before = draft
                draft = SetEditing.stepping(id, field, way, in: draft, units: units)
                for (old, new) in zip(before.exercises.flatMap(\.sets), draft.exercises.flatMap(\.sets)) {
                    #expect(old.id == new.id && old.kind == new.kind && old.doneAt == new.doneAt)
                    if old.id != id || !old.isDone {
                        #expect(old == new, "set \(old.id) moved by a step of \(id)")
                    } else if field == .weight {
                        #expect(old.reps == new.reps)
                    } else {
                        #expect(old.weight == new.weight)
                    }
                }
            }
            var flat = draft
            for place in flat.exercises.indices {
                flat.exercises[place].sets = original.exercises[place].sets
            }
            #expect(flat == original, "a field beside the sets changed")
            let changes = SetEditing.changes(from: original, to: draft)
            for exercise in draft.exercises {
                let moved = exercise.sets != original.exercises.first { $0.id == exercise.id }?.sets
                #expect((changes[exercise.id] != nil) == moved)
                // A map entry carries the untouched sets of that exercise too: they must be the stored values.
                #expect(changes[exercise.id].map { $0 == exercise.sets } ?? true)
            }
        }
    }
}

extension SetEditingAdversarialTests {
    @Test("As built: stepping a pound workout in kilograms has no way back; only Cancel restores the original")
    func kilogramsOnPounds_hasNoWayBack() throws {
        let original = Self.workout()
        let id = original.exercises[1].sets[0].id // 225 lb is 102.058… kg
        var draft = original
        for way in [StepDirection.upward, .downward, .downward, .upward, .upward, .downward] {
            draft = SetEditing.stepping(id, .weight, way, in: draft, units: .kg)
            #expect(SetEditing.changes(from: original, to: draft).isEmpty == false, "a kg multiple is never 225 lb")
        }
        // Up then down, as a lifter undoing a tap on 1.25 kg steps: 225 lb (102.1 kg on screen) goes to 102.5, then to
        // 101.25 kg, which is 223.2… lb. It is stored only if Save is tapped, and the number on screen says so.
        let there = SetEditing.stepping(id, .weight, .upward, in: original, units: .kg)
        let back = SetEditing.stepping(id, .weight, .downward, in: there, units: .kg)
        let weight = try #require(back.exercises[1].sets.first?.weight)
        #expect(weight == .kilograms(101.25))
        #expect(weight != original.exercises[1].sets[0].weight)
    }

    @Test("As built: in the workout's own units, a weight off a multiple has no way back either (notes, decision 7)")
    func ownUnits_offAMultiple_hasNoWayBack() {
        let original = Self.workout()
        let id = original.exercises[0].sets[0].id // 187 lb on a 5 lb step
        let there = SetEditing.stepping(id, .weight, .upward, in: original, units: .lb)
        let back = SetEditing.stepping(id, .weight, .downward, in: there, units: .lb)
        #expect(there.exercises[0].sets[0].weight == .pounds(190))
        #expect(back.exercises[0].sets[0].weight == .pounds(185), "187 does not come back")
        #expect(SetEditing.changes(from: original, to: back).isEmpty == false, "Save stays on")
    }

    @Test("The limits: 0 and 1 hold, a weight under one step goes to 0, reps at Int.max neither trap nor move")
    func limits_hold() {
        let workout = Self.workout()
        var set = workout.exercises[0].sets[0]
        set.weight = .pounds(3)
        #expect(SetEditing.stepped(set, .weight, .downward, step: .pounds(5)).weight == .zero)
        set.weight = .zero
        #expect(SetEditing.canStep(set, .weight, .downward) == false)
        #expect(SetEditing.stepped(set, .weight, .downward, step: .pounds(5)).weight == .zero)
        #expect(SetEditing.stepped(set, .weight, .upward, step: .zero).weight == .zero, "a zero step moves nothing")
        set.reps = .one
        #expect(SetEditing.canStep(set, .reps, .downward) == false)
        #expect(SetEditing.stepped(set, .reps, .downward, step: .pounds(5)).reps == .one)
        set.reps = Reps(clamping: .max)
        #expect(SetEditing.canStep(set, .reps, .upward) == false)
        #expect(SetEditing.stepped(set, .reps, .upward, step: .pounds(5)).reps.value == .max)
        #expect(SetEditing.stepped(set, .reps, .downward, step: .pounds(5)).reps.value == .max - 1)
    }

    @Test("A set not logged, and an id no exercise holds, move nothing")
    func notLoggedOrUnknown_moveNothing() {
        let workout = Self.workout()
        let undone = workout.exercises[0].sets[2]
        #expect(SetEditing.canStep(undone, .weight, .upward) == false)
        #expect(SetEditing.canStep(undone, .reps, .upward) == false)
        #expect(SetEditing.stepping(undone.id, .weight, .upward, in: workout, units: .lb) == workout)
        #expect(SetEditing.stepping(SetID(UUID()), .weight, .upward, in: workout, units: .lb) == workout)
        #expect(SetEditing.editable(workout.exercises[0]).map(\.id).contains(undone.id) == false)
    }

    @Test("The same exercise logged twice in a workout: a step moves one row, and the map names that row alone")
    func sameExerciseTwice_changesOneRow() {
        let workout = Seeders.workout(number: 4, endedAt: Date(timeIntervalSinceReferenceDate: 811_228_800), [
            .straight(WorkoutRepositoryContract.exercises[0], sets: 1, reps: 5, pounds: 185),
            .straight(WorkoutRepositoryContract.exercises[0], sets: 1, reps: 5, pounds: 185)
        ])
        let again = workout.exercises[1]
        let draft = SetEditing.stepping(again.sets[0].id, .reps, .upward, in: workout, units: .lb)
        #expect(Array(SetEditing.changes(from: workout, to: draft).keys) == [again.id])
    }
}
