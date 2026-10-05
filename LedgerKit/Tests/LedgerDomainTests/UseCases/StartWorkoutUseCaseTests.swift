import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S2 criterion 8 (the brief's criteria 1 and 2): `StartWorkoutUseCase` over the seeded in-memory stores
/// and the engine-backed fake session. The seed is `LedgerFakes`' (the bundled catalog, the spec's program,
/// eight weeks of its history), not this target's rule fixtures.
@Suite("StartWorkoutUseCase", .tags(.domain), .timeLimit(.minutes(1)))
struct StartWorkoutUseCaseTests {
    typealias Seed = LedgerFakes.Fixtures
    typealias Outcome = StartWorkoutUseCase.Outcome

    static let newID = Seed.uuid(4242)
    /// Week 5 of the seed program: Upper A (day 0), Lower A (1), Upper B (2, with a drop set).
    static let week = 4

    struct Subject {
        let stores: InMemoryStores
        let session: FakeWorkoutSessionClient
        let useCase: StartWorkoutUseCase

        init(_ seed: InMemoryStores.Seed, live: WorkoutState? = nil) {
            stores = InMemoryStores(seed: seed)
            session = FakeWorkoutSessionClient(live: live)
            useCase = StartWorkoutUseCase(
                session: session,
                programs: stores.programs,
                exercises: stores.exercises,
                stats: stores.stats,
                settings: stores.settings,
                device: Seed.deviceID,
                now: { Seed.now },
                newID: { StartWorkoutUseCaseTests.newID }
            )
        }
    }

    static func source(day: Int, week: Int = week) throws -> WorkoutSource {
        try WorkoutSource(programID: Seed.programID, weekIndex: week, dayTemplateID: Seed.seedProgram().days[day].id)
    }

    @Test("With nothing live it builds the day's session from what is stored and starts it")
    func start_noLiveWorkout_buildsAndStarts() async throws {
        let subject = try Subject(.preview())
        let outcome = try await subject.useCase.start(Self.source(day: 0))
        let program = try Seed.seedProgram()
        var history: [ExerciseID: LastPerformance] = [:]
        for slot in program.days[0].slots {
            history[slot.exerciseID] = try await subject.stores.stats.lastPerformance(exerciseID: slot.exerciseID)
        }
        let catalog = try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
        let expected = try SessionBuilder.build(
            program: program, weekIndex: Self.week, day: program.days[0], exercises: catalog,
            history: history, settings: Seed.settingsLb, id: WorkoutID(Self.newID), device: Seed.deviceID,
            now: Seed.now
        )
        #expect(outcome == .started(expected))
        #expect(await subject.session.current() == expected)
        #expect(await subject.session.applied == [.started(expected)])
        #expect(expected.cursor == Cursor(exerciseIndex: 0, setIndex: 0) && expected.doneSets == 0)
        #expect(expected.elapsed(at: Seed.now) == .zero)
        #expect(try expected.source == (Self.source(day: 0)))
    }

    @Test("Each exercise carries its last performance from history; none without one")
    func start_fillsLastPerformance() async throws {
        let seeded = try Subject(.preview())
        guard case let .started(workout) = try await seeded.useCase.start(Self.source(day: 0)) else {
            Issue.record("not started")
            return
        }
        let bench = try #require(await seeded.stores.stats.lastPerformance(exerciseID: Seed.CatalogID.benchPress))
        #expect(workout.exercises[0].lastPerformance == bench)
        #expect(workout.exercises.allSatisfy { $0.lastPerformance != nil })
        let fresh = try Subject(.init(catalog: ExerciseCatalog.seed(), programs: [Seed.seedProgram()]))
        guard case let .started(first) = try await fresh.useCase.start(Self.source(day: 0)) else {
            Issue.record("not started")
            return
        }
        #expect(first.exercises.allSatisfy { $0.lastPerformance == nil })
    }

    @Test("A drop-set slot gets its row at −15 %, rounded to the step; units and auto rest are the settings'")
    func start_buildsDropRows_andSnapshotsSettings() async throws {
        var seed = try InMemoryStores.Seed.preview()
        seed.settings.units = .kg
        seed.settings.autoRest = false
        let subject = Subject(seed)
        guard case let .started(workout) = try await subject.useCase.start(Self.source(day: 2)) else {
            Issue.record("not started")
            return
        }
        let curl = try #require(workout.exercises.last)
        #expect(curl.sets.map(\.kind) == [.working, .working, .working, .drop])
        let dropped = curl.targetLoad.scaled(by: ProgressionRules.reductionFactor).rounded(toStep: curl.step)
        #expect(curl.sets.last?.weight == dropped && dropped < curl.targetLoad)
        #expect(workout.units == .kg && !workout.autoRest)
    }

    @Test("A live workout of the same week and day is resumed, whatever replacingLive says (rule 17)", arguments: [
        false, true
    ])
    func start_sameSource_resumes(replacingLive: Bool) async throws {
        let live = try Seed.seedSession()
        let subject = try Subject(.preview(), live: live)
        let logged = try await subject.session.apply(.exerciseSelected(exerciseIndex: 1, setIndex: 0))
        let outcome = try await subject.useCase.start(Self.source(day: 0), replacingLive: replacingLive)
        #expect(outcome == .resumed(logged))
        #expect(await subject.session.applied.count == 1)
        #expect(await subject.session.current() == logged)
    }

    @Test("A live workout of another day, or of the same day in another week, is a conflict: nothing changes")
    func start_differentSource_reportsConflict() async throws {
        let live = try Seed.seedSession()
        let subject = try Subject(.preview(), live: live)
        #expect(try await subject.useCase.start(Self.source(day: 1)) == .conflict(live: live))
        #expect(try await subject.useCase.start(Self.source(day: 0, week: 3)) == .conflict(live: live))
        #expect(await subject.session.applied.isEmpty)
        #expect(await subject.session.current() == live)
    }

    @Test("With replacingLive the live workout is discarded, when the new one starts, and the new one started")
    func start_replacingLive_discardsThenStarts() async throws {
        let subject = try Subject(.preview(), live: Seed.seedSession())
        let outcome = try await subject.useCase.start(Self.source(day: 1), replacingLive: true)
        guard case let .started(workout) = outcome else {
            Issue.record("\(outcome)")
            return
        }
        #expect(try workout.source == (Self.source(day: 1)) && workout.id == WorkoutID(Self.newID))
        #expect(await subject.session.applied == [.discarded(endedAt: Seed.now), .started(workout)])
        #expect(await subject.session.current() == workout)
    }
}

/// What starts nothing.
extension StartWorkoutUseCaseTests {
    @Test("A program that is not the active one throws programNotActive and starts nothing")
    func start_programNoLongerActive_throws() async throws {
        let subject = try Subject(.preview(), live: nil)
        let other = ProgramID(Seed.uuid(77))
        let source = try WorkoutSource(programID: other, weekIndex: 0, dayTemplateID: Seed.seedProgram().days[0].id)
        await #expect(throws: StartWorkoutError.programNotActive(other)) { _ = try await subject.useCase.start(source) }
        try await subject.stores.programs.delete(Seed.programID)
        await #expect(throws: StartWorkoutError.programNotActive(Seed.programID)) {
            _ = try await subject.useCase.start(Self.source(day: 0), replacingLive: true)
        }
        #expect(await subject.session.applied.isEmpty)
    }

    @Test("A day the program does not hold, or one with no exercise, throws and starts nothing")
    func start_unknownOrEmptyDay_throws() async throws {
        var seed = try InMemoryStores.Seed.preview()
        seed.programs[0].days[3].slots = []
        let emptied = seed.programs[0].days[3].id
        let subject = try Subject(seed, live: Seed.seedSession())
        let missing = DayTemplateID(Seed.uuid(78))
        let nowhere = WorkoutSource(programID: Seed.programID, weekIndex: Self.week, dayTemplateID: missing)
        await #expect(throws: StartWorkoutError.dayNotInProgram(missing)) {
            _ = try await subject.useCase.start(nowhere, replacingLive: true)
        }
        await #expect(throws: StartWorkoutError.emptyDay(emptied)) {
            _ = try await subject.useCase.start(Self.source(day: 3), replacingLive: true)
        }
        #expect(await subject.session.applied.isEmpty)
    }

    @Test("A session that cannot be built leaves the live workout alone, even with replacingLive")
    func start_buildFails_keepsTheLiveWorkout() async throws {
        let live = try Seed.seedSession()
        let subject = try Subject(.preview(), live: live)
        await #expect(throws: SessionBuilderError.weekOutOfRange(99)) {
            _ = try await subject.useCase.start(Self.source(day: 1, week: 99), replacingLive: true)
        }
        #expect(await subject.session.applied.isEmpty)
        #expect(await subject.session.current() == live)
    }

    @Test("A slot whose exercise is not stored throws the builder's unknownExercise and starts nothing")
    func start_exerciseNotStored_throws() async throws {
        let programs = try InMemoryProgramRepository(programs: [Seed.seedProgram()])
        let stores = InMemoryStores()
        let session = FakeWorkoutSessionClient()
        let useCase = StartWorkoutUseCase(
            session: session, programs: programs, exercises: stores.exercises, stats: stores.stats,
            settings: stores.settings, device: Seed.deviceID, now: { Seed.now }, newID: { Self.newID }
        )
        await #expect(throws: SessionBuilderError.self) { _ = try await useCase.start(Self.source(day: 0)) }
        #expect(await session.applied.isEmpty)
    }
}
