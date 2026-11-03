import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criterion 4 and the answer of `materialize(_:slotUpdates:droppingLog:)`: "When
/// it succeeds, no event of that workout remains; when it fails, nothing changed: no history row, no program
/// change, the log whole." And what the returned `Bool` says in each case: whether the log went with the save.
@Suite("Adversarial F10 S3 · the log goes with the save", .tags(.persistence), .timeLimit(.minutes(1)))
struct LinkedSaveLogAdversarialTests {
    typealias Kind = LinkedStores.Kind
    typealias Fixture = LinkedFixture

    /// Stores holding a log of four envelopes for workout 1 and of six for workout 2.
    struct Logged {
        let stores: LinkedStores
        let one = Fixture.workout(1)
        let two = Fixture.workout(2)

        init(_ kind: Kind) async throws {
            stores = try await LinkedStores.make(kind)
            _ = try await stores.events.append(Fixture.log(of: one, count: 4))
            _ = try await stores.events.append(Fixture.log(of: two, count: 6))
        }
    }

    @Test(
        "Asked to drop the log, a save drops that workout's log and no other, and answers true",
        arguments: Kind.allCases
    )
    func save_droppingLog_dropsThatLogOnly(kind: Kind) async throws {
        let logged = try await Logged(kind)
        let (stores, one, two) = (logged.stores, logged.one, logged.two)
        #expect(await stores.save(one, droppingLog: true) == "true")
        #expect(try await stores.logCount(one) == 0, "no event of that workout remains")
        #expect(try await stores.logCount(two) == 6)
        #expect(try await stores.events.uncompactedWorkoutIDs() == [two.id])
        #expect(try await stores.events.highestSeq(for: one.id, device: S3Kit.device) == nil)
        #expect(try await stores.workouts.workout(id: one.id) != nil)
    }

    @Test("Not asked, a save leaves the log whole and answers false", arguments: Kind.allCases)
    func save_notDroppingLog_leavesTheLog(kind: Kind) async throws {
        let logged = try await Logged(kind)
        let (stores, one, two) = (logged.stores, logged.one, logged.two)
        let log = try await Set(stores.events.envelopes(for: one.id))
        #expect(await stores.save(one, droppingLog: false) == "false")
        #expect(try await Set(stores.events.envelopes(for: one.id)) == log)
        #expect(try await stores.logCount(two) == 6)
        #expect(await stores.save(one, droppingLog: true) == "true", "and a later save takes it")
        #expect(try await stores.events.uncompactedWorkoutIDs() == [two.id])
    }

    @Test(
        "Asked to drop a log that is not there, a save still answers true: nothing is left to compact",
        arguments: Kind.allCases
    )
    func save_droppingALogThatIsNotThere_answersTrue(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let workout = Fixture.workout(3)
        #expect(await stores.save(workout, droppingLog: true) == "true")
        #expect(await stores.save(workout, droppingLog: true) == "true")
        #expect(try await stores.events.uncompactedWorkoutIDs().isEmpty)
    }

    /// A workout the stores refuse, each for one reason, with misses, a program update and its log to drop.
    static func refused() throws -> [(name: String, workout: WorkoutState)] {
        let slot = try Fixture.slot(0)
        let base = Fixture.workout(1, updates: [slot.id: Fixture.other(than: slot)])
        var unfinished = base
        unfinished.phase = .live
        var endless = base
        endless.endedAt = nil
        var named = base
        named.name = "Upper\u{0}A"
        var eighth = base
        eighth.exercises[0].sets[0].weight = .pounds(0.125)
        var twice = base
        twice.exercises[1].sets[1] = LoggedSet(
            id: twice.exercises[0].sets[0].id, weight: .pounds(45), reps: .one, kind: .working
        )
        return [
            ("live", unfinished),
            ("no end", endless),
            ("NUL in its name", named),
            ("an eighth of a pound", eighth),
            ("a set id twice", twice)
        ]
    }

