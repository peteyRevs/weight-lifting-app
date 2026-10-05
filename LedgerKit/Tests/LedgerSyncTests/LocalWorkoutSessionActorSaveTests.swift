import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S3 criterion 5: the save and the end of the log are one store call over one database, so a finish can
/// no longer leave a workout in history and still live. The two-step path, where the log is dropped after the
/// save and that drop can fail by itself, is left for stores that are not one database, and is still handled.
@Suite("LocalWorkoutSessionActor · the save and the log", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorSaveTests {
    typealias Update = WorkoutSessionUpdate

    @Test("Over one database nothing can fail once the workout is saved: a broken compaction is never reached")
    func finish_oneDatabase_neverThrowsOnceSaved() async throws {
        let (subject, state) = try await LocalWorkoutSessionActorEndTests.live()
        var listener = await Listener(subject.host)
        // The call that S2 made after the save, and that could leave a workout in history and still live.
        await subject.probe.fail(.compact, times: 100)
        let finished = try await subject.host.finish(endedAt: Sample.at(600))
        #expect(await !subject.probe.calls.contains(.compact))
        #expect(try await subject.stores.workouts.recent(limit: 5).map(\.id) == [state.id])
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(try await subject.host.current() == nil)
        #expect(await !subject.host.needsRecovery)
        await #expect(throws: WorkoutSessionError.noLiveWorkout) {
            _ = try await subject.host.finish(endedAt: Sample.at(700))
        }
        await subject.probe.heal()
        try await subject.host.start(Sample.other)
        let ending = Update(state: finished, haptics: [.workoutFinished])
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), ending])
    }

    @Test("(a store that lies) A save that is stored and answered as failed: finish throws once, the retry ends it")
    func finish_saveAnswerLost_theRetryEndsIt() async throws {
        let (subject, state) = try await LocalWorkoutSessionActorEndTests.live()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.materialize, afterStoring: true)
        await #expect(throws: StoreProbe.Refusal(call: .materialize)) {
            _ = try await subject.host.finish(endedAt: Sample.at(600))
        }
        // The workout is saved and its log gone, and the host was told neither: it still shows the workout.
        #expect(try await subject.stores.workouts.workout(id: state.id) != nil)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(try await subject.host.current() == state)
        #expect(await subject.host.needsRecovery)
        let before = try await subject.stores.workouts.recent(limit: 5)
        let finished = try await subject.host.finish(endedAt: Sample.at(999))
        #expect(finished.endedAt == Sample.at(600))
        #expect(try await subject.stores.workouts.recent(limit: 5) == before)
        #expect(try await subject.host.current() == nil)
        #expect(await !subject.host.needsRecovery)
        try await subject.host.start(Sample.other)
        let ending = Update(state: finished, haptics: [.workoutFinished])
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), ending])
    }

    @Test("Over stores that are not one database, finish saves the workout and then drops the log, in two steps")
    func finish_separateStores_dropsTheLogAfterTheSave() async throws {
        let (subject, state) = try await LocalWorkoutSessionActorEndTests.live(oneDatabase: false)
        _ = try await subject.host.finish(endedAt: Sample.at(600))
        #expect(await subject.writes() == [.append, .materialize, .compact])
        #expect(try await subject.stores.workouts.workout(id: state.id)?.doneSets == 1)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(try await subject.host.current() == nil)
    }

    @Test("Not one database: a log that cannot be dropped after the save makes the end wait; the retry saves again")
    func finish_separateStores_compactFails_waitsAndRetries() async throws {
        let (subject, state) = try await LocalWorkoutSessionActorEndTests.live(oneDatabase: false)
        var listener = await Listener(subject.host)
        await subject.probe.fail(.compact)
        await #expect(throws: StoreProbe.Refusal(call: .compact)) {
            _ = try await subject.host.finish(endedAt: Sample.at(600))
        }
        #expect(try await subject.stores.workouts.workout(id: state.id) != nil)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [state.id])
        #expect(try await subject.host.current() == state)
        await subject.probe.clearCalls()
        let finished = try await subject.host.finish(endedAt: Sample.at(600))
        #expect(await subject.writes() == [.materialize, .compact])
        #expect(try await subject.stores.workouts.recent(limit: 5).map(\.id) == [state.id])
        try await subject.host.start(Sample.other)
        let ending = Update(state: finished, haptics: [.workoutFinished])
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), ending])
    }
}
