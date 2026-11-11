import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S8a adversarial round 1 (G2): a swap's program change is compare-and-set, lands in the save's
/// transaction, and history keeps the replacement. Each test runs on the database and on LedgerFakes' linked
/// stores. Expected values come from the S8 plan (criteria 8–10) and the orchestrator's rulings after G1:
/// (1) an entry whose slot no workout exercise came from is applied without the check; (2) of two saved
/// workouts that swapped the same slot, the earlier lands and the later is skipped.
@Suite("Adversarial F10 S8a · the swap's save", .tags(.persistence), .timeLimit(.minutes(1)))
struct SwapSaveAdversarialTests {
    typealias Kind = LinkedStores.Kind
    typealias Fixture = LinkedFixture

    @Test("The slot still holds the original: the swap's exercise lands", arguments: Kind.allCases)
    func save_slotUnchanged_applies(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let swapped = Fixture.other(than: slot)
        let workout = SwapSaveKit.workout(1, from: slot, performing: swapped, updates: [slot.id: swapped])
        #expect(await stores.save(workout, droppingLog: false) == "false")
        #expect(try await SwapSaveKit.slotExercise(stores, slot) == swapped)
    }

    @Test("The program was edited during the workout: the edit stays, the workout is stored", arguments: Kind.allCases)
    func save_slotEditedMeanwhile_keepsTheEdit(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let (swapped, edited) = (Fixture.other(than: slot), Fixture.other(than: slot, offset: 2))
        try await SwapSaveKit.editSlot(stores, slot, to: edited)
        let workout = SwapSaveKit.workout(1, from: slot, performing: swapped, updates: [slot.id: swapped])
        #expect(await stores.save(workout, droppingLog: false) == "false")
        #expect(try await SwapSaveKit.slotExercise(stores, slot) == edited)
        #expect(try await stores.workouts.workout(id: workout.id) != nil)
        // A second save changes nothing.
        #expect(await stores.save(workout, droppingLog: false) == "false")
        #expect(try await SwapSaveKit.slotExercise(stores, slot) == edited)
    }

    @Test(
        "Edited away and back to the original during the workout: the swap still lands (compare, not version)",
        arguments: Kind.allCases
    )
    func save_slotEditedAndBack_applies(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let swapped = Fixture.other(than: slot)
        try await SwapSaveKit.editSlot(stores, slot, to: Fixture.other(than: slot, offset: 2))
        try await SwapSaveKit.editSlot(stores, slot, to: slot.exerciseID)
        let workout = SwapSaveKit.workout(1, from: slot, performing: swapped, updates: [slot.id: swapped])
        _ = await stores.save(workout, droppingLog: false)
        #expect(try await SwapSaveKit.slotExercise(stores, slot) == swapped)
    }

    @Test(
        "Ruling 1: an entry for a slot no workout exercise came from is applied without the check",
        arguments: Kind.allCases
    )
    func save_entryWithoutAnOriginal_appliesUnchecked(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let (own, foreign) = try (Fixture.slot(0), Fixture.slot(1))
        let target = Fixture.other(than: foreign, offset: 3)
        try await SwapSaveKit.editSlot(stores, foreign, to: Fixture.other(than: foreign, offset: 2))
        let workout = SwapSaveKit.workout(1, from: own, performing: own.exerciseID, updates: [foreign.id: target])
        _ = await stores.save(workout, droppingLog: false)
        #expect(try await SwapSaveKit.slotExercise(stores, foreign) == target)
    }

    @Test(
        "Ruling 2: two saved workouts swapped one slot; at one launch the earlier lands, the later is skipped",
        arguments: Kind.allCases,
        [false, true]
    )
    func save_twoWorkoutsOneSlot_firstSavedWins(kind: Kind, laterFirst: Bool) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let (first, second) = (Fixture.other(than: slot), Fixture.other(than: slot, offset: 2))
        let earlier = SwapSaveKit.workout(1, from: slot, performing: first, updates: [slot.id: first])
        let later = SwapSaveKit.workout(2, from: slot, performing: second, updates: [slot.id: second])
        let order = laterFirst ? [later, earlier] : [earlier, later]
        for workout in order {
            #expect(await stores.save(workout, droppingLog: false) == "false")
        }
        #expect(
            try await SwapSaveKit.slotExercise(stores, slot) == (laterFirst ? second : first),
            "the first materialised lands; the other finds the slot changed"
        )
        #expect(try await stores.workouts.recent(limit: 9).count == 2)
    }

    @Test(
        "Swap back to the original with the toggle on: nothing changes, even after a program edit",
        arguments: Kind.allCases
    )
    func save_backToTheOriginal_changesNothing(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let edited = Fixture.other(than: slot, offset: 2)
        try await SwapSaveKit.editSlot(stores, slot, to: edited)
        let workout = SwapSaveKit.workout(
            1,
            from: slot,
            performing: slot.exerciseID,
            updates: [slot.id: slot.exerciseID]
        )
        _ = await stores.save(workout, droppingLog: false)
        #expect(try await SwapSaveKit.slotExercise(stores, slot) == edited)
    }
}

@Suite("Adversarial F10 S8a · the swap's save, history and atomicity", .tags(.persistence), .timeLimit(.minutes(1)))
struct SwapSaveHistoryAdversarialTests {
    typealias Kind = LinkedStores.Kind
    typealias Fixture = LinkedFixture