    @Test(
        "A refused save changes nothing: no history row, no miss, no program change, the log whole",
        arguments: Kind.allCases
    )
    func save_refused_changesNothing(kind: Kind) async throws {
        for (name, workout) in try Self.refused() {
            let logged = try await Logged(kind)
            let (stores, one) = (logged.stores, logged.one)
            let (log, before) = try await (Set(stores.events.envelopes(for: one.id)), stores.dump())
            let slot = try Fixture.slot(0)
            let outcome = await stores.save(workout, slots: [Fixture.missing(slot, [0, 1, 2])], droppingLog: true)
            #expect(outcome != "true" && outcome != "false", "\(name): saved, \(outcome)")
            let program = try await LinkedDifference.of(stores.program(1), Fixture.program(1), "program 1")
            #expect(program == nil, "\(name): \(program ?? "")")
            #expect(try await stores.workouts.recent(limit: 9).isEmpty, "\(name): a history row")
            #expect(try await Set(stores.events.envelopes(for: one.id)) == log, "\(name): the log is not whole")
            let rows = try await LinkedStores.difference(before, stores.dump())
            #expect(rows == nil, "\(name): \(rows ?? "")")
        }
    }

    @Test("A repository that holds no log saves and answers false, whatever it is asked")
    func save_repositoryWithoutALog_answersFalse() async throws {
        let programs = try InMemoryProgramRepository(programs: [Fixture.program(1)])
        let unlinked = InMemoryWorkoutRepository(programs: programs)
        let workout = Fixture.workout(1)
        #expect(try await unlinked.materialize(workout, slotUpdates: [], droppingLog: true) == false)
        #expect(try await unlinked.materialize(workout, slotUpdates: [], droppingLog: false) == false)
        #expect(try await unlinked.workout(id: workout.id) != nil)
    }

    /// A wrapper written before S3: it forwards the calls it knows and inherits the new one's default.
    struct OldWrapper: WorkoutRepository {
        let base: any WorkoutRepository

        func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog _: Bool) async throws -> Bool {
            try await base.materialize(workout, slotUpdates: slotUpdates)
            return false
        }

        func workout(id: WorkoutID) async throws -> WorkoutState? {
            try await base.workout(id: id)
        }

        func recent(limit: Int) async throws -> [WorkoutState] {
            try await base.recent(limit: limit)
        }

        func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
            try await base.workouts(in: range)
        }

        func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
            try await base.updateSets(workoutExerciseID: workoutExerciseID, sets: sets)
        }

        func delete(id: WorkoutID) async throws {
            try await base.delete(id: id)
        }

        func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
            base.observeRecent(limit: limit)
        }

        func historyEntries() async throws -> [HistoryEntry] {
            try await base.historyEntries()
        }

        func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
            base.observeHistoryEntries()
        }
    }

    @Test(
        "A wrapper that does not forward the new call saves, keeps the log and answers false",
        arguments: Kind.allCases
    )
    func save_throughAWrapperOfBeforeS3_keepsTheLogAndSaysSo(kind: Kind) async throws {
        let logged = try await Logged(kind)
        let (stores, one) = (logged.stores, logged.one)
        let slot = try Fixture.slot(0)
        var workout = one
        workout.programUpdates = [slot.id: Fixture.other(than: slot)]
        let wrapped = OldWrapper(base: stores.workouts)
        #expect(try await wrapped.materialize(workout, slotUpdates: [], droppingLog: true) == false)
        #expect(try await stores.logCount(one) == 4, "the log is the caller's to compact")
        let expected = try Fixture.program(1).changing(slot.id) { $0.exerciseID = Fixture.other(than: slot) }
        let program = try await LinkedDifference.of(stores.program(1), expected, "program 1")
        #expect(program == nil, "the program change is not lost with the transaction: \(program ?? "")")
    }
}

/// F13 S2's requirement, outside the suite's body (which the lint holds to 150 lines).
extension LinkedSaveLogAdversarialTests.OldWrapper {
    func observeWorkout(id: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        base.observeWorkout(id: id)
    }
}
