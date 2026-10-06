import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 8: what `StartWorkoutUseCase` refuses ("It throws `programNotActive`,
/// `dayNotInProgram` or `emptyDay`, and starts nothing then"), and what a failure leaves behind when the
/// lifter asked to replace the live workout.
@Suite("Adversarial F10 S2 · StartWorkoutUseCase refusals", .tags(.domain), .timeLimit(.minutes(1)))
struct StartWorkoutRefusalAdversarialTests {
    typealias Outcomes = StartWorkoutUseCaseAdversarialTests

    /// A refusal, arranged on a bench whose live workout is another day's: what to ask, and the error.
    struct Refusal: Sendable, CustomStringConvertible {
        let description: String
        let arrange: @Sendable (StartBench) async throws -> (source: WorkoutSource, error: String)
    }

    static let unknownDay = DayTemplateID(EventBuilders.uuid(0xDEAD))

    static let refusals: [Refusal] = [
        Refusal(description: "another program is active") { bench in
            let source = try await bench.source()
            let other = try await Seeders.program(number: 5, exercises: bench.stores.exercises.all().map(\.id))
            try await bench.stores.programs.save(other)
            return (source, "\(StartWorkoutError.programNotActive(source.programID))")
        },
        Refusal(description: "the program was deleted") { bench in
            let source = try await bench.source()
            try await bench.stores.programs.delete(source.programID)
            return (source, "\(StartWorkoutError.programNotActive(source.programID))")
        },
        Refusal(description: "the day is not the program's") { bench in
            let program = try await bench.program()
            let source = WorkoutSource(programID: program.id, weekIndex: 1, dayTemplateID: unknownDay)
            return (source, "\(StartWorkoutError.dayNotInProgram(unknownDay))")
        },
        Refusal(description: "the day has no exercise") { bench in
            var program = try await bench.program()
            program.days[0].slots = []
            try await bench.stores.programs.save(program)
            return try await (bench.source(), "\(StartWorkoutError.emptyDay(program.days[0].id))")
        },
        Refusal(description: "the block has ended") { bench in
            try await (bench.source(week: 8), "\(SessionBuilderError.weekOutOfRange(8))")
        },
        Refusal(description: "the week is before the block") { bench in
            try await (bench.source(week: -1), "\(SessionBuilderError.weekOutOfRange(-1))")
        }
    ]

    @Test("A refused start starts nothing", arguments: refusals)
    func start_refused_startsNothing(refusal: Refusal) async throws {
        let bench = try await StartBench.make()
        let (source, error) = try await refusal.arrange(bench)
        #expect(await bench.outcome(source) == error)
        #expect(await bench.outcome(source, replacingLive: true) == error)
        #expect(try await bench.session.current() == nil)
        #expect(await bench.session.inner.applied.isEmpty)
    }

    @Test("A refused start leaves a live workout of another day live, replacingLive or not", arguments: refusals)
    func start_refusedWhileAnotherIsLive_keepsItLive(refusal: Refusal) async throws {
        let (bench, live) = try await Outcomes.benchWithLive(week: 1, day: 1)
        let (source, error) = try await refusal.arrange(bench)
        #expect(await bench.outcome(source, replacingLive: true) == error)
        #expect(try await bench.session.current() == live, "a build that fails leaves it live")
        #expect(await bench.session.asked.allSatisfy { $0 == .current })
    }

    @Test("A slot whose exercise is no longer stored: unknownExercise, and the live workout stays")
    func start_exerciseDeleted_throwsAndKeepsTheLiveWorkout() async throws {
        let (bench, live) = try await Outcomes.benchWithLive(week: 1, day: 1)
        let gone = try await bench.program().days[0].slots[2].exerciseID
        let useCase = bench.useCase(exercises: ExercisesWithout(base: bench.stores.exercises, gone: gone))
        let source = try await bench.source()
        let outcome = await bench.outcome(source, replacingLive: true, with: useCase)
        #expect(outcome == "\(SessionBuilderError.unknownExercise(gone))")
        #expect(try await bench.session.current() == live)
    }

    @Test("A store that cannot be read fails the start before the live workout is touched")
    func start_storeFailsDuringTheBuild_keepsTheLiveWorkout() async throws {
        let (bench, live) = try await Outcomes.benchWithLive(week: 1, day: 1)
        let useCase = bench.useCase(settings: UnreadableSettings())
        let outcome = try await bench.outcome(bench.source(), replacingLive: true, with: useCase)
        #expect(outcome == "\(UnreadableSettings.Unreadable())")
        #expect(try await bench.session.current() == live)
        #expect(await bench.session.asked.allSatisfy { $0 == .current })
    }

    /// The use case's documentation: "Only a throw from `start` itself can follow a discard." The lifter
    /// chose "Discard and start new", so the old workout is gone as asked; what the screen must handle is
    /// that no workout is live after the error.
    @Test("(documents) replacingLive whose start then fails leaves no workout: the old one is discarded")
    func start_replacingLiveThenStartFails_leavesNoWorkout() async throws {
        let (bench, _) = try await Outcomes.benchWithLive(week: 1, day: 1)
        let source = try await bench.source()
        await bench.session.failNextStart()
        #expect(await bench.outcome(source, replacingLive: true) == "\(SpySession.StartRefused())")
        #expect(try await bench.session.current() == nil)
        #expect(await bench.session.inner.applied.last == .discarded(endedAt: StartBench.now))
        #expect(try await bench.useCase().start(source) == .started(bench.built(source)), "asking again starts it")
    }

    @Test("Another caller starts a workout between the look and the start: workoutInProgress, then a conflict")
    func start_anotherStartGetsInBetween_reportsItNextTime() async throws {
        let bench = try await StartBench.make()
        let source = try await bench.source()
        let intruder = EventBuilders.seedSession()
        await bench.session.afterNextLook { try await $0.start(intruder) }
        #expect(await bench.outcome(source) == "\(WorkoutSessionError.workoutInProgress(intruder.id))")
        #expect(try await bench.session.current() == intruder)
        #expect(try await bench.useCase().start(source) == .conflict(live: intruder))
    }

    /// Criterion 8: "with `replacingLive: true` the live workout is discarded and the new one started." When the
    /// workout the lifter chose to replace has ended by the time of the discard (another caller finished it; on
    /// the host, a save that had failed went through), nothing stands in the new one's way (finding F10-S2-2).
    @Test("replacingLive when the live workout ended between the look and the discard still starts the new one")
    func start_replacingLive_liveEndedInBetween_startsTheNewOne() async throws {
        let (bench, live) = try await Outcomes.benchWithLive(week: 1, day: 1)
        let source = try await bench.source()
        await bench.session.afterNextLook { _ = try await $0.finish(endedAt: StartBench.now) }
        let outcome = await bench.outcome(source, replacingLive: true)
        #expect(outcome == "started \(StartBench.newID.uuidString.suffix(5))")
        #expect(try await bench.session.current()?.source == source)
        #expect(await bench.session.inner.applied.contains(.finished(endedAt: StartBench.now)), "\(live.id) was saved")
    }

    @Test("replacingLive when the live workout turns out to be this day's after all resumes it and discards nothing")
    func start_replacingLive_sameDayStartedInBetween_isNotDiscarded() async throws {
        let bench = try await StartBench.make()
        let source = try await bench.source()
        let mine = try await bench.built(source, id: EventBuilders.uuid(0x01D))
        try await bench.session.inner.start(mine)
        #expect(try await bench.useCase().start(source, replacingLive: true) == .resumed(mine))
        #expect(await bench.session.inner.applied == [.started(mine)])
    }
}
