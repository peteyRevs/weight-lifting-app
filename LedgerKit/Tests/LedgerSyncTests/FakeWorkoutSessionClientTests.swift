import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// What `FakeWorkoutSessionClient` adds to the contract it keeps (`WorkoutSessionClientContractTests`): the
/// record of what it was asked and a workout to begin with; and that streams which ended disturb nobody.
@Suite("FakeWorkoutSessionClient", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeWorkoutSessionClientTests {
    typealias Update = WorkoutSessionUpdate

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

    /// A stepper edit of the first row: its weight becomes `pounds`.
    static func edit(_ pounds: Int) -> WorkoutEvent {
        .setTargetChanged(
            exerciseIndex: 0,
            setID: EventBuilders.setID(0, 0),
            weight: .pounds(Decimal(pounds)),
            reps: nil
        )
    }

    @Test("applied lists every ask in call order: start, apply, finish and discard, refused or ignored too")
    func applied_recordsEveryAsk_inCallOrder() async throws {
        let fake = FakeWorkoutSessionClient()
        let never = Date(timeIntervalSinceReferenceDate: .infinity)
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
        // Refused: an end the engine ignores.
        await #expect(throws: WorkoutSessionError.invalidEndDate) { try await fake.discard(endedAt: never) }
        _ = try await fake.finish(endedAt: Self.later)
        try await fake.start(Self.session)
        try await fake.discard(endedAt: Self.later)
        #expect(await fake.applied == [
            .restSkipped,
            .started(Self.session),
            .started(Self.session),
            Self.logged,
            .started(Self.session),
            .discarded(endedAt: never),
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
        #expect(await updates.next() == Update(state: Self.session))
        await #expect(throws: WorkoutSessionError.workoutInProgress(Self.session.id)) {
            try await fake.start(Self.session)
        }
        let after = try await fake.apply(Self.logged)
        #expect(after.doneSets == 1)
        #expect(await updates.next() == Update(state: after, haptics: [.setLogged]))
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

    @Test(
        "finish and discard at a date that is not finite throw invalidEndDate; the workout is still live and can end",
        arguments: [Double.infinity, -.infinity, .nan]
    )
    func end_atADateThatIsNotFinite_throwsInvalidEndDate(_ seconds: Double) async throws {
        let never = Date(timeIntervalSinceReferenceDate: seconds)
        let fake = FakeWorkoutSessionClient(live: Self.session)
        var updates = await fake.updates().makeAsyncIterator()
        await #expect(throws: WorkoutSessionError.invalidEndDate) { _ = try await fake.finish(endedAt: never) }
        await #expect(throws: WorkoutSessionError.invalidEndDate) { try await fake.discard(endedAt: never) }
        #expect(await fake.current() == Self.session)
        // Through `apply` the same event is an ignored one: the workout comes back as it stands.
        #expect(try await fake.apply(.finished(endedAt: never)) == Self.session)
        let finished = try await fake.finish(endedAt: Self.later)
        #expect(finished.phase == .finished && finished.endedAt == Self.later)
        // Nothing was published for the refused and ignored ends: the stream goes from the workout to its end.
        #expect(await updates.next() == Update(state: Self.session))
        #expect(await updates.next() == Update(state: finished, haptics: [.workoutFinished]))
    }

    /// The fake forgets a stream when a publication finds it ended, so thousands that ended while nothing
    /// was published are all still held at the next one. What a caller can see of that is only this: nobody
    /// else is disturbed.
    @Test("Thousands of dropped streams and hundreds of cancelled readers disturb no later subscriber or publication")
    func endedStreams_disturbNoLaterSubscriberOrPublication() async throws {
        let fake = FakeWorkoutSessionClient()
        // Today's screen coming and going while no workout ever starts: nothing is published in between.
        for _ in 0 ..< 5000 {
            _ = await fake.updates()
        }
        var kept = await fake.updates().makeAsyncIterator()
        try await fake.start(Self.session)
        #expect(await kept.next() == Update(state: nil))
        #expect(await kept.next() == Update(state: Self.session))
        // Readers that come and go during the workout, one per edit, each cancelled before the next edit.
        var expected: [Update] = []
        for round in 0 ..< 200 {
            let stream = await fake.updates()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in stream {}
                }
                group.cancelAll()
            }
            try await expected.append(Update(state: fake.apply(Self.edit(100 + round))))
        }
        var heard: [Update] = []
        while heard.count < expected.count, let update = await kept.next() {
            heard.append(update)
        }
        #expect(heard == expected)
        var late = await fake.updates().makeAsyncIterator()
        #expect(await late.next() == expected.last)
    }
}
