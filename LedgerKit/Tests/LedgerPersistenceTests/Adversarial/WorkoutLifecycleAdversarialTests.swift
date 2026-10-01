import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: a workout through its life: stored, stored again, rebuilt, deleted, brought
/// back, and refused when it is not finished; and the misses it writes to the program.
@Suite("Adversarial S3 · workout lifecycle", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutLifecycleAdversarialTests {
    @Test("Materialising the same workout, records and misses three times changes no byte after the first")
    func materialize_isIdempotent() async throws {
        let stack = try await S3Kit.stack()
        let program = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        var slot = program.days[0].slots[1]
        slot.misses = [0, 2]
        let workout = S3Kit.mixed(1)
        let records = [S3Kit.record(S3Kit.bench, .weightAtReps(.pounds(190), Reps(clamping: 3)), in: workout)]
        try await stack.materialize(workout, prs: records, slots: [slot])
        let first = try await stack.dump()
        for _ in 0 ..< 2 {
            stack.clock.advance()
            try await stack.materialize(workout, prs: records, slots: [slot])
            #expect(try await stack.dump() == first)
        }
        #expect(try await stack.liveCounts() == S3Kit.expectedCounts([workout], records: 1))
    }

    @Test("A workout that is live, discarded or has no end is refused; a stored workout of that id keeps every byte")
    func notFinished_isRefused_andLeavesTheStoredWorkout() async throws {
        let stack = try await S3Kit.stack()
        let stored = S3Kit.mixed(1)
        try await stack.materialize(stored)
        stack.clock.advance()
        let before = try await stack.dump()
        let key = "workout \(stored.id.rawValue.uuidString)"
        for phase in WorkoutPhase.allCases {
            for hasEnd in [true, false] where !(phase == .finished && hasEnd) {
                var refused = S3Kit.mixed(1)
                refused.name = "Not finished"
                refused.phase = phase
                refused.endedAt = hasEnd ? S3Kit.now : nil
                await #expect(throws: LedgerPersistenceError.notFinished(key), "\(phase), end: \(hasEnd)") {
                    try await stack.materialize(refused)
                }
            }
        }
        #expect(try await stack.dump() == before)
    }

    @Test("A workout that ended before it started, or in no time at all, is stored as given")
    func oddDurations_areStored() async throws {
        let stack = try await S3Kit.stack()
        var backwards = S3Kit.mixed(1)
        backwards.startedAt = S3Kit.day(3)
        var instant = S3Kit.mixed(2, endedAt: S3Kit.day(-1))
        instant.startedAt = S3Kit.day(-1)
        try await stack.materialize(backwards)
        try await stack.materialize(instant)
        #expect(try await stack.workouts.recent(limit: 5) == [backwards, instant])
    }

    @Test("A deleted workout rebuilt with other rows comes back as the new state, with the first created_at")
    func rematerializeAfterDelete_storesTheNewState() async throws {
        let stack = try await S3Kit.stack()
        let first = S3Kit.mixed(1)
        let record = S3Kit.record(S3Kit.bench, .estimatedOneRepMax(.pounds(215)), in: first)
        try await stack.materialize(first, prs: [record])
        let created = try await stack.texts("SELECT created_at FROM workout")
        stack.clock.advance()
        try await stack.workouts.delete(id: first.id)
        #expect(try await stack.liveCounts() == [0, 0, 0, 0])
        #expect(try await stack.stats().personalRecords(exerciseID: S3Kit.bench) == [])
        stack.clock.advance()
        var rebuilt = first
        rebuilt.exercises.removeFirst()
        rebuilt.exercises[0].sets.removeLast()
        rebuilt.exercises.append(S3Kit.exercise(
            1,
            7,
            S3Kit.RowSpec(S3Kit.press, [S3Kit.set(95, 8)]),
            doneAt: S3Kit.now
        ))
        try await stack.materialize(rebuilt)
        #expect(try await stack.workouts.workout(id: first.id) == rebuilt)
        #expect(try await stack.liveCounts() == S3Kit.expectedCounts([rebuilt]))
        #expect(try await stack.texts("SELECT created_at FROM workout") == created)
        #expect(try await stack.texts("SELECT pr_count FROM workout") == ["0"])
        #expect(try await stack.stats().personalRecords(exerciseID: S3Kit.bench) == [])
        #expect(try await stack.stats().sessionCount(exerciseID: S3Kit.bench) == 0)
    }

    enum SlotCase: String, CaseIterable, Sendable {
        case unknownSlot, removedSlot, slotOfADeletedProgram, sameSlotTwice, slotOfAnInactiveProgram
    }

    @Test(
        "Slot updates for a slot that is unknown, removed or deleted are skipped; the last of two wins",
        arguments: SlotCase.allCases
    )
    func slotUpdates_edgeCases(slotCase: SlotCase) async throws {
        let stack = try await S3Kit.stack()
        let program = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        let other = try S2Kit.program(2, weeks: 3, days: 2, slotsPerDay: 2, isActive: false)
        try await stack.programs.save(other)
        var slot = program.days[0].slots[0]
        slot.misses = [0, 1, 2]
        var updates = [slot]
        var expected = program
        switch slotCase {
        case .unknownSlot:
            updates = try [S2Kit.slot(9999, misses: [1])]
        case .removedSlot:
            expected.days[0].slots.removeFirst()
            try await stack.programs.save(expected)
        case .slotOfADeletedProgram:
            try await stack.programs.delete(program.id)
        case .sameSlotTwice:
            var again = slot
            again.misses = [1]
            updates.append(again)
            expected.days[0].slots[0].misses = [1]
        case .slotOfAnInactiveProgram:
            var inactive = other.days[1].slots[1]
            inactive.misses = [0, 1, 2]
            updates = [inactive]
        }
        let before = try await stack.texts("SELECT id || quote(deleted_at) FROM slot_miss ORDER BY id")
        let workout = S3Kit.mixed(1)
        try await stack.materialize(workout, slots: updates)
        #expect(try await stack.workouts.workout(id: workout.id) == workout)
        switch slotCase {
        case .unknownSlot, .removedSlot, .slotOfADeletedProgram:
            #expect(try await stack.texts("SELECT id || quote(deleted_at) FROM slot_miss ORDER BY id") == before)
        case .sameSlotTwice:
            #expect(try await stack.programs.active() == expected)
        case .slotOfAnInactiveProgram:
            #expect(try await stack.programs.program(id: other.id)?.days[1].slots[1].misses == [0, 1, 2])
            #expect(try await stack.programs.active() == program)
        }
    }
}

