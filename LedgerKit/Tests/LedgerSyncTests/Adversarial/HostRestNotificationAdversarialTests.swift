import Foundation
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
import Synchronization
import Testing

/// G2, F10 S6 criterion 8: the host and the rest-over notification, with no screen anywhere. One rule, from
/// the criterion: whatever was asked of the host, the notification that is scheduled is the one for the
/// rest the live workout holds, and none when it holds no rest or has ended.
@Suite(
    "LocalWorkoutSessionActor · the rest notification (adversarial)",
    .tags(.sync, .property),
    .timeLimit(.minutes(2))
)
struct HostRestNotificationAdversarialTests {
    /// A host over in-memory stores with a recording client, and the host a relaunch builds over the same
    /// stores with a client of its own (the system's scheduled notification is not in the process).
    struct Rig {
        let memory = InMemoryStores(seed: .empty)
        let notifications = FakeNotifications()
        let host: LocalWorkoutSessionActor

        init() {
            host = Self.host(memory, notifications)
        }

        static func host(_ memory: InMemoryStores, _ client: (any NotificationsClient)?) -> LocalWorkoutSessionActor {
            LocalWorkoutSessionActor(
                events: memory.events,
                workouts: memory.workouts,
                programs: memory.programs,
                device: EventBuilders.phone,
                notifications: client,
                now: { EventBuilders.start }
            )
        }
    }

