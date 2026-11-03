import Foundation
@testable import LedgerDomain
import Testing

/// F13 S3, N11: what fixing a past workout may change, and how far a step goes. A pound workout read in kilograms, a
/// weight between multiples, zero, reps at 1, and a property: only the logged sets' weight and reps ever change.
@Suite("SetEditing", .tags(.domain))
struct SetEditingTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func set(_ number: Int, pounds: Decimal = 185, reps: Int = 5, done: Bool = true) -> LoggedSet {
        LoggedSet(
            id: SetID(uuid(1000 + number)),
            weight: .pounds(pounds),
            reps: Reps(clamping: reps),
            kind: .working,
            doneAt: done ? now : nil
        )
    }

    static func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
    }

    static func exercise(
        _ number: Int = 1,
        equipment: Equipment = .barbell,
        step: Weight = .pounds(5),
        sets: [LoggedSet]
    ) -> WorkoutExercise {
        WorkoutExercise(
            id: WorkoutExerciseID(uuid(number)),
            slotID: nil,
            exerciseID: ExerciseID(uuid(100 + number)),
            originalExerciseID: ExerciseID(uuid(100 + number)),
            name: "Lift \(number)",
            equipment: equipment,
            step: step,
            rest: RestDuration(clampingSeconds: 90),
            rpe: RPE(clamping: 8),
            isSupersetWithPrevious: false,
            targetSets: sets.count,
            targetReps: 5,
            targetLoad: .pounds(185),
            sets: sets
        )
    }

    static func workout(units: Units = .lb, _ exercises: [WorkoutExercise]) -> WorkoutState {
        WorkoutState(
            id: WorkoutID(uuid(50)),
            source: nil,
            name: "Upper A",
            tag: "",
            isDeload: false,
            exercises: exercises,
            cursor: nil,
            startedAt: now,
            endedAt: now,
            phase: .finished,
            originDevice: DeviceID(uuid(60)),
            units: units
        )
    }

    // MARK: The step

    @Test("The step is the exercise's own in the workout's units, the equipment's in other units")
    func step_followsTheUnits() {
        let own = Self.exercise(equipment: .dumbbell, step: .pounds(10), sets: [])
        #expect(SetEditing.step(of: own, loggedIn: .lb, readIn: .lb) == .pounds(10))
        #expect(SetEditing.step(of: own, loggedIn: .lb, readIn: .kg) == .kilograms(1.25))
        #expect(SetEditing.step(of: own, loggedIn: .kg, readIn: .lb) == .pounds(2.5))
    }

    @Test("A stored step that cannot move a weight falls back to the equipment's")
    func step_ofZero_isTheEquipments() {
        let none = Self.exercise(step: .zero, sets: [])
        #expect(SetEditing.step(of: none, loggedIn: .lb, readIn: .lb) == .pounds(5))
    }

    // MARK: Weight

    @Test("A weight on a multiple moves one step either way")
    func weight_onAMultiple_movesOneStep() {
        let upward = SetEditing.stepped(Self.set(1), .weight, .upward, step: .pounds(5))
        let downward = SetEditing.stepped(Self.set(1), .weight, .downward, step: .pounds(5))
        #expect(upward.weight == .pounds(190))
        #expect(downward.weight == .pounds(180))
    }

    @Test("185 lb read in kilograms (83.9) goes to 85 kg up and 82.5 kg down on the barbell's kg step")
    func weight_inOtherUnits_goesToTheNextMultiple() {
        let workout = Self.workout([Self.exercise(sets: [Self.set(1)])])
        let upward = SetEditing.stepping(Self.set(1).id, .weight, .upward, in: workout, units: .kg)
        let downward = SetEditing.stepping(Self.set(1).id, .weight, .downward, in: workout, units: .kg)
        #expect(upward.exercises[0].sets[0].weight == .kilograms(85))
        #expect(downward.exercises[0].sets[0].weight == .kilograms(82.5))
    }

    @Test("A weight between multiples goes to the one on the side tapped")
    func weight_betweenMultiples_goesToTheSideTapped() {
        let between = Self.set(1, pounds: 187.5)
        #expect(SetEditing.stepped(between, .weight, .upward, step: .pounds(5)).weight == .pounds(190))
        #expect(SetEditing.stepped(between, .weight, .downward, step: .pounds(5)).weight == .pounds(185))
    }

    @Test("A weight never goes below 0, and 0 has no step down")
    func weight_stopsAtZero() {
        let light = Self.set(1, pounds: 2.5)
        #expect(SetEditing.stepped(light, .weight, .downward, step: .pounds(5)).weight == .zero)
        let empty = Self.set(1, pounds: 0)
        #expect(SetEditing.stepped(empty, .weight, .downward, step: .pounds(5)).weight == .zero)
        #expect(!SetEditing.canStep(empty, .weight, .downward))
        #expect(SetEditing.canStep(empty, .weight, .upward))
        #expect(SetEditing.stepped(empty, .weight, .upward, step: .pounds(5)).weight == .pounds(5))
    }

    @Test("nextMultiple with no usable step stays, and never reads below 0")
    func nextMultiple_withoutAStep_stays() {
        #expect(Weight.pounds(100).nextMultiple(of: .zero, .upward) == .pounds(100))
        #expect(Weight.pounds(100).nextMultiple(of: .pounds(-5), .downward) == .pounds(100))
    }

    // MARK: Reps

    @Test("Reps move by one and stop at 1")
    func reps_stepByOne_andStopAtOne() {
        #expect(SetEditing.stepped(Self.set(1), .reps, .upward, step: .pounds(5)).reps.value == 6)
        #expect(SetEditing.stepped(Self.set(1), .reps, .downward, step: .pounds(5)).reps.value == 4)
        let one = Self.set(1, reps: 1)
        #expect(SetEditing.stepped(one, .reps, .downward, step: .pounds(5)).reps.value == 1)
        #expect(!SetEditing.canStep(one, .reps, .downward))
        #expect(SetEditing.canStep(one, .reps, .upward))
    }

    @Test("Reps at the top of what an Int holds stay there")
    func reps_atTheTop_stay() {
        let most = Self.set(1, reps: .max)
        #expect(SetEditing.stepped(most, .reps, .upward, step: .pounds(5)).reps.value == .max)
        #expect(!SetEditing.canStep(most, .reps, .upward))
    }
}

