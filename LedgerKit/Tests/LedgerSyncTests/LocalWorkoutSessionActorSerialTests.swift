import Foundation
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import Testing

/// The host's operations run one at a time, in a task the host owns. These hold one operation inside the
/// store (`StoreProbe.hold`) and make the next call, or cancel the caller, while it waits there: the
/// interleavings an actor that awaits its store would otherwise allow.
@Suite("LocalWorkoutSessionActor · one operation at a time", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorSerialTests {
    typealias Update = WorkoutSessionUpdate

    @Test("Calls made while another is inside the store start from what that one stored, and make one history")
    func laterCallers_startFromWhatTheFirstStored() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        var listener = await Listener(subject.host)
        await subject.probe.hold(.append)
        async let first = subject.host.apply(Sample.logged(0, 0))
        await subject.probe.waitUntilHeld()
        // Which of these two reaches the host first is the scheduler's choice; both come after the held one.
        async let second = subject.host.apply(Sample.retargeted(0, 1, pounds: 190))
        async let third = subject.host.apply(Sample.retargeted(0, 2, pounds: 195))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        #expect(try await subject.host.current() == Sample.session)
        await subject.probe.release()
        let (logged, one, other) = try await (first, second, third)
        #expect(logged.doneSets == 1 && one.doneSets == 1 && other.doneSets == 1)
        let last = try #require(try await subject.host.current())
        #expect(last.exercises[0].sets.map(\.weight) == [185, 190, 195, 185, 185].map { Weight.pounds($0) })
        #expect([one, other].contains(last))
        let mark = try await mark(subject.host)
        let heard = await listener.updates(before: mark)
        let between = one == last ? other : one
        #expect(heard == [
            Update(state: Sample.session),
            Update(state: logged, haptics: [.setLogged]),
            Update(state: between),
            Update(state: last)
        ])
        #expect(await subject.log().map(\.seq) == [1, 2, 3, 4, 5])
    }

    @Test(
        "A caller cancelled while its event is on the way to the store: the event is stored and published all the same"
    )
    func cancelledCaller_stillStores() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        var listener = await Listener(subject.host)
        await subject.probe.hold(.append)
        let caller = Task { try await subject.host.apply(Sample.logged(0, 0)) }
        await subject.probe.waitUntilHeld()
        caller.cancel()
        await subject.probe.release()
        let applied = try await caller.value
        #expect(applied.doneSets == 1)
        #expect(await subject.log().map(\.seq) == [1, 2])
        #expect(try await subject.host.current() == applied)
        _ = await listener.next()
        #expect(await listener.next() == Update(state: applied, haptics: [.setLogged]))
    }

    @Test(
        "A caller already cancelled when it calls: its event still reaches the database, which refuses cancelled writes"
    )
    func cancelledCaller_isStoredInTheDatabase() async throws {
        let stores = try LedgerStores(LedgerDatabase.inMemory(), deviceID: Subject.device, now: { EventBuilders.start })
        let host = LocalWorkoutSessionActor(
            events: stores.events, workouts: stores.workouts, programs: stores.programs,
            device: Subject.device, now: { EventBuilders.start }
        )
        try await host.start(Sample.session)
        let (gate, open) = AsyncStream<Void>.makeStream()
        let caller = Task {
            for await _ in gate {
                break
            }
            // GRDB's async writes throw `CancellationError` in a cancelled task: the write must not be this one's.
            return try await (Task.isCancelled, host.apply(Sample.logged(0, 0)))
        }
        caller.cancel()
        open.yield()
        let (wasCancelled, applied) = try await caller.value
        #expect(wasCancelled && applied.doneSets == 1)
        #expect(try await stores.events.envelopes(for: Sample.session.id).count == 2)
        #expect(try await host.finish(endedAt: Sample.at(600)).doneSets == 1)
    }

    @Test("A caller cancelled before its turn comes: its event is still applied, in its place in the queue")
    func cancelledCaller_keepsItsTurn() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        await subject.probe.hold(.append)
        async let first = subject.host.apply(Sample.logged(0, 0))
        await subject.probe.waitUntilHeld()
        let caller = Task { try await subject.host.apply(Sample.retargeted(0, 1, pounds: 190)) }
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        caller.cancel()
        await subject.probe.release()
        _ = try await first
        #expect(try await caller.value.exercises[0].sets[1].weight == .pounds(190))
        #expect(await subject.log().map(\.seq) == [1, 2, 3])
    }

    @Test("A call made during recovery waits for it: it meets the workout recovery resumes")
    func callsDuringRecovery_waitForIt() async throws {
        let subject = LocalWorkoutSessionActorRecoveryTests.subject(holding: LocalWorkoutSessionActorRecoveryTests.live)
        let resumed = try #require(WorkoutEngine.replay(LocalWorkoutSessionActorRecoveryTests.live))
        await subject.probe.hold(.uncompactedWorkoutIDs)
        async let launch = subject.host.resumeFromStore()
        await subject.probe.waitUntilHeld()
        async let current = subject.host.current()
        async let stream = subject.host.updates()
        // A start that did not wait would find nothing live and leave a second live log behind.
        async let start = failure { try await subject.host.start(Sample.session) }
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        await subject.probe.release()
        #expect(try await launch == resumed)
        #expect(try await current == resumed)
        var iterator = await stream.makeAsyncIterator()
        #expect(await iterator.next() == Update(state: resumed))
        #expect(await start as? WorkoutSessionError == .workoutInProgress(resumed.id))
        #expect(await subject.stores.events.uncompactedWorkoutIDs() == [resumed.id])
    }

    @Test("With no launch step, the first protocol call recovers, whichever call it is", arguments: 0 ..< 4)
    func firstProtocolCall_startsRecovery(call: Int) async throws {
        let subject = LocalWorkoutSessionActorRecoveryTests.subject(holding: LocalWorkoutSessionActorRecoveryTests.live)
        let resumed = try #require(WorkoutEngine.replay(LocalWorkoutSessionActorRecoveryTests.live))
        switch call {
        case 0:
            #expect(try await subject.host.current() == resumed)
        case 1:
            var listener = await Listener(subject.host)
            #expect(await listener.next() == Update(state: resumed))
        case 2:
            await #expect(throws: WorkoutSessionError.workoutInProgress(resumed.id)) {
                try await subject.host.start(Sample.session)
            }
        default:
            #expect(try await subject.host.finish(endedAt: Sample.at(600)).doneSets == 2)
            #expect(try await subject.stores.workouts.workout(id: resumed.id) != nil)
        }
        #expect(await !subject.host.needsRecovery)
        // The launch step, running afterwards, finds nothing to do.
        await subject.probe.clearCalls()
        try await subject.host.resumeFromStore()
        #expect(await subject.writes() == [])
    }
}
