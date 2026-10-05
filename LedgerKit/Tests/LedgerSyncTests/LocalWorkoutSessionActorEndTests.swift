import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criteria 4 and 5: finish and discard on the host, step by step, and each step failing. A finish
/// stores `.finished`, saves the workout, drops the log and only then publishes; until the end is complete
/// every reader still sees the workout as it stood, and every later change completes the end first.
@Suite("LocalWorkoutSessionActor · the end of a workout", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorEndTests {
    typealias Update = WorkoutSessionUpdate

    /// A host with `Sample.session` live and one set logged, the calls so far forgotten.
    static func live() async throws -> (subject: Subject, state: WorkoutState) {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        let state = try await subject.host.apply(Sample.logged(0, 0))
        await subject.probe.clearCalls()
        return (subject, state)
    }

    /// What `event` makes of `state`, by the engine.
    static func ended(_ state: WorkoutState, by event: WorkoutEvent) throws -> WorkoutState {
        let envelope = EventBuilders.envelope(event, seq: 9, at: EventBuilders.start, workoutID: state.id)
        return try #require(WorkoutEngine.reduce(state, envelope).0)
    }

    @Test("Finish stores the end, saves the workout, drops the log, and then there is no workout")
    func finish_storesThenSavesThenDrops() async throws {
        let (subject, state) = try await Self.live()
        let finished = try await subject.host.finish(endedAt: Sample.at(600))
        #expect(try finished == (Self.ended(state, by: .finished(endedAt: Sample.at(600)))))
        #expect(await subject.writes() == [.append, .materialize, .compact])
        #expect(try await subject.stores.workouts.workout(id: state.id)?.doneSets == 1)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(try await subject.host.current() == nil)
        #expect(await !subject.host.needsRecovery)
    }

    @Test(
        "The ending update follows the save: while the store still works on it, readers see the workout live",
        arguments: [StoreProbe.Call.materialize, .compact]
    )
    func finish_publishesAfterTheSave(holding call: StoreProbe.Call) async throws {
        let (subject, state) = try await Self.live()
        var early = await Listener(subject.host)
        await subject.probe.hold(call)
        async let finishing = subject.host.finish(endedAt: Sample.at(600))
        await subject.probe.waitUntilHeld()
        #expect(try await subject.host.current() == state)
        var joining = await Listener(subject.host)
        await subject.probe.release()
        let ending = try await Update(state: finishing, haptics: [.workoutFinished])
        // The stream that joined during the save starts with the live workout and is told of its end.
        try await subject.host.start(Sample.other)
        #expect(await joining.updates(before: Sample.other) == [Update(state: state), ending])
        #expect(await early.updates(before: Sample.other) == [Update(state: state), ending])
    }

    @Test("When the ending update arrives the workout is in history, or its log is gone")
    func endingUpdate_arrivesAfterTheStoreIsDone() async throws {
        let (subject, state) = try await Self.live()
        var listener = await Listener(subject.host)
        _ = await listener.next()
        async let finishing = subject.host.finish(endedAt: Sample.at(600))
        #expect(await listener.next()?.state?.phase == .finished)
        #expect(try await subject.stores.workouts.workout(id: state.id) != nil)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        _ = try await finishing
        try await subject.host.start(Sample.other)
        async let discarding: Void = subject.host.discard(endedAt: Sample.at(900))
        _ = await listener.next()
        #expect(await listener.next()?.state?.phase == .discarded)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        try await discarding
    }

    @Test("A save that fails: finish throws, the log is kept, nothing is published, and a second finish retries it")
    func finish_saveFails_secondFinishRetries() async throws {
        let (subject, state) = try await Self.live()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.materialize)
        await #expect(throws: StoreProbe.Refusal(call: .materialize)) {
            _ = try await subject.host.finish(endedAt: Sample.at(600))
        }
        let finished = try Self.ended(state, by: .finished(endedAt: Sample.at(600)))
        #expect(await WorkoutEngine.replay(subject.log()) == finished)
        #expect(try await subject.stores.workouts.workout(id: state.id) == nil)
        #expect(try await subject.host.current() == state)
        #expect(await subject.host.needsRecovery)
        var joining = await Listener(subject.host)
        #expect(await joining.next() == Update(state: state))
        // The retry returns the workout as it ended at the first call, whatever date it is given.
        #expect(try await subject.host.finish(endedAt: Sample.at(999)) == finished)
        #expect(try await subject.stores.workouts.workout(id: state.id) != nil)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(try await subject.host.current() == nil)
        #expect(await !subject.host.needsRecovery)
        try await subject.host.start(Sample.other)
        let ending = Update(state: finished, haptics: [.workoutFinished])
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), ending])
    }

    @Test("A log that cannot be dropped after the save: the end waits all the same, and the retry saves again")
    func finish_compactFails_waitsAndRetries() async throws {
        let (subject, state) = try await Self.live()
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

/// While an end waits to be completed, and discard.
extension LocalWorkoutSessionActorEndTests {
    @Test("While an end waits, a change to the workout completes it first, and a start is refused")
    func pendingEnd_isCompletedBeforeAnyChange() async throws {
        let (subject, state) = try await Self.live()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.materialize, times: 2)
        _ = await failure { _ = try await subject.host.finish(endedAt: Sample.at(600)) }
        // The store still fails: the apply throws what the save throws, and nothing is published.
        await #expect(throws: StoreProbe.Refusal(call: .materialize)) {
            try await subject.host.apply(Sample.logged(0, 1))
        }
        await #expect(throws: WorkoutSessionError.workoutInProgress(state.id)) {
            try await subject.host.start(Sample.other)
        }
        #expect(try await subject.host.current() == state)
        // The store works again: the apply saves the workout, and then has no workout to change.
        await #expect(throws: WorkoutSessionError.noLiveWorkout) { try await subject.host.apply(Sample.logged(0, 1)) }
        #expect(try await subject.stores.workouts.workout(id: state.id)?.doneSets == 1)
        await #expect(throws: WorkoutSessionError.noLiveWorkout) {
            try await subject.host.discard(endedAt: Sample.at(700))
        }
        try await subject.host.start(Sample.other)
        let finished = try Self.ended(state, by: .finished(endedAt: Sample.at(600)))
        let ending = Update(state: finished, haptics: [.workoutFinished])
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), ending])
    }

    @Test("While an end waits, the launch step completes it and tells the streams, without a haptic")
    func pendingEnd_isCompletedByTheLaunchStep() async throws {
        let (subject, state) = try await Self.live()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.materialize, times: 2)
        _ = await failure { _ = try await subject.host.finish(endedAt: Sample.at(600)) }
        await #expect(throws: StoreProbe.Refusal(call: .materialize)) { try await subject.host.resumeFromStore() }
        #expect(try await subject.host.current() == state)
        #expect(await subject.host.needsRecovery)
        #expect(try await subject.host.resumeFromStore() == nil)
        #expect(await !subject.host.needsRecovery)
        #expect(try await subject.stores.workouts.workout(id: state.id) != nil)
        try await subject.host.start(Sample.other)
        let finished = try Self.ended(state, by: .finished(endedAt: Sample.at(600)))
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), Update(state: finished)])
    }

    @Test("An end the store refuses outright: nothing ends, nothing is published, and the next finish ends the workout")
    func finish_storeRefusesTheEnd_nothingEnds() async throws {
        let (subject, state) = try await Self.live()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.append)
        await #expect(throws: StoreProbe.Refusal(call: .append)) {
            _ = try await subject.host.finish(endedAt: Sample.at(600))
        }
        #expect(try await subject.host.current() == state)
        #expect(await subject.log().map(\.seq) == [1, 2])
        #expect(try await subject.stores.workouts.recent(limit: 5).isEmpty)
        // Nothing was stored, so the retry is a finish of its own: it ends the workout at its own date.
        let finished = try await subject.host.finish(endedAt: Sample.at(700))
        #expect(try finished == (Self.ended(state, by: .finished(endedAt: Sample.at(700)))))
        #expect(await subject.log().isEmpty)
        try await subject.host.start(Sample.other)
        let ending = Update(state: finished, haptics: [.workoutFinished])
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), ending])
    }

    @Test(
        "An end the store took and then threw on: the next call finds it stored, completes it and tells the streams"
    )
    func finish_lostAcknowledgement_isCompletedFromTheStore() async throws {
        let (subject, state) = try await Self.live()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.append, afterStoring: true)
        await #expect(throws: StoreProbe.Refusal(call: .append)) {
            _ = try await subject.host.finish(endedAt: Sample.at(600))
        }
        #expect(await subject.host.needsRecovery)
        let finished = try Self.ended(state, by: .finished(endedAt: Sample.at(600)))
        #expect(await WorkoutEngine.replay(subject.log()) == finished)
        // The workout ended in its log, so recovery saves it; the caller that asks next learns there is none.
        #expect(try await subject.host.current() == nil)
        #expect(try await subject.stores.workouts.workout(id: state.id)?.doneSets == 1)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(await !subject.host.needsRecovery)
        try await subject.host.start(Sample.other)
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), Update(state: finished)])
    }

    @Test("Discard stores the end and drops the log: nothing reaches history")
    func discard_dropsTheLog() async throws {
        let (subject, state) = try await Self.live()
        try await subject.host.discard(endedAt: Sample.at(600))
        #expect(await subject.writes() == [.append, .compact])
        #expect(try await subject.stores.workouts.recent(limit: 5).isEmpty)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(try await subject.host.current() == nil)
        #expect(state.doneSets == 1)
    }

    @Test("A log that cannot be dropped: discard throws, the workout still shows, and a second discard completes it")
    func discard_compactFails_secondDiscardCompletes() async throws {
        let (subject, state) = try await Self.live()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.compact)
        await #expect(throws: StoreProbe.Refusal(call: .compact)) {
            try await subject.host.discard(endedAt: Sample.at(600))
        }
        #expect(try await subject.host.current() == state)
        // A finish cannot save a workout that was discarded: it completes the discard and finds nothing live.
        await subject.probe.fail(.compact)
        await #expect(throws: StoreProbe.Refusal(call: .compact)) {
            _ = try await subject.host.finish(endedAt: Sample.at(700))
        }
        try await subject.host.discard(endedAt: Sample.at(800))
        #expect(try await subject.stores.workouts.recent(limit: 5).isEmpty)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        try await subject.host.start(Sample.other)
        let discarded = try Self.ended(state, by: .discarded(endedAt: Sample.at(600)))
        #expect(await listener.updates(before: Sample.other) == [Update(state: state), Update(state: discarded)])
    }

    @Test("A log with rows this version cannot read: finish throws incompleteLog and the workout stays live")
    func finish_incompleteLog_staysLive() async throws {
        let (subject, state) = try await Self.live()
        await subject.probe.pretendUnreadable(1)
        await #expect(throws: WorkoutSessionError.incompleteLog(state.id)) {
            _ = try await subject.host.finish(endedAt: Sample.at(600))
        }
        await #expect(throws: WorkoutSessionError.incompleteLog(state.id)) {
            try await subject.host.apply(.finished(endedAt: Sample.at(600)))
        }
        #expect(await subject.writes() == [])
        #expect(await !subject.host.needsRecovery)
        let next = try await subject.host.apply(Sample.logged(0, 1))
        #expect(next.doneSets == 2)
        // Discarding it ends the workout and keeps the log for a version that reads it.
        try await subject.host.discard(endedAt: Sample.at(700))
        #expect(try await subject.host.current() == nil)
        #expect(await subject.writes() == [.append, .append])
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [state.id])
    }
}