extension WorkoutLifecycleAdversarialTests {
    @Test("A miss cleared by one workout and recorded again by the next is stored again, once; so is a negative week")
    func clearedMiss_comesBack() async throws {
        let stack = try await S3Kit.stack()
        let program = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        var expected = program
        for (number, misses) in [[0, 1, 2], [], [1, -1], [-1], [0, 1, 2]].enumerated() {
            stack.clock.advance()
            expected.days[0].slots[0].misses = Set(misses)
            try await stack.materialize(S3Kit.mixed(number + 1), slots: [expected.days[0].slots[0]])
            #expect(try await stack.programs.active() == expected, "misses \(misses)")
        }
        let slot = expected.days[0].slots[0].id.rawValue.uuidString
        #expect(try await stack.texts("SELECT week_index FROM slot_miss WHERE slot_id = ?", [slot]).count == 4)
    }

    @Test("(documents) Deleting a workout leaves the misses it wrote, and its workout_health row")
    func delete_keepsMissesAndHealth() async throws {
        let stack = try await S3Kit.stack()
        let program = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        var slot = program.days[0].slots[0]
        slot.misses = [0, 1, 2]
        let workout = S3Kit.mixed(1)
        try await stack.materialize(workout, slots: [slot])
        try await stack.execute(
            "INSERT INTO workout_health (workout_id, avg_heart_rate, created_at, updated_at) VALUES (?, 120, 'a', 'a')",
            [workout.id.rawValue.uuidString]
        )
        try await stack.workouts.delete(id: workout.id)
        #expect(try await stack.programs.active()?.days[0].slots[0].misses == [0, 1, 2])
        #expect(try await S2Kit.count(stack.queue, "workout_health") == 1)
    }
}

