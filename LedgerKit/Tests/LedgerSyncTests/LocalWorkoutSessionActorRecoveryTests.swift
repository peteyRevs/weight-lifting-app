import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criterion 6: `resumeFromStore()`, row by row of the criterion's table, on stores holding what an
/// app that died left behind.
@Suite("LocalWorkoutSessionActor · recovery", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorRecoveryTests {
    typealias Update = WorkoutSessionUpdate

    static let finished = Sample.log([Sample.logged(0, 0), .finished(endedAt: Sample.at(600))])
    static let discarded = Sample.log([Sample.logged(0, 0), .discarded(endedAt: Sample.at(600))])
    /// `Sample.other`, the superset pair, live: its first round logged, so its rest is running, and the last
    /// row of the second exercise selected.
    static let live = Sample.log(
        [logged(0, at: 60), logged(1, at: 70), .exerciseSelected(exerciseIndex: 1, setIndex: 2)],
        of: Sample.other
    )

    /// The first row of exercise `index` of `Sample.other`, logged as prescribed.
    static func logged(_ index: Int, at seconds: Double) -> WorkoutEvent {
        let set = Sample.other.exercises[index].sets[0]
        return .setLogged(
            exerciseIndex: index,
            setID: set.id,
            weight: set.weight,
            reps: set.reps,
            doneAt: Sample.at(seconds)
        )
    }

    static func subject(holding envelopes: [EventEnvelope], history: [WorkoutState] = []) -> Subject {
        Subject(seed: InMemoryStores.Seed(workouts: history, envelopes: envelopes))
    }

    @Test("Nothing stored: nothing is done, and there is no workout")
    func nothingStored_noWorkout() async throws {
        let subject = Subject()
        #expect(try await subject.host.resumeFromStore() == nil)
        #expect(try await subject.host.current() == nil)
        #expect(await subject.writes() == [])
        #expect(await !subject.host.needsRecovery)
    }

    @Test("A live log is resumed with the same sets, cursor and rest: no haptic, no effect run, the next seq")
    func liveLog_isResumed() async throws {
        let subject = Self.subject(holding: Self.live)
        let expected = try #require(WorkoutEngine.replay(Self.live))
        #expect(expected.rest == RestTimer(endsAt: Sample.at(70 + 90), total: .seconds(90)))
        #expect(expected.cursor == Cursor(exerciseIndex: 1, setIndex: 2) && expected.doneSets == 2)
        #expect(try await subject.host.resumeFromStore() == expected)
        #expect(try await subject.host.current() == expected)
        #expect(await subject.writes() == [])
        var listener = await Listener(subject.host)
        #expect(await listener.next() == Update(state: expected))
        try await subject.host.apply(.restSkipped)
        #expect(await subject.log(of: Sample.other.id).map(\.seq) == [1, 2, 3, 4, 5])
    }

    @Test("Finished, not saved: the workout is saved and its log dropped; nothing is live")
    func finishedLog_isSavedThenDropped() async throws {
        let subject = Self.subject(holding: Self.finished)
        #expect(try await subject.host.resumeFromStore() == nil)
        #expect(await subject.writes() == [.materialize, .compact])
        let stored = try #require(await subject.stores.workouts.workout(id: Sample.session.id))
        #expect(stored.phase == .finished && stored.endedAt == Sample.at(600) && stored.doneSets == 1)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
        #expect(try await subject.host.current() == nil)
    }

    @Test("Saved, not dropped: saving again changes nothing, and the log is dropped")
    func savedLog_isSavedAgainAndDropped() async throws {
        let workout = try #require(WorkoutEngine.replay(Self.finished))
        let subject = Self.subject(holding: Self.finished, history: [workout])
        let before = try await subject.stores.workouts.recent(limit: 5)
        #expect(before.map(\.id) == [workout.id])
        #expect(try await subject.host.resumeFromStore() == nil)
        #expect(try await subject.stores.workouts.recent(limit: 5) == before)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
    }

    @Test("Discarded, not dropped: the log is dropped and nothing reaches history")
    func discardedLog_isDropped() async throws {
        let subject = Self.subject(holding: Self.discarded)
        #expect(try await subject.host.resumeFromStore() == nil)
        #expect(await subject.writes() == [.compact])
        #expect(try await subject.stores.workouts.recent(limit: 5).isEmpty)
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [])
    }

    @Test("A log that replays to nothing is kept, and is no failure")
    func logWithoutAStart_isKept() async throws {
        let orphan = EventBuilders.envelope(.restSkipped, seq: 2, at: Sample.at(10))
        let subject = Self.subject(holding: [orphan])
        #expect(try await subject.host.resumeFromStore() == nil)
        #expect(await subject.writes() == [])
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [EventBuilders.workoutID])
        #expect(await !subject.host.needsRecovery)
    }

    @Test("Rows this version cannot read: a live log resumes from what it reads, an ended one is kept")
    func unreadableRows_resumeOrKeep() async throws {
        let subject = Self.subject(holding: Self.live + Self.finished + [
            EventBuilders.envelope(
                .started(Sample.session),
                seq: 1,
                at: Sample.at(0),
                workoutID: WorkoutID(EventBuilders.uuid(0xF102))
            ),
            EventBuilders.envelope(
                .discarded(endedAt: Sample.at(5)),
                seq: 2,
                at: Sample.at(5),
                workoutID: WorkoutID(EventBuilders.uuid(0xF102))
            )
        ])
        await subject.probe.pretendUnreadable(2)
        #expect(try await subject.host.resumeFromStore() == WorkoutEngine.replay(Self.live))
        #expect(await subject.writes() == [])
        #expect(try await subject.stores.workouts.recent(limit: 5).isEmpty)
        #expect(await subject.stores.events.uncompactedWorkoutIDs().count == 3)
        #expect(await !subject.host.needsRecovery)
    }
}

