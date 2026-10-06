import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 8 on the real host: `StartWorkoutUseCase` over
/// `LocalWorkoutSessionActor` and the in-memory stores, where the session can be in a state the fake never
/// is: an end that is stored and waits.
@Suite("Adversarial F10 S2 · StartWorkoutUseCase over the host", .tags(.sync), .timeLimit(.minutes(1)))
struct HostStartUseCaseAdversarialTests {
    static let newID = EventBuilders.uuid(0x57A27)

    struct NoStores: Error {}

    /// The misses scene (Upper A of week 4 live), a use case over its host and stores, and another day to start.
    struct Bench {
        let scene: SiegeScene
        let useCase: StartWorkoutUseCase
        let other: WorkoutSource
    }

    static func bench() async throws -> Bench {
        let scene = try await HostMissesAdversarialTests.scene(.memory)
        guard let stores = scene.rig.memory else {
            throw NoStores()
        }
        let useCase = StartWorkoutUseCase(
            session: scene.host, programs: stores.programs, exercises: stores.exercises, stats: stores.stats,
            settings: stores.settings, device: scene.rig.device, now: { scene.rig.clock.now }, newID: { newID }
        )
        let lower = try Fixtures.lowerA().id
        let other = WorkoutSource(programID: Fixtures.programID, weekIndex: 4, dayTemplateID: lower)
        return Bench(scene: scene, useCase: useCase, other: other)
    }

    static func outcome(_ useCase: StartWorkoutUseCase, _ source: WorkoutSource, replacingLive: Bool) async -> String {
        do {
            switch try await useCase.start(source, replacingLive: replacingLive) {
            case let .started(workout): return "started \(workout.name)"
            case let .resumed(workout): return "resumed \(workout.name)"
            case let .conflict(workout): return "conflict with \(workout.name)"
            }
        } catch let error as SiegeError {
            return "\(error.call.rawValue) \(error.fault.rawValue)"
        } catch {
            return "\(error)"
        }
    }

    @Test("A workout the use case started is the one a relaunch resumes")
    func start_overTheHost_survivesARelaunch() async throws {
        let bench = try await Self.bench()
        let (scene, useCase, other) = (bench.scene, bench.useCase, bench.other)
        try await scene.host.discard(endedAt: SiegeScene.end)
        #expect(await Self.outcome(useCase, other, replacingLive: false) == "started Lower A — Squat focus")
        let started = try #require(try await scene.host.current())
        #expect(started.source == other && started.id == WorkoutID(Self.newID))
        let relaunched = await scene.rig.host()
        #expect(try await relaunched.resumeFromStore() == started)
    }

    @Test("replacingLive over the host discards the live workout's log and starts the new one")
    func start_replacingLive_overTheHost_discardsAndStarts() async throws {
        let bench = try await Self.bench()
        let (scene, useCase, other) = (bench.scene, bench.useCase, bench.other)
        #expect(await Self.outcome(useCase, other, replacingLive: false) == "conflict with Upper A — Push focus")
        #expect(await Self.outcome(useCase, other, replacingLive: true) == "started Lower A — Squat focus")
        #expect(try await scene.rig.history().isEmpty)
        #expect(try await scene.rig.uncompacted() == [WorkoutID(Self.newID)])
        #expect(await scene.heard().map(\.state?.phase) == [
            .live,
            .live,
            .live,
            .live,
            .live,
            .live,
            .live,
            .live,
            .live,
            .discarded,
            .live
        ])
    }

    /// Criterion 8: "with `replacingLive: true` the live workout is discarded and the new one started." Here the
    /// live workout's "Save workout" failed: its end is stored, every reader still sees it (the protocol), so
    /// the use case reports a conflict, and "Discard and start new" must leave the lifter with the new workout.
    @Test("replacingLive over a workout whose save failed still starts the new workout")
    func start_replacingLive_overAWaitingSave_startsTheNewWorkout() async throws {
        let bench = try await Self.bench()
        let (scene, useCase, other) = (bench.scene, bench.useCase, bench.other)
        await scene.siege.fail(.materialize)
        #expect(await SiegeScene.outcome(.finish(SiegeScene.end), on: scene.host) == "materialize refuse")
        #expect(await Self.outcome(useCase, other, replacingLive: false) == "conflict with Upper A — Push focus")
        let replaced = await Self.outcome(useCase, other, replacingLive: true)
        #expect(replaced == "started Lower A — Squat focus")
        let current = try await scene.host.current()
        #expect(current?.source == other)
        #expect(try await scene.rig.history().map(\.id) == [scene.live.id], "the end was stored: the workout is saved")
    }

    @Test("replacingLive whose discard cannot drop the log: asking again completes it and starts")
    func start_replacingLive_discardFails_secondAttemptStarts() async throws {
        let bench = try await Self.bench()
        let (scene, useCase, other) = (bench.scene, bench.useCase, bench.other)
        await scene.siege.fail(.compact)
        #expect(await Self.outcome(useCase, other, replacingLive: true) == "compact refuse")
        #expect(try await scene.host.current()?.id == scene.live.id, "nothing started over a log that is not dropped")
        #expect(await Self.outcome(useCase, other, replacingLive: true) == "started Lower A — Squat focus")
        #expect(try await scene.rig.history().isEmpty)
        #expect(try await scene.rig.uncompacted() == [WorkoutID(Self.newID)])
    }

    @Test("(documents) replacingLive whose start is refused by the store leaves no workout, live or stored")
    func start_replacingLive_startRefused_leavesNoWorkout() async throws {
        let bench = try await Self.bench()
        let (scene, useCase, other) = (bench.scene, bench.useCase, bench.other)
        await scene.siege.fail(.append, skipping: 1)
        let outcome = await Self.outcome(useCase, other, replacingLive: true)
        #expect(outcome == "append refuse", "the discard's append passes; the start's fails")
        #expect(try await scene.host.current() == nil)
        #expect(try await scene.rig.uncompacted().isEmpty)
        #expect(await Self.outcome(useCase, other, replacingLive: true) == "started Lower A — Squat focus")
    }
}
