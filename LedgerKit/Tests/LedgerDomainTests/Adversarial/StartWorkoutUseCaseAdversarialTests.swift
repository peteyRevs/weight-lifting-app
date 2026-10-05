import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 8: `StartWorkoutUseCase.start(_:replacingLive:)`, each outcome. The
/// expected workout is `SessionBuilder.build` called here on what the stores hold; the session client is the
/// fake behind a spy.
@Suite("Adversarial F10 S2 · StartWorkoutUseCase outcomes", .tags(.domain), .timeLimit(.minutes(1)))
struct StartWorkoutUseCaseAdversarialTests {
    static let kilograms = Settings(
        units: .kg, defaultRest: Settings.default.defaultRest, plateMathEnabled: true, autoRest: false,
        watchBuzz: true, weekStart: .monday, plateInventory: Settings.default.plateInventory
    )

    @Test(
        "With no live workout it starts what SessionBuilder builds from the stores",
        arguments: [[0, 0], [1, 0], [4, 2], [7, 1], [6, 3]], [Settings.default, kilograms]
    )
    func start_noLiveWorkout_startsWhatSessionBuilderBuilds(place: [Int], settings: Settings) async throws {
        let bench = try await StartBench.make(settings: settings)
        let source = try await bench.source(week: place[0], day: place[1])
        let expected = try await bench.built(source)
        let outcome = try await bench.useCase().start(source)
        #expect(outcome == .started(expected))
        #expect(try await bench.session.current() == expected)
        #expect(await bench.session.inner.applied == [.started(expected)])
        #expect(expected.source == source && expected.id == WorkoutID(StartBench.newID))
        #expect(expected.startedAt == StartBench.now && expected.originDevice == StartBench.device)
        #expect(expected.units == settings.units && expected.autoRest == settings.autoRest)
        #expect(expected.isDeload == (place[0] == 7))
    }

    @Test("The built workout carries the stored last performances")
    func start_withHistory_carriesLastPerformance() async throws {
        let bench = try await StartBench.make()
        guard case let .started(workout) = try await bench.useCase().start(bench.source(week: 1, day: 0)) else {
            Issue.record("not started")
            return
        }
        #expect(workout.exercises.allSatisfy { $0.lastPerformance != nil }, "the bench's history covers day 0")
        #expect(workout.exercises.first?.lastPerformance?.date == StartBench.now.addingTimeInterval(-7 * 86400))
    }

    /// A live workout of week `week`, day `day`, started an hour ago under another id, with a set logged.
    static func benchWithLive(week: Int, day: Int) async throws -> (bench: StartBench, live: WorkoutState) {
        let plain = try await StartBench.make()
        let started = try await plain.built(
            plain.source(week: week, day: day), id: EventBuilders.uuid(0x01D),
            now: StartBench.now.addingTimeInterval(-3600)
        )
        let bench = try await StartBench.make(live: started)
        let set = started.exercises[0].sets[0]
        let live = try await bench.session.inner.apply(.setLogged(
            exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: StartBench.now
        ))
        return (bench, live)
    }

    @Test("A live workout of the same week and day is resumed, whatever replacingLive says", arguments: [false, true])
    func start_sameSourceLive_resumes(replacingLive: Bool) async throws {
        let (bench, live) = try await Self.benchWithLive(week: 1, day: 0)
        let outcome = try await bench.useCase().start(bench.source(week: 1, day: 0), replacingLive: replacingLive)
        #expect(outcome == .resumed(live))
        #expect(try await bench.session.current() == live)
        #expect(await bench.session.asked.allSatisfy { $0 == .current }, "nothing built, stored or ended")
    }

    @Test(
        "A live workout of another day, or of the same day in another week, is a conflict and nothing changes",
        arguments: [[1, 1], [2, 0]]
    )
    func start_otherSourceLive_isAConflict(other: [Int]) async throws {
        let (bench, live) = try await Self.benchWithLive(week: other[0], day: other[1])
        let outcome = try await bench.useCase().start(bench.source(week: 1, day: 0))
        #expect(outcome == .conflict(live: live))
        #expect(try await bench.session.current() == live)
        #expect(await bench.session.asked.allSatisfy { $0 == .current })
    }

    @Test("A live workout that came from no program is a conflict too")
    func start_adHocWorkoutLive_isAConflict() async throws {
        let adHoc = EventBuilders.seedSession()
        let bench = try await StartBench.make(live: adHoc)
        #expect(try await bench.useCase().start(bench.source()) == .conflict(live: adHoc))
        #expect(try await bench.session.current() == adHoc)
    }

    @Test("replacingLive discards the other workout at the new one's start, then starts it")
    func start_replacingLive_discardsThenStarts() async throws {
        let (bench, live) = try await Self.benchWithLive(week: 1, day: 1)
        let source = try await bench.source(week: 1, day: 0)
        let expected = try await bench.built(source)
        #expect(try await bench.useCase().start(source, replacingLive: true) == .started(expected))
        #expect(try await bench.session.current() == expected)
        let asked = await bench.session.asked.filter { $0 != .current }
        #expect(asked == [.discard(StartBench.now), .start(expected.id)], "the old one ends when the new one starts")
        #expect(await bench.session.inner.applied.suffix(2) == [
            .discarded(endedAt: StartBench.now),
            .started(expected)
        ])
        #expect(live.id != expected.id)
    }

    @Test("replacingLive with nothing live just starts")
    func start_replacingLiveWithNothingLive_starts() async throws {
        let bench = try await StartBench.make()
        let source = try await bench.source()
        #expect(try await bench.useCase().start(source, replacingLive: true) == .started(bench.built(source)))
        #expect(await bench.session.asked.contains {
            if case .discard = $0 {
                true
            } else {
                false
            }
        } == false)
    }

    @Test("A slot removed from the day since it was shown: the workout is built from the stored day")
    func start_dayEditedSince_buildsFromTheStoredProgram() async throws {
        let bench = try await StartBench.make()
        var program = try await bench.program()
        let source = try await bench.source(week: 2, day: 0)
        program.days[0].slots.remove(at: 1)
        try await bench.stores.programs.save(program)
        let outcome = try await bench.useCase().start(source)
        #expect(try await outcome == .started(bench.built(source)))
        #expect(try await bench.session.current()?.exercises.map(\.slotID) == program.days[0].slots.map(\.id))
    }
}