    @Test(
        "An unknown exercise swapped in: the workout is stored with it, the slot is untouched",
        arguments: Kind.allCases
    )
    func save_unknownExercise_storesTheWorkout(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let workout = SwapSaveKit.workout(
            1,
            from: slot,
            performing: Fixture.unknownExercise,
            updates: [slot.id: Fixture.unknownExercise]
        )
        #expect(await stores.save(workout, droppingLog: false) == "false")
        #expect(try await SwapSaveKit.slotExercise(stores, slot) == slot.exerciseID)
        let stored = try await stores.workouts.workout(id: workout.id)
        #expect(stored?.exercises.first?.exerciseID == Fixture.unknownExercise)
    }

    @Test("History keeps the replacement's id, name, equipment and step, and the original", arguments: Kind.allCases)
    func save_history_keepsTheReplacement(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let swapped = Fixture.other(than: slot)
        let workout = SwapSaveKit.workout(1, from: slot, performing: swapped, updates: [:])
        _ = await stores.save(workout, droppingLog: false)
        let stored = try #require(try await stores.workouts.workout(id: workout.id)?.exercises.first)
        #expect(stored.exerciseID == swapped && stored.originalExerciseID == slot.exerciseID)
        #expect(stored.equipment == .kettlebell && stored.step == .kilograms(2) && stored.name == "Swapped")
        #expect(stored.targetLoad == .kilograms(16) && stored.slotID == slot.id)
    }

    @Test("The slot write fails: neither the workout nor the program change is stored, the log is kept")
    func save_slotWriteRefused_leavesNeither() async throws {
        let stores = try await LinkedStores.make(.database)
        let queue = try #require(stores.queue)
        let slot = try Fixture.slot(0)
        let swapped = Fixture.other(than: slot)
        let workout = SwapSaveKit.workout(1, from: slot, performing: swapped, updates: [slot.id: swapped])
        _ = try await stores.events.append(Fixture.log(of: workout))
        try await queue.write {
            try $0.execute(sql: "CREATE TRIGGER g2 BEFORE UPDATE ON slot BEGIN SELECT RAISE(ABORT, 'g2'); END")
        }
        stores.clock.advance()
        let before = try await stores.dump()
        let outcome = await stores.save(workout, droppingLog: true)
        let after = try await stores.dump()
        #expect(outcome.contains("g2"))
        let changed = LinkedStores.difference(before, after)
        #expect(changed == nil, "\(changed ?? "")")
        try await queue.write { try $0.execute(sql: "DROP TRIGGER g2") }
        #expect(await stores.save(workout, droppingLog: true) == "true")
        #expect(try await SwapSaveKit.slotExercise(stores, slot) == swapped)
        #expect(try await stores.logCount(workout) == 0)
    }

    @Test("A log with a replacement swap round-trips through the event store", arguments: Kind.allCases)
    func eventStore_replacementSwap_roundTrips(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let workout = Fixture.workout(1)
        let swap = try WorkoutEvent.exerciseSwapped(
            exerciseIndex: 0, exerciseID: Fixture.unknownExercise, name: "Kettlebell Floor Press",
            alsoUpdateProgram: true,
            replacement: SwappedExercise(
                equipment: .kettlebell, step: .kilograms(2),
                load: .kilograms(#require(Decimal(string: "83.91458845"))),
                lastPerformance: LastPerformance(
                    date: Date(timeIntervalSinceReferenceDate: 811_228_800.000_123),
                    sets: 3,
                    reps: 8,
                    load: .pounds(#require(Decimal(string: "52.5")))
                )
            )
        )
        let log = EventBuilders.log(from: [swap, swap], device: S3Kit.device, workoutID: workout.id)
        _ = try await stores.events.append(log)
        let read = try await stores.events.envelopes(for: workout.id)
        let same = read.sorted() == log.sorted() // the store promises no order
        #expect(same, "\(read.count) envelopes read of \(log.count)")
    }
}

/// Builders for the S8a save suites.
enum SwapSaveKit {
    /// Finished workout `number` of program 1 whose first exercise came from `slot` (its original the slot's
    /// exercise), now performing `performed`, with `updates`.
    static func workout(
        _ number: Int,
        from slot: Slot,
        performing performed: ExerciseID,
        updates: [SlotID: ExerciseID]
    ) -> WorkoutState {
        var workout = LinkedFixture.workout(number, updates: updates)
        let first = workout.exercises[0]
        workout.exercises[0] = WorkoutExercise(
            id: first.id, slotID: slot.id, exerciseID: performed, originalExerciseID: slot.exerciseID,
            name: "Swapped", equipment: .kettlebell, step: .kilograms(2), rest: first.rest, rpe: first.rpe,
            isSupersetWithPrevious: false, targetSets: first.targetSets, targetReps: first.targetReps,
            targetLoad: .kilograms(16), sets: first.sets
        )
        return workout
    }

    static func slotExercise(_ stores: LinkedStores, _ slot: Slot) async throws -> ExerciseID? {
        try await stores.program(1)?.days.flatMap(\.slots).first { $0.id == slot.id }?.exerciseID
    }

    static func editSlot(_ stores: LinkedStores, _ slot: Slot, to exercise: ExerciseID) async throws {
        let program = try #require(try await stores.program(1))
        try await stores.programs.save(program.changing(slot.id) { $0.exerciseID = exercise })
    }
}
