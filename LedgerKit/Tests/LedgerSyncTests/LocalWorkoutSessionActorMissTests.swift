import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criterion 4, the misses (rule 13, decision #5): a finished workout leaves each of its slots missed
/// or not for its week, on the program as it is stored when the workout is saved, and only when the active
/// program is the workout's.
@Suite("LocalWorkoutSessionActor · misses", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorMissTests {
    /// Week 5 (index 4) of the seed program, Upper A: five slots.
    static let week = 4

    /// A host over the bundled catalog and the active seed program, with its Upper A session live.
    static func live() async throws -> (subject: Subject, workout: WorkoutState) {
        let seed = try InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), programs: [Fixtures.seedProgram()])
        let subject = Subject(seed: seed)
        let workout = try Fixtures.seedSession()
        try await subject.host.start(workout)
        return (subject, workout)
    }

    /// Logs every set of exercise `index` as prescribed.
    static func logAll(of index: Int, in workout: WorkoutState, on host: LocalWorkoutSessionActor) async throws {
        for set in workout.exercises[index].sets {
            try await host.apply(.setLogged(
                exerciseIndex: index,
                setID: set.id,
                weight: set.weight,
                reps: set.reps,
                doneAt: Fixtures.now.addingTimeInterval(60)
            ))
        }
    }

    /// The stored misses of Upper A's slots, in slot order, once the seed program is active.
    static func misses(in subject: Subject) async throws -> [Set<Int>] {
        try await subject.stores.programs.setActive(Fixtures.programID)
        return try #require(await subject.stores.programs.active()).days[0].slots.map(\.misses)
    }

    @Test("Finish marks the week missed on each slot whose working sets were not all done, and on no other")
    func finish_writesTheMisses() async throws {
        let (subject, workout) = try await Self.live()
        try await Self.logAll(of: 0, in: workout, on: subject.host)
        try await subject.host.apply(.setLogged(
            exerciseIndex: 1,
            setID: workout.exercises[1].sets[0].id,
            weight: workout.exercises[1].sets[0].weight,
            reps: workout.exercises[1].sets[0].reps,
            doneAt: Fixtures.now.addingTimeInterval(90)
        ))
        _ = try await subject.host.finish(endedAt: Fixtures.now.addingTimeInterval(3600))
        #expect(try await Self.misses(in: subject) == [[], [Self.week], [Self.week], [Self.week], [Self.week]])
        #expect(try await subject.stores.workouts.workout(id: workout.id)?.doneSets == 6)
    }

    @Test("The misses go onto the program as stored at the save, not as it was when the workout started")
    func finish_usesTheProgramAsStoredNow() async throws {
        let (subject, workout) = try await Self.live()
        try await Self.logAll(of: 0, in: workout, on: subject.host)
        try await Self.logAll(of: 1, in: workout, on: subject.host)
        // Recorded while the workout ran: an earlier week's miss on the first slot, and this week's on the second.
        var program = try #require(await subject.stores.programs.active())
        program.days[0].slots[0].misses = [2]
        program.days[0].slots[1].misses = [Self.week]
        try await subject.stores.programs.save(program)
        _ = try await subject.host.finish(endedAt: Fixtures.now.addingTimeInterval(3600))
        let misses = try await Self.misses(in: subject)
        #expect(misses[0] == [2], "a miss recorded since the start was cleared")
        #expect(misses[1] == [], "a slot done in full keeps this week's miss")
        #expect(misses[2] == [Self.week])
    }

    @Test("When the active program is not the workout's, the workout is saved and no miss is written")
    func finish_anotherProgramActive_writesNoMisses() async throws {
        let (subject, workout) = try await Self.live()
        let other = try Seeders.program(
            number: 7, weeks: 2, days: 1, slotsPerDay: 1, exercises: [Fixtures.CatalogID.benchPress]
        )
        try await subject.stores.programs.save(other)
        #expect(try await subject.stores.programs.active()?.id == other.id)
        _ = try await subject.host.finish(endedAt: Fixtures.now.addingTimeInterval(3600))
        #expect(try await subject.stores.workouts.workout(id: workout.id) != nil)
        #expect(try await Self.misses(in: subject) == [[], [], [], [], []])
    }

    @Test("The rule is the program's id, not its slots: an active program with the same slots gets no miss either")
    func finish_judgesTheProgramByItsID() async throws {
        let seed = try InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), programs: [Fixtures.seedProgram()])
        let stores = InMemoryStores(seed: seed)
        let host = LocalWorkoutSessionActor(
            events: stores.events, workouts: stores.workouts, programs: AnotherProgramWithTheSameSlots(),
            device: Subject.device, now: { Fixtures.now }
        )
        let workout = try Fixtures.seedSession()
        try await host.start(workout)
        _ = try await host.finish(endedAt: Fixtures.now.addingTimeInterval(3600))
        #expect(try await stores.workouts.workout(id: workout.id) != nil)
        // The in-memory history writes a listed slot's misses onto whichever stored program holds the slot.
        let stored = try #require(await stores.programs.active())
        #expect(stored.days[0].slots.map(\.misses) == [[], [], [], [], []])
    }

    @Test("An ad-hoc workout asks for no program")
    func finish_adHoc_readsNoProgram() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        _ = try await subject.host.finish(endedAt: Sample.at(600))
        #expect(await !subject.probe.calls.contains(.activeProgram))
    }

    @Test("A finish the app was killed in is saved at the next launch with the misses of the program as stored then")
    func recovery_writesTheMisses() async throws {
        let (subject, workout) = try await Self.live()
        try await Self.logAll(of: 0, in: workout, on: subject.host)
        await subject.probe.fail(.materialize)
        _ = await failure { _ = try await subject.host.finish(endedAt: Fixtures.now.addingTimeInterval(3600)) }
        var program = try #require(await subject.stores.programs.active())
        program.days[0].slots[0].misses = [1]
        try await subject.stores.programs.save(program)
        #expect(try await subject.relaunched().host.resumeFromStore() == nil)
        #expect(try await Self.misses(in: subject) == [[1], [Self.week], [Self.week], [Self.week], [Self.week]])
        #expect(try await subject.stores.workouts.workout(id: workout.id)?.phase == .finished)
    }
}

/// A program store whose active program is not the workout's, yet holds the very same slots: what no real
/// store allows (a slot id belongs to one program), so only the host's own rule keeps the misses out.
struct AnotherProgramWithTheSameSlots: ProgramRepository {
    struct Unused: Error {}

    func active() async throws -> Program? {
        let seed = try Fixtures.seedProgram()
        return try Program(
            id: ProgramID(Fixtures.uuid(77)),
            name: seed.name,
            startDate: seed.startDate,
            weeks: seed.weeks,
            days: seed.days,
            isActive: true
        )
    }

    func save(_: Program) async throws {
        throw Unused()
    }

    func update(_: ProgramID, _: @Sendable (Program) throws -> Program) async throws -> Program {
        throw Unused()
    }

    func setActive(_: ProgramID) async throws {
        throw Unused()
    }

    func delete(_: ProgramID) async throws {
        throw Unused()
    }

    func observeActive() -> AsyncStream<Program?> {
        AsyncStream { $0.finish() }
    }
}
