import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criteria 1 and 2: a finished workout's `programUpdates` land with the save, on
/// a stored slot of the workout's own program and with a stored exercise; anything else is skipped and the
/// workout is still stored. Each test runs on the database and on LedgerFakes' linked stores; the expected
/// program is the fixture's, changed here.
@Suite("Adversarial F10 S3 · a program change lands with the save", .tags(.persistence), .timeLimit(.minutes(1)))
struct LinkedSaveAdversarialTests {
    typealias Kind = LinkedStores.Kind
    typealias Fixture = LinkedFixture

    /// `nil` when `stores` hold `expected` as program 1 and program 2 as built, and `workout` in history.
    static func issue(
        _ stores: LinkedStores,
        program expected: Program,
        holding workout: WorkoutState
    ) async throws -> String? {
        if let line = try await LinkedDifference.of(stores.program(1), expected, "program 1") {
            return line
        }
        if let line = try await LinkedDifference.of(stores.program(2), Fixture.program(2), "program 2") {
            return line
        }
        return try await stores.workouts.workout(id: workout.id) == nil ? "the workout is not in history" : nil
    }

    @Test(
        "An update of a slot of the workout's program sets its exercise, and nothing else of the program",
        arguments: Kind.allCases
    )
    func save_updateOfOwnSlot_setsTheExerciseAndNothingElse(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let (slot, missed) = try (Fixture.slot(0), Fixture.slot(4))
        let swapped = Fixture.other(than: slot)
        let workout = Fixture.workout(1, updates: [slot.id: swapped])
        let outcome = await stores.save(workout, slots: [Fixture.missing(missed, [0, 2])], droppingLog: false)
        #expect(outcome == "false")
        let expected = try Fixture.program(1)
            .changing(slot.id) { $0.exerciseID = swapped }
            .changing(missed.id) { $0.misses = [0, 2] }
        let issue = try await Self.issue(stores, program: expected, holding: workout)
        #expect(issue == nil, "\(issue ?? "")")
    }

    @Test(
        "Misses and an update for the same slot: both are written, and the slot's stale copy is not",
        arguments: Kind.allCases
    )
    func save_missesAndUpdateOfTheSameSlot_writesBoth(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(1)
        let swapped = Fixture.other(than: slot, offset: 2)
        let workout = Fixture.workout(1, updates: [slot.id: swapped])
        _ = await stores.save(workout, slots: [Fixture.missing(slot, [1])], droppingLog: false)
        let expected = try Fixture.program(1).changing(slot.id) {
            $0.exerciseID = swapped
            $0.misses = [1]
        }
        let issue = try await Self.issue(stores, program: expected, holding: workout)
        #expect(issue == nil, "\(issue ?? "")")
    }

    @Test(
        "A slot of another program, a slot that never was, an exercise that is not stored: each is skipped",
        arguments: Kind.allCases
    )
    func save_whatCannotBeApplied_isSkippedAndTheRestApplied(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let (applied, unstored, foreign) = try (Fixture.slot(2), Fixture.slot(3), Fixture.slot(0, of: 2))
        let swapped = Fixture.other(than: applied)
        let workout = Fixture.workout(1, updates: [
            applied.id: swapped,
            unstored.id: Fixture.unknownExercise,
            foreign.id: Fixture.other(than: foreign),
            Fixture.unknownSlot: swapped
        ])
        #expect(await stores.save(workout, droppingLog: false) == "false", "a skipped entry never fails the save")
        let expected = try Fixture.program(1).changing(applied.id) { $0.exerciseID = swapped }
        let issue = try await Self.issue(stores, program: expected, holding: workout)
        #expect(issue == nil, "\(issue ?? "")")
    }

    @Test("An ad-hoc workout, and a workout of another program, change no slot of this one", arguments: Kind.allCases)
    func save_updateFromOutsideTheProgram_isSkipped(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let update = [slot.id: Fixture.other(than: slot)]
        let (adHoc, stranger) = (
            Fixture.workout(1, ofProgram: nil, updates: update),
            Fixture.workout(2, ofProgram: 2, updates: update)
        )
        #expect(await stores.save(adHoc, droppingLog: false) == "false")
        #expect(await stores.save(stranger, droppingLog: false) == "false")
        let issue = try await Self.issue(stores, program: Fixture.program(1), holding: stranger)
        #expect(issue == nil, "\(issue ?? "")")
        #expect(try await stores.workouts.recent(limit: 9).count == 2)
    }

    @Test(
        "A workout of a stored program that is not the active one still updates its own slot",
        arguments: Kind.allCases
    )
    func save_updateOfTheWorkoutsInactiveProgram_isApplied(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(5, of: 2)
        let swapped = Fixture.other(than: slot)
        _ = await stores.save(Fixture.workout(1, ofProgram: 2, updates: [slot.id: swapped]), droppingLog: false)
        let expected = try Fixture.program(2).changing(slot.id) { $0.exerciseID = swapped }
        let issue = try await LinkedDifference.of(stores.program(2), expected, "program 2")
        #expect(issue == nil, "\(issue ?? "")")
        #expect(
            try await stores.programs.active()?.id == S2Kit.programID(1),
            "and the active program is still program 1"
        )
    }

    @Test("A slot removed during the workout is skipped and does not come back", arguments: Kind.allCases)
    func save_updateOfASlotRemovedSince_isSkipped(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        var edited = try Fixture.program(1)
        let removed = edited.days[0].slots.remove(at: 1)
        try await stores.programs.save(edited)
        let kept = edited.days[0].slots[0]
        let workout = Fixture.workout(
            1,
            updates: [removed.id: Fixture.other(than: removed), kept.id: Fixture.other(than: kept)]
        )
        #expect(await stores.save(workout, slots: [Fixture.missing(removed, [2])], droppingLog: false) == "false")
        let expected = edited.changing(kept.id) { $0.exerciseID = Fixture.other(than: kept) }
        let issue = try await Self.issue(stores, program: expected, holding: workout)
        #expect(issue == nil, "\(issue ?? "")")
    }

    @Test("A program deleted during the workout is left alone, also when it is saved again", arguments: Kind.allCases)
    func save_updateOfADeletedProgram_isSkipped(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        try await stores.programs.delete(S2Kit.programID(1))
        let workout = Fixture.workout(1, updates: [slot.id: Fixture.other(than: slot)])
        #expect(await stores.save(workout, slots: [Fixture.missing(slot, [0, 1, 2])], droppingLog: false) == "false")
        #expect(try await stores.program(1) == nil)
        #expect(try await stores.workouts.workout(id: workout.id) != nil, "the workout is still stored")
        try await stores.programs.save(Fixture.program(1))
        let issue = try await Self.issue(stores, program: Fixture.program(1), holding: workout)
        #expect(issue == nil, "\(issue ?? "")")
    }
}
