import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S5a, criterion 8's first half: after `.startRequestedByPhone` the watch adopts the phone's workout when its
/// `started` arrives within 5 s, and starts its own otherwise. Two live workouts are then both kept on both
/// devices (S3); which goes on is S5b's, pending Pete. Time is a `ManualClock`; the two-host tests run on
/// `LiveSyncPair`, driven from the test's task.
@Suite("LocalWorkoutSessionActor · a start the phone asks for", .tags(.sync), .timeLimit(.minutes(1)))
struct HostPhoneStartTests {
    /// How many times the watch started its own workout.
    actor Starts {
        private(set) var count = 0

        /// Whether the watch never started its own.
        var none: Bool {
            count < 1
        }

        func add() {
            count += 1
        }
    }

    /// The watch's own workout when the phone's does not come: the superset day, from the watch.
    static let watchSession = EventBuilders.session(
        EventBuilders.supersetExercises,
        id: Sample.other.id,
        device: EventBuilders.watch
    )

    @Test("A workout already live is adopted at once")
    func liveWorkout_isAdoptedAtOnce() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        #expect(await subject.host.adoptsPhoneStart(clock: ManualClock()))
    }

    @Test("With nothing live after 5 s, the watch does not adopt")
    func nothingWithinTheWait_isNotAdopted() async {
        let subject = Subject()
        let clock = ManualClock()
        let waiting = Task { await subject.host.adoptsPhoneStart(clock: clock) }
        #expect(await clock.nextSleep(skipping: .zero) == LocalWorkoutSessionActor.phoneStartWait)
        clock.advance(by: LocalWorkoutSessionActor.phoneStartWait)
        #expect(await waiting.value == false)
    }

    @Test("Criterion 8: the phone's started arriving within 5 s is adopted, and both carry one workout")
    func phoneStart_withinTheWait_isAdopted() async throws {
        let pair = await LiveSyncPair.make(seed: 81)
        defer { pair.close() }
        let (clock, starts) = (ManualClock(), Starts())
        let (requests, sink) = AsyncStream<HealthSessionEvent>.makeStream()
        let following = Task {
            await pair.watch.host.followPhoneStartRequests(requests, clock: clock) { await starts.add() }
        }
        try await pair.phone.host.start(Sample.session)
        await pair.phone.rest()
        sink.yield(.startRequestedByPhone)
        #expect(await clock.nextSleep(skipping: .zero) == LocalWorkoutSessionActor.phoneStartWait)
        await pair.settle()
        sink.finish()
        await following.value
        #expect(await starts.none)
        #expect(try await pair.watch.host.current()?.id == Sample.session.id)
        #expect(try await pair.converged())
    }

    @Test("Criterion 8: no started within 5 s starts the watch's own; both workouts are then kept on both devices")
    func noPhoneStart_startsOwn_andKeepsBoth() async throws {
        let pair = await LiveSyncPair.make(seed: 82)
        defer { pair.close() }
        let (clock, starts) = (ManualClock(), Starts())
        let (requests, sink) = AsyncStream<HealthSessionEvent>.makeStream()
        await pair.partition()
        try await pair.phone.host.start(Sample.session)
        await pair.phone.rest()
        let following = Task {
            await pair.watch.host.followPhoneStartRequests(requests, clock: clock) {
                await starts.add()
                try? await pair.watch.host.start(Self.watchSession)
            }
        }
        sink.yield(.startRequestedByPhone)
        #expect(await clock.nextSleep(skipping: .zero) == LocalWorkoutSessionActor.phoneStartWait)
        clock.advance(by: LocalWorkoutSessionActor.phoneStartWait)
        sink.finish()
        await following.value
        #expect(await starts.count == 1)
        await pair.watch.rest()
        await pair.heal()
        await pair.settle()
        #expect(try await pair.phone.host.current()?.id == Sample.session.id)
        #expect(try await pair.watch.host.current()?.id == Self.watchSession.id)
        for workout in [Sample.session.id, Self.watchSession.id] {
            let (onPhone, onWatch) = await (pair.phone.log(of: workout), pair.watch.log(of: workout))
            let keptOnBoth = !onPhone.isEmpty && onPhone == onWatch
            #expect(keptOnBoth, "\(workout.rawValue): both devices hold the whole log")
        }
    }

    @Test("Other events are ignored, and a wait cut short by cancellation starts nothing")
    func cancelledWait_startsNothing() async throws {
        let subject = Subject()
        let (clock, starts) = (ManualClock(), Starts())
        let (requests, sink) = AsyncStream<HealthSessionEvent>.makeStream()
        let following = Task {
            await subject.host.followPhoneStartRequests(requests, clock: clock) { await starts.add() }
        }
        sink.yield(.prepared)
        sink.yield(.startRequestedByPhone)
        #expect(await clock.nextSleep(skipping: .zero) == LocalWorkoutSessionActor.phoneStartWait)
        following.cancel()
        await following.value
        #expect(await starts.none)
        #expect(try await subject.host.current() == nil)
    }
}
