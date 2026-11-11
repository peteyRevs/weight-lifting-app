import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criterion 3: "Materialising the same finished workout again leaves every row
/// of every table as it was, the program's included." On the database the rows are compared as stored, their
/// timestamps too, with the clock moved between the saves; on both kinds of store, what the protocols read.
@Suite("Adversarial F10 S3 · saving twice changes nothing", .tags(.persistence), .timeLimit(.minutes(1)))
struct LinkedSaveTwiceAdversarialTests {
    typealias Kind = LinkedStores.Kind
    typealias Fixture = LinkedFixture
    typealias Scene = LinkedSaveFaultAdversarialTests.Scene

    @Test("A second and a third save of the same workout change no row of any table", arguments: [true, false])
    func saveAgain_sameWorkout_changesNoRow(droppingLog: Bool) async throws {
        let scene = try await Scene()
        let first = await scene.stores.save(scene.workout, slots: scene.slots, droppingLog: droppingLog)
        #expect(first == "\(droppingLog)")
        let before = try await scene.stores.dump()
        for attempt in ["second", "third"] {
            scene.stores.clock.advance(seconds: 3600)
            let outcome = await scene.stores.save(scene.workout, slots: scene.slots, droppingLog: droppingLog)
            #expect(outcome == "\(droppingLog)")
            let rows = try await LinkedStores.difference(before, scene.stores.dump())
            #expect(rows == nil, "the \(attempt) save: \(rows ?? "")")
        }
    }

    @Test("A second save that is asked for the log, after a first that was not, changes the log's table alone")
    func saveAgain_nowDroppingTheLog_changesOnlyTheLog() async throws {
        let scene = try await Scene()
        _ = await scene.stores.save(scene.workout, slots: scene.slots, droppingLog: false)
        let before = try await scene.stores.dump()
        scene.stores.clock.advance(seconds: 3600)
        #expect(await scene.save() == "true")
        let rows = try await LinkedStores.difference(before, scene.stores.dump())
        #expect(rows == "workout_event: 5 rows, then 0, 5 differ", "\(rows ?? "no row changed")")
    }

    @Test("Saving twice leaves what the protocols read as it was, on both kinds of store", arguments: Kind.allCases)
    func saveAgain_sameWorkout_readsTheSame(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let (slot, missed) = try (Fixture.slot(1), Fixture.slot(3))
        let workout = Fixture.workout(
            1,
            updates: [slot.id: Fixture.other(than: slot), Fixture.unknownSlot: slot.exerciseID]
        )
        var model = try LinkedModel(programs: [Fixture.program(1), Fixture.program(2)])
        for _ in 0 ..< 3 {
            let outcome = await stores.save(workout, slots: [Fixture.missing(missed, [2])], droppingLog: true)
            #expect(outcome == "\(model.save(workout, slots: [Fixture.missing(missed, [2])], droppingLog: true))")
            let issue = try await model.difference(from: stores)
            #expect(issue == nil, "\(issue ?? "")")
            stores.clock.advance()
        }
        #expect(try await stores.workouts.recent(limit: 9).count == 1)
    }

    @Test("An update to the exercise a slot already holds writes nothing, not even a timestamp")
    func save_updateToTheSameExercise_writesNothingToTheProgram() async throws {
        let stores = try await LinkedStores.make(.database)
        let slot = try Fixture.slot(0)
        let before = try await stores.dump()
        stores.clock.advance(seconds: 3600)
        #expect(await stores
            .save(Fixture.workout(1, updates: [slot.id: slot.exerciseID]), droppingLog: false) == "false")
        let after = try await stores.dump()
        let programTables = ["program", "program_week", "day_template", "slot", "slot_miss"]
        let rows = LinkedStores.difference(
            before.filter { programTables.contains($0.key) },
            after.filter { programTables.contains($0.key) }
        )
        #expect(rows == nil, "\(rows ?? "")")
    }

    /// The same slot twice can only come from two saves: `programUpdates` holds one exercise a slot. Since F10
    /// S8a (G3 SF1, ruled) only a workout's first save writes its program changes, so the first save's exercise
    /// stands (before S8a the later one's did).
    @Test(
        "The same workout saved again with another exercise for the slot: the first save's exercise stands",
        arguments: Kind.allCases
    )
    func saveAgain_anotherExerciseForTheSlot_theFirstStands(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(2)
        let (first, second) = (Fixture.other(than: slot, offset: 1), Fixture.other(than: slot, offset: 2))
        _ = await stores.save(Fixture.workout(1, updates: [slot.id: first]), droppingLog: false)
        _ = await stores.save(Fixture.workout(1, updates: [slot.id: second]), droppingLog: false)
        var issue = try await LinkedDifference.of(
            stores.program(1),
            Fixture.program(1).changing(slot.id) { $0.exerciseID = first },
            "program 1"
        )
        #expect(issue == nil, "\(issue ?? "")")
        // Saved a third time with no update: a save sets what it is asked to and undoes nothing.
        _ = await stores.save(Fixture.workout(1), droppingLog: false)
        issue = try await LinkedDifference.of(
            stores.program(1),
            Fixture.program(1).changing(slot.id) { $0.exerciseID = first },
            "program 1"
        )
        #expect(issue == nil, "\(issue ?? "")")
    }

    /// The upsert is not a no-op once the program has moved on: F05's input 6 warned of this for misses. For a
    /// swap it no longer holds: since F10 S8a (G3 SF1, ruled) only a workout's first save writes its program
    /// changes, so saving it again leaves the lifter's later edit (before S8a it set the slot back).
    @Test(
        "(documents) Saving an old workout again leaves a later edit of the program",
        arguments: Kind.allCases
    )
    func saveAgain_afterTheProgramWasEdited_leavesTheEdit(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(2)
        let workout = Fixture.workout(1, updates: [slot.id: Fixture.other(than: slot)])
        _ = await stores.save(workout, droppingLog: false)
        try await stores.programs.save(Fixture.program(1))
        #expect(try await stores.program(1) == Fixture.program(1), "the lifter put the exercise back")
        _ = await stores.save(workout, droppingLog: false)
        let issue = try await LinkedDifference.of(stores.program(1), Fixture.program(1), "program 1")
        #expect(issue == nil, "\(issue ?? "")")
    }
}
