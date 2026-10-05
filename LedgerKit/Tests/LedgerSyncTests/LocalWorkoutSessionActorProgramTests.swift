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
        #expect(try await Self.program(in: subject) == Fixtures.seedProgram())
        _ = try await subject.host.finish(endedAt: Self.end)
        #expect(await subject.writes() == [.append, .materialize])
        #expect(try await Self.program(in: subject) == Self.swappedProgram())
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
        #expect(try await Self.program(in: subject) == Fixtures.seedProgram())
        #expect(try await subject.stores.workouts.recent(limit: 5).isEmpty)
    }

    @Test("A save that fails changes no program; the retry, or the next launch, saves the workout and the change")
    func finish_saveFails_theProgramWaitsWithTheWorkout() async throws {
        let (subject, workout) = try await Self.swapped()
        await subject.probe.fail(.materialize, times: 2)
        _ = await failure { _ = try await subject.host.finish(endedAt: Self.end) }
        #expect(try await Self.program(in: subject) == Fixtures.seedProgram())
        _ = await failure { try await subject.relaunched().host.resumeFromStore() }
        #expect(try await Self.program(in: subject) == Fixtures.seedProgram())
        #expect(try await subject.stores.workouts.workout(id: workout.id) == nil)
        #expect(try await subject.relaunched().host.resumeFromStore() == nil)
        #expect(try await Self.program(in: subject) == Self.swappedProgram())
        #expect(try await subject.stores.workouts.workout(id: workout.id) != nil)
    }

    @Test("The change goes to the workout's own program, active or not, and to no other")
    func finish_anotherProgramActive_changesTheWorkoutsProgram() async throws {
        let (subject, _) = try await Self.swapped()
        let other = try Seeders.program(
            number: 7, weeks: 2, days: 1, slotsPerDay: 1, exercises: [Fixtures.CatalogID.benchPress]
        )
        try await subject.stores.programs.save(other)
        _ = try await subject.host.finish(endedAt: Self.end)
        #expect(try await subject.stores.programs.active() == other)
        // No miss is written for a program that is not active (S2, ruling O9); the swap still lands on it.
        var expected = try Self.swappedProgram(misses: [])
        expected.isActive = true
        #expect(try await Self.program(in: subject) == expected)
    }
}
