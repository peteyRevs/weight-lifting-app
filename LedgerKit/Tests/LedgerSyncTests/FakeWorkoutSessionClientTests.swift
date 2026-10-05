import Foundation
import LedgerDomain
@testable import LedgerFakes
import LedgerTestSupport
import Synchronization
import Testing

/// What `FakeWorkoutSessionClient` adds to the contract it keeps (`WorkoutSessionClientContractTests`): the
/// record of what it was asked, a workout to begin with, and the streams it forgets once they end.
@Suite("FakeWorkoutSessionClient", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeWorkoutSessionClientTests {
    static let session = EventBuilders.seedSession()
    static let later = EventBuilders.start.addingTimeInterval(600)

    /// The first row of the session, logged a minute in.
    static let logged = WorkoutEvent.setLogged(
        exerciseIndex: 0,
        setID: EventBuilders.setID(0, 0),
        weight: .pounds(185),
        reps: Reps(clamping: 5),
        doneAt: EventBuilders.start.addingTimeInterval(60)
    )

    @Test("applied lists every ask in call order: start, apply, finish and discard, refused or ignored too")
    func applied_recordsEveryAsk_inCallOrder() async throws {
        let fake = FakeWorkoutSessionClient()
        #expect(await fake.applied.isEmpty)
        // Refused: nothing is live yet.
        await #expect(throws: WorkoutSessionError.noLiveWorkout) { _ = try await fake.apply(.restSkipped) }
        try await fake.start(Self.session)
        // Refused: a workout is live.
        await #expect(throws: WorkoutSessionError.workoutInProgress(Self.session.id)) {
            try await fake.start(Self.session)
        }
        try await fake.apply(Self.logged)
        // Ignored by the engine: a second `started`.
        try await fake.apply(.started(Self.session))
        _ = try await fake.finish(endedAt: Self.later)
        try await fake.start(Self.session)
        try await fake.discard(endedAt: Self.later)
        #expect(await fake.applied == [
            .restSkipped,
            .started(Self.session),
            .started(Self.session),
            Self.logged,
            .started(Self.session),
            .finished(endedAt: Self.later),
            .started(Self.session),
            .discarded(endedAt: Self.later)
        ])
    }

    @Test("A fake built on a live workout holds it as if start had been called, with nothing applied yet")
    func initLive_holdsTheWorkout() async throws {
        let fake = FakeWorkoutSessionClient(live: Self.session)
        #expect(await fake.current() == Self.session)
        #expect(await fake.applied.isEmpty)
        var updates = await fake.updates().makeAsyncIterator()
        #expect(await updates.next() == WorkoutSessionUpdate(state: Self.session))
        await #expect(throws: WorkoutSessionError.workoutInProgress(Self.session.id)) {
            try await fake.start(Self.session)
        }
        let after = try await fake.apply(Self.logged)
        #expect(after.doneSets == 1)
        #expect(await updates.next() == WorkoutSessionUpdate(state: after, effects: [.haptic(.setLogged)]))
    }

    @Test("A fake built on a snapshot the engine would not start reports an issue and holds no workout")
    func initLive_unstartableSnapshot_reportsAnIssue() async {
        var finished = Self.session
        finished.phase = .finished
        finished.endedAt = Self.later
        let ended = finished
        await withKnownIssue {
            let fake = FakeWorkoutSessionClient(live: ended)
            #expect(await fake.current() == nil)
            #expect(await fake.applied.isEmpty)
        } matching: { issue in
            issue.description.contains("not a snapshot the engine starts (finished)")
        }
    }

    @Test("The device and the clock it stamps with change nothing a caller sees")
    func stamp_changesNothingObservable() async throws {
        let ticks = Ticks()
        let plain = FakeWorkoutSessionClient()
        let stamped = FakeWorkoutSessionClient(device: EventBuilders.watch, now: { ticks.next() })
        var seen: [[WorkoutSessionUpdate]] = []
        for fake in [plain, stamped] {
            var updates = await fake.updates().makeAsyncIterator()
            try await fake.start(Self.session)
            try await fake.apply(Self.logged)
            try await fake.apply(.restSkipped)
            _ = try await fake.finish(endedAt: Self.later)
            var heard: [WorkoutSessionUpdate] = []
            while heard.count < 5, let update = await updates.next() {
                heard.append(update)
            }
            seen.append(heard)
        }
        #expect(seen[0].count == 5)
        #expect(seen[0] == seen[1])
        // The clock was read once per call: the fake stamps with it, and never with the wall clock.
        #expect(ticks.count == 4)
    }

    @Test("A dropped stream is forgotten at the next subscription: a thousand come and go, one is held")
    func droppedStreams_areForgottenAtTheNextSubscription() async {
        let fake = FakeWorkoutSessionClient()
        // Today's screen coming and going a thousand times while no workout ever starts: nothing is published.
        for _ in 0 ..< 1000 {
            _ = await fake.updates()
        }
        // Each subscription forgot the stream dropped before it; only the last one's is still held.
        #expect(await fake.subscriberCount == 1)
        var kept = await fake.updates().makeAsyncIterator()
        #expect(await fake.subscriberCount == 1)
        #expect(await kept.next() == WorkoutSessionUpdate(state: nil))
    }

    @Test("A cancelled subscriber's stream is forgotten at the next publication, which the others still get")
    func cancelledStream_isForgottenAtTheNextPublication() async throws {
        let fake = FakeWorkoutSessionClient()
        var kept = await fake.updates().makeAsyncIterator()
        let stream = await fake.updates()
        let (listening, signal) = AsyncStream<Void>.makeStream()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in stream {
                    signal.yield()
                }
            }
            // Cancelled only once it is listening: it has read its first update.
            var reading = listening.makeAsyncIterator()
            _ = await reading.next()
            #expect(await fake.subscriberCount == 2)
            group.cancelAll()
        }
        // Its loop has ended. The fake learns of it without a task of its own, at its next call.
        #expect(await fake.subscriberCount == 2)
        try await fake.start(Self.session)
        #expect(await fake.subscriberCount == 1)
        #expect(await kept.next() == WorkoutSessionUpdate(state: nil))
        #expect(await kept.next() == WorkoutSessionUpdate(state: Self.session))
    }

    @Test("Streams that are read stay subscribed through any number of publications")
    func openStreams_staySubscribed() async throws {
        let fake = FakeWorkoutSessionClient(live: Self.session)
        var readers: [AsyncStream<WorkoutSessionUpdate>.AsyncIterator] = []
        for _ in 0 ..< 3 {
            await readers.append(fake.updates().makeAsyncIterator())
        }
        for pounds in 100 ..< 150 {
            try await fake.apply(.setTargetChanged(
                exerciseIndex: 0,
                setID: EventBuilders.setID(0, 0),
                weight: .pounds(Decimal(pounds)),
                reps: nil
            ))
        }
        #expect(await fake.subscriberCount == 3)
        for index in readers.indices {
            var heard = 0
            while heard < 51, await readers[index].next() != nil {
                heard += 1
            }
            #expect(heard == 51)
        }
    }
}

/// A clock that moves a second each time it is read, and counts the reads.
private final class Ticks: Sendable {
    private let reads = Mutex(0)

    var count: Int {
        reads.withLock { $0 }
    }

    func next() -> Date {
        reads.withLock { reads in
            reads += 1
            return EventBuilders.start.addingTimeInterval(Double(reads))
        }
    }
}
