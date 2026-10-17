import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S3 criteria 1 and 5, on the host: a swap with "Also update program" reaches the program when the
/// workout is saved, in the save's one store call, and at no other time. A discarded workout leaves the
/// program alone, and so does a save that fails, until its retry.
@Suite("LocalWorkoutSessionActor · program changes", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorProgramTests {
    static let end = Fixtures.now.addingTimeInterval(3600)

    /// A host over the bundled catalog and the active seed program, its Upper A session live, and the bench
    /// press of its first slot swapped for the overhead press.
    static func swapped(alsoUpdateProgram: Bool = true) async throws -> (subject: Subject, workout: WorkoutState) {
        let seed = try InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), programs: [Fixtures.seedProgram()])
        let subject = Subject(seed: seed)
        try await subject.host.start(Fixtures.seedSession())
        let workout = try await subject.host.apply(.exerciseSwapped(
            exerciseIndex: 0,
            exerciseID: Fixtures.CatalogID.overheadPress,
            name: "Overhead Press",
            alsoUpdateProgram: alsoUpdateProgram
        ))
        await subject.probe.clearCalls()
        return (subject, workout)
    }

    /// The seed program as stored, whichever program is active.
    static func program(in subject: Subject) async throws -> Program {
        try await subject.stores.programs.setActive(Fixtures.programID)
        return try #require(await subject.stores.programs.active())
    }

    /// What differs between the stored seed program and `expected`, in a line, or `nil`: an expectation
    /// compares this, never two whole programs.
    static func difference(in subject: Subject, from expected: Program) async throws -> String? {
        try await program(in: subject).difference(from: expected)
    }

    static func isSaved(_ workout: WorkoutState, in subject: Subject) async throws -> Bool {
        try await subject.stores.workouts.workout(id: workout.id) != nil
    }

    /// The seed program with its first slot's exercise swapped, and the misses a finish with no set logged
    /// leaves on Upper A's five slots in week 5.
    static func swappedProgram(misses: Set<Int> = [4]) throws -> Program {
        var program = try Fixtures.seedProgram()
        program.days[0].slots[0].exerciseID = Fixtures.CatalogID.overheadPress
        for index in program.days[0].slots.indices {
            program.days[0].slots[index].misses = misses
        }
        return program
    }

    @Test("A swap with the program lands when the workout is saved: one store call, the slot's exercise and no more")
    func finish_afterASwapWithTheProgram_changesTheSlot() async throws {
        let (subject, workout) = try await Self.swapped()
        #expect(workout.programUpdates == [workout.exercises[0].slotID: Fixtures.CatalogID.overheadPress])
        // Until the save the program is as it was.
        #expect(try await Self.difference(in: subject, from: Fixtures.seedProgram()) == nil)
        _ = try await subject.host.finish(endedAt: Self.end)
        #expect(await subject.writes() == [.append, .materialize])
        #expect(try await Self.difference(in: subject, from: Self.swappedProgram()) == nil)
        #expect(try await subject.stores.workouts.workout(id: workout.id)?.exercises[0].name == "Overhead Press")
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
    }

    @Test("A swap for this workout only changes no program")
    func finish_afterASwapWithoutTheProgram_leavesIt() async throws {
        let (subject, workout) = try await Self.swapped(alsoUpdateProgram: false)
        #expect(workout.programUpdates.isEmpty)
        _ = try await subject.host.finish(endedAt: Self.end)
        #expect(try await Self.program(in: subject).days[0].slots[0].exerciseID == Fixtures.CatalogID.benchPress)
    }

    @Test("A discarded workout leaves the program alone, whatever its swaps asked for")
    func discard_leavesTheProgramAlone() async throws {
        let (subject, _) = try await Self.swapped()
        try await subject.host.discard(endedAt: Self.end)
        #expect(try await Self.difference(in: subject, from: Fixtures.seedProgram()) == nil)
        #expect(try await subject.stores.workouts.recent(limit: 5).isEmpty)
    }

    @Test("A save that fails changes no program; the retry, or the next launch, saves the workout and the change")
    func finish_saveFails_theProgramWaitsWithTheWorkout() async throws {
        let (subject, workout) = try await Self.swapped()
        await subject.probe.fail(.materialize, times: 2)
        _ = await failure { _ = try await subject.host.finish(endedAt: Self.end) }
        #expect(try await Self.difference(in: subject, from: Fixtures.seedProgram()) == nil)
        _ = await failure { try await subject.relaunched().host.resumeFromStore() }
        #expect(try await Self.difference(in: subject, from: Fixtures.seedProgram()) == nil)
        #expect(try await !Self.isSaved(workout, in: subject))
        let resumed = try await subject.relaunched().host.resumeFromStore()
        #expect(resumed?.id == nil)
        #expect(try await Self.difference(in: subject, from: Self.swappedProgram()) == nil)
        #expect(try await Self.isSaved(workout, in: subject))
    }

    @Test("The change goes to the workout's own program, active or not, and to no other")
    func finish_anotherProgramActive_changesTheWorkoutsProgram() async throws {
        let (subject, _) = try await Self.swapped()
        let other = try Seeders.program(
            number: 7, weeks: 2, days: 1, slotsPerDay: 1, exercises: [Fixtures.CatalogID.benchPress]
        )
        try await subject.stores.programs.save(other)
        _ = try await subject.host.finish(endedAt: Self.end)
        let active = try #require(await subject.stores.programs.active())
        #expect(active.difference(from: other) == nil)
        // No miss is written for a program that is not active (S2, ruling O9); the swap still lands on it.
        var expected = try Self.swappedProgram(misses: [])
        expected.isActive = true
        #expect(try await Self.difference(in: subject, from: expected) == nil)
    }

    /// A finished log of week 5's Upper A, started `days` after the fixture's now under workout id `number`,
    /// whose only event before its end swaps the first slot's exercise for `exercise`, in the program too.
    static func swapLog(_ number: Int, afterDays days: Double, to exercise: ExerciseID) throws -> [EventEnvelope] {
        let program = try Fixtures.seedProgram()
        let start = Fixtures.now.addingTimeInterval(86400 * days)
        let session = try SessionBuilder.build(
            program: program,
            weekIndex: 4,
            day: program.days[0],
            exercises: Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first },
            history: [:],
            settings: Fixtures.settingsLb,
            id: WorkoutID(Fixtures.uuid(number)),
            device: Subject.device,
            now: start
        )
        let events: [WorkoutEvent] = [
            .started(session),
            .exerciseSwapped(exerciseIndex: 0, exerciseID: exercise, name: "Swapped", alsoUpdateProgram: true),
            .finished(endedAt: start.addingTimeInterval(3600))
        ]
        return EventBuilders.log(from: events, startingAt: start, workoutID: session.id)
    }

    /// F10 S3 review N5: two finished workouts found at one launch are saved in the order they started, so
    /// the later one's swap is the one the program keeps, whichever log the store lists first.
    @Test("Two finished logs at one launch: the later workout's swap lands last", arguments: [true, false])
    func recovery_twoFinishedLogs_areSavedInTheOrderTheyStarted(laterListedFirst: Bool) async throws {
        let earlier = try Self.swapLog(7001, afterDays: 0, to: Fixtures.CatalogID.overheadPress)
        let later = try Self.swapLog(7002, afterDays: 1, to: Fixtures.CatalogID.inclineDBPress)
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(
            catalog: ExerciseCatalog.seed(),
            programs: [Fixtures.seedProgram()],
            envelopes: earlier + later
        ))
        let listed = [earlier, later].compactMap(\.first?.workoutID)
        let events = ListedEventStore(base: stores.events, order: laterListedFirst ? listed.reversed() : listed)
        let host = LocalWorkoutSessionActor(
            events: events, workouts: stores.workouts, programs: stores.programs,
            device: Subject.device, now: { Fixtures.now }
        )
        let resumed = try await host.resumeFromStore()
        #expect(resumed?.id == nil)
        #expect(try await stores.workouts.recent(limit: 5).map(\.id) == listed.reversed())
        let slot = try #require(await stores.programs.active()).days[0].slots[0]
        #expect(slot.exerciseID == Fixtures.CatalogID.inclineDBPress, "the earlier workout's swap was written last")
        #expect(await stores.events.uncompactedWorkoutIDs() == [])
    }
}

/// An event store that lists its logs in a given order, and is otherwise `base`: a store may list them in
/// any order (`WorkoutEventStore.uncompactedWorkoutIDs()`), and the host must not depend on which.
struct ListedEventStore: WorkoutEventStore {
    let base: InMemoryWorkoutEventStore
    let order: [WorkoutID]

    func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope] {
        try await base.append(envelopes)
    }

    func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope] {
        await base.envelopes(for: workout)
    }

    func unreadableCount(for workout: WorkoutID) async throws -> Int {
        await base.unreadableCount(for: workout)
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64? {
        await base.highestSeq(for: workout, device: device)
    }

    func uncompactedWorkoutIDs() async throws -> [WorkoutID] {
        let stored = await base.uncompactedWorkoutIDs()
        return order.filter(stored.contains) + stored.filter { !order.contains($0) }
    }

    func newestWallClock() async throws -> Date? {
        try await base.newestWallClock()
    }

    func compact(workout: WorkoutID) async throws {
        await base.compact(workout: workout)
    }
}