    static let seeds: [UInt64] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init)
        return (0 ..< max(1, configured ?? 40)).map { UInt64($0) &* 7919 &+ 17 }
    }()

    /// A seeded event on `session`'s rows at `clock` seconds: logs, un-logs, steppers, "+30s" both ways,
    /// skips, and events the engine ignores.
    static func event(_ generator: inout SplitMix64, in session: WorkoutState, at clock: Double) -> WorkoutEvent {
        let exercise = Int.random(in: 0 ..< session.exercises.count, using: &generator)
        let row = session.exercises[exercise].sets.randomElement(using: &generator) ?? session.exercises[0].sets[0]
        switch Int.random(in: 0 ..< 12, using: &generator) {
        case 0 ..< 5:
            return .setLogged(
                exerciseIndex: exercise, setID: row.id, weight: row.weight, reps: row.reps, doneAt: Sample.at(clock)
            )
        case 5, 6:
            return .setUnlogged(exerciseIndex: exercise, setID: row.id)
        case 7:
            return .setTargetChanged(exerciseIndex: exercise, setID: row.id, weight: .pounds(100), reps: nil)
        case 8, 9:
            return .restExtended(
                amount: .seconds(30), extendsShownRest: Bool.random(using: &generator), tappedAt: Sample.at(clock)
            )
        case 10:
            return .restSkipped
        default:
            return .exerciseSelected(exerciseIndex: 99, setIndex: 0)
        }
    }

    @Test(
        "After every change the scheduled notification is the live workout's rest's, and none without a rest",
        arguments: seeds, [true, false]
    )
    func scheduled_isTheWorkoutsRest(seed: UInt64, autoRest: Bool) async throws {
        var generator = SplitMix64(seed: seed)
        let rig = Rig()
        let session = EventBuilders.seedSession(autoRest: autoRest)
        try await rig.host.start(session)
        var clock = 10.0
        for step in 0 ..< 50 {
            clock += Double(Int.random(in: 0 ... 120, using: &generator))
            let event = Self.event(&generator, in: session, at: clock)
            let state = try await rig.host.apply(event)
            let due = await rig.notifications.restOverAt
            #expect(due == state.rest?.endsAt, "seed \(seed), step \(step), \(event)")
        }
        // The end, with no screen up: nothing stays scheduled.
        if seed.isMultiple(of: 2) {
            try await rig.host.discard(endedAt: Sample.at(clock))
        } else {
            _ = try await rig.host.finish(endedAt: Sample.at(clock))
        }
        #expect(await rig.notifications.restOverAt == nil, "seed \(seed)")
        #expect(await rig.notifications.calls.last == .cancelRestOver, "seed \(seed)")
    }

    @Test("With auto rest off a logged set schedules nothing; +30s with no rest still starts and schedules one")
    func autoRestOff() async throws {
        let rig = Rig()
        try await rig.host.start(EventBuilders.seedSession(autoRest: false))
        try await rig.host.apply(Sample.logged(0, 0, at: 60))
        #expect(await rig.notifications.calls == [])
        try await rig.host.apply(.restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: Sample.at(90)))
        #expect(await rig.notifications.calls == [.scheduleRestOver(Sample.at(120))])
    }

    /// As built, and a question for F23, not a ruling. Brief criterion 12: killed with a rest running, the
    /// relaunched app shows the correct time left. The criteria are silent on the notification: the host
    /// a relaunch builds asks its client for nothing, on the ground that the system still holds what the
    /// last process scheduled. That is true of a kill; it is not true after the lifter turned
    /// notifications off and on, or of a device restored from a backup, and F23 decides.
    @Test("As built: a relaunch with a rest running asks the new client for nothing (question, F23)")
    func relaunch_midRest_asBuilt() async throws {
        let rig = Rig()
        try await rig.host.start(Sample.session)
        try await rig.host.apply(Sample.logged(0, 0, at: 60))
        #expect(await rig.notifications.restOverAt == Sample.at(210))
        let again = FakeNotifications()
        let relaunched = Rig.host(rig.memory, again)
        let resumed = try await relaunched.resumeFromStore()
        #expect(resumed?.rest?.endsAt == Sample.at(210), "the rest is resumed")
        #expect(await again.calls == [])
        // From there the new host's client hears every change.
        try await relaunched.apply(.restSkipped)
        #expect(await again.calls == [.cancelRestOver])
    }

    @Test("The same walk with no client, the app's host today: every call returns and the workout is the same")
    func noClient_sameWorkout() async throws {
        let rig = Rig()
        let bare = Rig.host(InMemoryStores(seed: .empty), nil)
        try await rig.host.start(Sample.session)
        try await bare.start(Sample.session)
        var generator = SplitMix64(seed: 99)
        var clock = 10.0
        for _ in 0 ..< 60 {
            clock += Double(Int.random(in: 0 ... 120, using: &generator))
            let event = Self.event(&generator, in: Sample.session, at: clock)
            let with = try await rig.host.apply(event)
            let without = try await bare.apply(event)
            let isSame = with == without
            #expect(isSame)
        }
        try await bare.discard(endedAt: Sample.at(clock))
        let left = try await bare.current()
        #expect(left == nil)
    }

    @Test("A client that is slow to schedule does not hold the update: the screen hears of the set first")
    func slowClient_doesNotHoldTheUpdate() async throws {
        let client = ParkingNotifications()
        let host = Rig.host(InMemoryStores(seed: .empty), client)
        try await host.start(Sample.session)
        var updates = await host.updates().makeAsyncIterator()
        _ = await updates.next()
        let applying = Task { try await host.apply(Sample.logged(0, 0, at: 60)) }
        for _ in 0 ..< 20000 where await client.waiting == 0 {
            await Task.yield()
        }
        guard await client.waiting > 0 else {
            Issue.record("the notification's client was never asked")
            applying.cancel()
            return
        }
        // The client has been asked and has not answered. The update is already in the stream.
        let heard = Mutex(false)
        let listening = Task { [updates] in
            var updates = updates
            let update = await updates.next()
            heard.withLock { $0 = update?.state?.doneSets == 1 }
        }
        for _ in 0 ..< 2000 where !heard.withLock({ $0 }) {
            await Task.yield()
        }
        let didHear = heard.withLock { $0 }
        #expect(didHear, "the update waits for the notification's client")
        await client.release()
        _ = try await applying.value
        await listening.value
        #expect(await client.asked == [Sample.at(210)])
    }
}

/// A `NotificationsClient` whose scheduling does not return until the test lets it: a system call that is slow.
actor ParkingNotifications: NotificationsClient {
    private(set) var asked: [Date] = []
    private(set) var waiting = 0
    private var parked: [CheckedContinuation<Void, Never>] = []

    func scheduleRestOver(at endsAt: Date) async {
        asked.append(endsAt)
        waiting += 1
        await withCheckedContinuation { parked.append($0) }
    }

    func cancelRestOver() {}

    func release() {
        waiting = 0
        for call in parked {
            call.resume()
        }
        parked = []
    }
}