/// Several logs at once, a pass that fails, and a pass run again.
extension LocalWorkoutSessionActorRecoveryTests {
    @Test("A save that throws: its log is kept and the step fails, the other logs dealt with; the next pass saves it")
    func saveThatThrows_keepsItsLog_andCarriesOn() async throws {
        let dropped = WorkoutID(EventBuilders.uuid(0xF102))
        let discarding = EventBuilders.log(
            from: [
                .started(EventBuilders.session(EventBuilders.seedExercises, id: dropped)),
                .discarded(endedAt: Sample.at(5))
            ],
            workoutID: dropped
        )
        let subject = Self.subject(holding: Self.live + Self.finished + discarding)
        let resumed = try #require(WorkoutEngine.replay(Self.live))
        await subject.probe.fail(.materialize)
        await #expect(throws: StoreProbe.Refusal(call: .materialize)) { try await subject.host.resumeFromStore() }
        #expect(try await subject.host.current() == resumed)
        #expect(await Set(subject.stores.events.uncompactedWorkoutIDs()) == [Sample.session.id, Sample.other.id])
        #expect(try await subject.stores.workouts.recent(limit: 5).isEmpty)
        #expect(await subject.host.needsRecovery)
        #expect(try await subject.host.resumeFromStore() == resumed)
        #expect(try await subject.stores.workouts.recent(limit: 5).map(\.id) == [Sample.session.id])
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [Sample.other.id])
        #expect(await !subject.host.needsRecovery)
    }

    @Test("Running the step twice changes nothing: no write, no update")
    func twice_changesNothing() async throws {
        let subject = Self.subject(holding: Self.live + Self.finished)
        let resumed = try await subject.host.resumeFromStore()
        var listener = await Listener(subject.host)
        await subject.probe.clearCalls()
        #expect(try await subject.host.resumeFromStore() == resumed)
        #expect(try await subject.relaunched().host.resumeFromStore() == resumed)
        #expect(await subject.writes() == [])
        let mark = try await mark(subject.host)
        #expect(await listener.updates(before: mark) == [Update(state: resumed)])
    }

    @Test(
        "(documents) A workout the host shows whose log is gone from its store: the pass resumes nothing and it stays"
    )
    func logGone_theShownWorkoutStays() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        // Only damage does this. The pass logs a fault; what the host should do then is F17's to decide.
        await subject.stores.events.compact(workout: Sample.session.id)
        #expect(try await subject.host.resumeFromStore() == Sample.session)
        #expect(try await subject.host.current() == Sample.session)
        #expect(await !subject.host.needsRecovery)
    }

    @Test("Two live logs, which start refuses to make: the one that started last is resumed, the other kept")
    func twoLiveLogs_resumeTheLater() async throws {
        let later = EventBuilders.session(EventBuilders.seedExercises, startedAt: Sample.at(100))
        let subject = Self.subject(holding: Self.live + Sample.log([], of: later))
        #expect(try await subject.host.resumeFromStore() == later)
        #expect(await subject.stores.events.uncompactedWorkoutIDs().count == 2)
        #expect(await subject.writes() == [])
    }

    @Test(
        "A store that cannot be read: the step throws, knows nothing, and the next call recovers before it answers",
        arguments: [StoreProbe.Call.newestWallClock, .uncompactedWorkoutIDs, .envelopes, .highestSeq]
    )
    func storeUnreadable_theNextCallRetries(failing call: StoreProbe.Call) async throws {
        let subject = Self.subject(holding: Self.live)
        await subject.probe.fail(call, times: 2)
        await #expect(throws: StoreProbe.Refusal(call: call)) { try await subject.host.resumeFromStore() }
        #expect(await subject.host.needsRecovery)
        await #expect(throws: StoreProbe.Refusal(call: call)) { _ = try await subject.host.current() }
        #expect(try await subject.host.current() == WorkoutEngine.replay(Self.live))
        #expect(await !subject.host.needsRecovery)
    }

    @Test("A stream opened while the store cannot be read starts with no workout, and hears the one recovery resumes")
    func updates_whenRecoveryFails_hearTheResumedWorkout() async throws {
        let subject = Self.subject(holding: Self.live)
        await subject.probe.fail(.uncompactedWorkoutIDs)
        var listener = await Listener(subject.host)
        #expect(await listener.next() == Update(state: nil))
        let resumed = try await subject.host.resumeFromStore()
        #expect(resumed != nil)
        #expect(await listener.next() == Update(state: resumed))
    }

    @Test("After a relaunch a finished workout that still cannot be saved leaves nothing live: another can start")
    func unsavedWorkout_afterARelaunch_leavesNothingLive() async throws {
        let subject = Self.subject(holding: Self.finished)
        await subject.probe.fail(.materialize, times: 2)
        await #expect(throws: StoreProbe.Refusal(call: .materialize)) { try await subject.host.resumeFromStore() }
        #expect(try await subject.host.current() == nil)
        try await subject.host.start(Sample.other)
        // The next pass saves the first workout and says nothing: the live one is another.
        var listener = await Listener(subject.host)
        await subject.probe.heal()
        #expect(try await subject.host.resumeFromStore() == Sample.other)
        #expect(try await subject.stores.workouts.recent(limit: 5).map(\.id) == [Sample.session.id])
        let mark = try await mark(subject.host)
        #expect(await listener.updates(before: mark) == [Update(state: Sample.other)])
    }
}