extension WorkoutLifecycleAdversarialTests {
    /// A copy of `exercise` with another original exercise, which is a `let`.
    static func prescribed(_ original: ExerciseID, _ exercise: WorkoutExercise) -> WorkoutExercise {
        WorkoutExercise(
            id: exercise.id,
            slotID: exercise.slotID,
            exerciseID: exercise.exerciseID,
            originalExerciseID: original,
            name: exercise.name,
            equipment: exercise.equipment,
            step: exercise.step,
            rest: exercise.rest,
            rpe: exercise.rpe,
            isSupersetWithPrevious: exercise.isSupersetWithPrevious,
            targetSets: exercise.targetSets,
            targetReps: exercise.targetReps,
            targetLoad: exercise.targetLoad,
            sets: exercise.sets
        )
    }

    /// One stored field changed at a time, each to a value no fixture default has.
    static let fieldEdits: [(name: String, edit: @Sendable (inout WorkoutState) -> Void)] = [
        ("source", { $0.source = WorkoutSource(
            programID: ProgramID(S3Kit.uuid(1, 1)), weekIndex: -3, dayTemplateID: DayTemplateID(S3Kit.uuid(2, 2))
        ) }),
        ("isDeload", { $0.isDeload = true }),
        ("units", { $0.units = .kg }),
        ("originDevice", { $0.originDevice = DeviceID(S3Kit.uuid(0xD, 7)) }),
        ("startedAt", { $0.startedAt = S3Kit.day(-0.25) }),
        ("endedAt", { $0.endedAt = S3Kit.day(0.25) }),
        ("slotID", { $0.exercises[1].slotID = SlotID(S3Kit.uuid(5, 5)) }),
        ("exerciseID", { $0.exercises[1].exerciseID = S3Kit.press }),
        ("originalExerciseID", { $0.exercises[1] = prescribed(S3Kit.row, $0.exercises[1]) }),
        ("equipment", { $0.exercises[1].equipment = .kettlebell }),
        ("step", { $0.exercises[1].step = .kilograms(1.25) }),
        ("rest", { $0.exercises[1].rest = RestDuration(seconds: 300) ?? .defaultRest }),
        ("rpe", { $0.exercises[1].rpe = S3Kit.rpe(9.5) }),
        ("superset", { $0.exercises[1].isSupersetWithPrevious = true }),
        ("targetSets", { $0.exercises[1].targetSets = 7 }),
        ("targetReps", { $0.exercises[1].targetReps = 11 }),
        ("targetLoad", { $0.exercises[1].targetLoad = .kilograms(47.5) }),
        ("set kind", { $0.exercises[1].sets[0].kind = .warmup }),
        ("set tick", { $0.exercises[1].sets[0].doneAt = S3Kit.day(-0.125) })
    ]

    @Test("Every stored field of a workout and its exercises reads back, changed one at a time and all together")
    func everyField_isStoredAndDiffed() async throws {
        let stack = try await S3Kit.stack()
        let base = S3Kit.mixed(1)
        try await stack.materialize(base)
        var all = base
        for (name, edit) in Self.fieldEdits {
            var edited = base
            edit(&edited)
            edit(&all)
            #expect(edited != base, "\(name): the edit changes nothing")
            try await stack.materialize(edited)
            #expect(try await stack.workouts.workout(id: base.id) == edited, "\(name)")
        }
        try await stack.materialize(all)
        #expect(try await stack.workouts.workout(id: base.id) == all)
        let fresh = try await S3Kit.stack()
        try await fresh.materialize(all)
        #expect(try await fresh.workouts.recent(limit: 1) == [all])
    }
}
