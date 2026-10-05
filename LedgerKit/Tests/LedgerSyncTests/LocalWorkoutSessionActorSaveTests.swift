import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S3 criterion 5: the save and the end of the log are one store call over one database, so a finish can
/// no longer leave a workout in history and still live. The two-step path, where the log is dropped after the
/// save and that drop can fail by itself, is left for stores that are not one database, and is still handled.
///
/// The host does not take the repository's word that the log went (finding F10-S3-1): after a save that
/// answered so it looks in its own event store, once, and compacts there when the log is still listed or the
/// look failed.
@Suite("LocalWorkoutSessionActor · the save and the log", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorSaveTests {
    typealias Update = WorkoutSessionUpdate

    /// The store calls that write, of `calls`.
    static func writes(_ calls: [StoreProbe.Call]) -> [StoreProbe.Call] {
        calls.filter { [.append, .materialize, .compact].contains($0) }
    }

    @Test("After a save that answered that the log went, the host looks in its event store once, and no more")
    func finish_oneDatabase_looksOnceAfterTheSave() async throws {
        let (subject, _) = try await LocalWorkoutSessionActorEndTests.live()
        _ = try await subject.host.finish(endedAt: Sample.at(600))
        let calls = await subject.probe.calls
        #expect(calls == [.unreadableCount, .append, .unreadableCount, .materialize, .uncompactedWorkoutIDs])
    }

    /// Review S3-SF4: before the host could skip the compaction, a held `.compact` always came. A wait for
    /// one that never comes must end, with a message, and not hang the run. No host is involved here: a held
    /// call that a host did make would wait for a release this test never gives.
    @Test("A wait for a held store call that never comes ends when its task is cancelled, and says which call")
    func probe_waitForACallThatNeverComes_endsOnCancellation() async throws {
        let probe = StoreProbe()
        await probe.hold(.compact)
        let waiting = Task { try await probe.waitUntilHeld() }
        waiting.cancel()
        let outcome = await waiting.result
        #expect(throws: StoreProbe.NeverHeld(call: .compact)) { try outcome.get() }
        #expect(StoreProbe.NeverHeld(call: .compact).description.contains("compact"))
    }

    @Test("A repository that answers for another store's log is not believed: the host drops the log in its own")
    func finish_repositoryAnswersForAnotherStore_theHostDropsItsOwnLog() async throws {
        let memory = InMemoryStores()
        // Not the event store `memory.workouts` is linked to, which is the one its answer is about.
        let events = InMemoryWorkoutEventStore()
        let probed = ProbedStores(events: events, workouts: memory.workouts, programs: memory.programs)
        let host = LocalWorkoutSessionActor(
            events: probed.events, workouts: probed.workouts, programs: probed.programs,
            device: Subject.device, now: { EventBuilders.start }
        )
        try await host.start(Sample.session)
        await probed.probe.clearCalls()
        _ = try await host.finish(endedAt: Sample.at(600))
        #expect(await Self.writes(probed.probe.calls) == [.append, .materialize, .compact])
        #expect(await events.uncompactedWorkoutIDs() == [])
        #expect(try await memory.workouts.recent(limit: 5).map(\.id) == [Sample.session.id])
        #expect(await !host.needsRecovery)
    }

    @Test("A look that fails is not thrown: the host compacts instead, which settles it, and finish returns")
    func finish_theLookFails_theHostCompacts() async throws {
        let (subject, state) = try await LocalWorkoutSessionActorEndTests.live()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.uncompactedWorkoutIDs)
        let finished = try await subject.host.finish(endedAt: Sample.at(600))
        #expect(await subject.writes() == [.append, .materialize, .compact])
        #expect(try await subject.stores.workouts.recent(limit: 5).map(\.id) == [state.id])
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(await !subject.host.needsRecovery)
        try await subject.host.start(Sample.other)
        let heard = await listener.updates(before: Sample.other)
        #expect(heard.map(\.state?.phase) == [.live, .finished] && heard.last?.state?.id == finished.id)
    }

    @Test("When the look and the compaction both fail the end waits, though the workout is saved; the retry ends it")
    func finish_theLookAndTheCompactionFail_theEndWaits() async throws {
        let (subject, state) = try await LocalWorkoutSessionActorEndTests.live()
        await subject.probe.fail(.uncompactedWorkoutIDs)
        await subject.probe.fail(.compact)
        await #expect(throws: StoreProbe.Refusal(call: .compact)) {
            _ = try await subject.host.finish(endedAt: Sample.at(600))
        }
        #expect(try await subject.stores.workouts.recent(limit: 5).map(\.id) == [state.id])
        #expect(try await subject.host.current()?.phase == .live)
        #expect(await subject.host.needsRecovery)
        await subject.probe.clearCalls()
        let finished = try await subject.host.finish(endedAt: Sample.at(999))
        #expect(finished.endedAt == Sample.at(600))
        #expect(await subject.writes() == [.materialize])
        #expect(try await subject.stores.workouts.recent(limit: 5).map(\.id) == [state.id])
        #expect(try await subject.host.current()?.id == nil)
        #expect(await !subject.host.needsRecovery)
    }

    @Test("Over one database a compaction that would fail is never reached once the workout is saved")
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