// MARK: - What passes through

extension SetEditingTests {
    @Test("A set that was not logged is not offered, cannot step and does not change")
    func notLogged_isLeftAlone() {
        let skipped = Self.set(2, done: false)
        let exercise = Self.exercise(sets: [Self.set(1), skipped])
        #expect(SetEditing.editable(exercise).map(\.id) == [Self.set(1).id])
        for field in [SetEditing.Field.weight, .reps] {
            for direction in [StepDirection.upward, .downward] {
                #expect(!SetEditing.canStep(skipped, field, direction))
                #expect(SetEditing.stepped(skipped, field, direction, step: .pounds(5)) == skipped)
            }
        }
    }

    @Test("An id no exercise holds changes nothing, and nothing changed is no change")
    func unknownSet_changesNothing() {
        let workout = Self.workout([Self.exercise(sets: [Self.set(1)])])
        let same = SetEditing.stepping(Self.set(9).id, .reps, .upward, in: workout, units: .lb)
        #expect(same == workout)
        #expect(SetEditing.changes(from: workout, to: same).isEmpty)
    }

    @Test("Changes name only the exercises that differ, with all their sets")
    func changes_nameOnlyWhatDiffers() {
        let first = Self.exercise(1, sets: [Self.set(1), Self.set(2)])
        let second = Self.exercise(2, sets: [Self.set(3)])
        let workout = Self.workout([first, second])
        let edited = SetEditing.stepping(Self.set(2).id, .reps, .upward, in: workout, units: .lb)
        let changes = SetEditing.changes(from: workout, to: edited)
        #expect(Array(changes.keys) == [first.id])
        #expect(changes[first.id]?.map(\.reps.value) == [5, 6])
    }

    @Test("A step and its way back in the same units is no change")
    func stepAndBack_isNoChange() {
        let workout = Self.workout([Self.exercise(sets: [Self.set(1)])])
        let id = Self.set(1).id
        let there = SetEditing.stepping(id, .weight, .upward, in: workout, units: .lb)
        let back = SetEditing.stepping(id, .weight, .downward, in: there, units: .lb)
        #expect(SetEditing.changes(from: workout, to: back).isEmpty)
    }

    @Test(
        "Whatever is stepped, only a logged set's weight and reps change; ids, kinds, order and doneAt pass through",
        arguments: 0 ..< 40
    )
    func property_onlyLoggedWeightAndRepsChange(_ seed: Int) {
        var generator = SplitMix(seed: UInt64(seed))
        let sets = (0 ..< 6).map { place in
            Self.set(
                place,
                pounds: Decimal(Int.random(in: 0 ... 80, using: &generator)) * 2.5,
                reps: Int.random(in: 1 ... 12, using: &generator),
                done: Bool.random(using: &generator)
            )
        }
        let original = Self.workout(units: seed.isMultiple(of: 2) ? .lb : .kg, [Self.exercise(sets: sets)])
        var edited = original
        for _ in 0 ..< 30 {
            let id = sets[Int.random(in: 0 ..< sets.count, using: &generator)].id
            edited = SetEditing.stepping(
                id,
                Bool.random(using: &generator) ? .weight : .reps,
                Bool.random(using: &generator) ? .upward : .downward,
                in: edited,
                units: Bool.random(using: &generator) ? .lb : .kg
            )
        }
        for (before, after) in zip(original.exercises[0].sets, edited.exercises[0].sets) {
            #expect(before.id == after.id && before.kind == after.kind && before.doneAt == after.doneAt)
            #expect(after.weight >= .zero && after.reps >= .one)
            if !before.isDone {
                #expect(before == after)
            }
        }
        var restored = edited
        restored.exercises[0].sets = original.exercises[0].sets
        #expect(restored == original, "nothing but the sets changed")
    }
}

/// A seeded generator, so a failing seed fails again.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
