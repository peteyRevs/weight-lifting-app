import Foundation
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
import Testing

/// G2, F10 S9 ruling Q4, on the host that runs the notification: a member that starts no rest cancels the
/// pending "Rest over", so none is left to buzz in the middle of a round; an un-log afterwards schedules none;
/// and a host relaunched mid-round (a kill) resumes the same rest, none, and the same cursor. Seeded walks on a
/// 3-member block of unequal counts check that the scheduled notification is always the workout's rest.
@Suite(
    "LocalWorkoutSessionActor · supersets and the rest notification (adversarial, F10 S9)",
    .tags(.sync, .property),
    .timeLimit(.minutes(2))
)
struct HostSupersetRestAdversarialTests {
    typealias Rig = HostRestNotificationAdversarialTests.Rig

    /// Bench (1 set, 150 s), then A (3, 90 s), B (1, 60 s), C (2, 120 s) as one block.
    static let session = EventBuilders.session([
        .init("Bench", .barbell, sets: 1, reps: 5, pounds: 185, restSeconds: 150),
        .init("A", .dumbbell, sets: 3, reps: 10, pounds: 55, restSeconds: 90),
        .init("B", .machine, sets: 1, reps: 8, pounds: 70, restSeconds: 60, superset: true),
        .init("C", .cable, sets: 2, reps: 12, pounds: 20, restSeconds: 120, superset: true)
    ])

    static func logged(_ exercise: Int, _ set: Int, at seconds: Double) -> WorkoutEvent {
        let row = session.exercises[exercise].sets[set]
        return .setLogged(
            exerciseIndex: exercise, setID: row.id, weight: row.weight, reps: row.reps, doneAt: Sample.at(seconds)
        )
    }

    @Test("Q4: C1 schedules the group's rest; A2 cancels it, nothing is due mid-round; an un-log schedules nothing")
    func memberMidRound_cancels_andUnlogSchedulesNothing() async throws {
        let rig = Rig()
        try await rig.host.start(Self.session)
        try await rig.host.apply(Self.logged(1, 0, at: 10))
        try await rig.host.apply(Self.logged(2, 0, at: 20))
        #expect(await rig.notifications.calls == [], "A1 and B1 start no rest")
        try await rig.host.apply(Self.logged(3, 0, at: 30))
        #expect(await rig.notifications.restOverAt == Sample.at(150))
        let afterA2 = try await rig.host.apply(Self.logged(1, 1, at: 60))
        #expect(afterA2.rest == nil)
        #expect(await rig.notifications.restOverAt == nil, "no Rest over is left to buzz during the round")
        #expect(await rig.notifications.calls == [.scheduleRestOver(Sample.at(150)), .cancelRestOver])
        let unlog = WorkoutEvent.setUnlogged(exerciseIndex: 1, setID: Self.session.exercises[1].sets[1].id)
        let unlogged = try await rig.host.apply(unlog)
        #expect(unlogged.rest == nil)
        #expect(await rig.notifications.calls.count == 2, "an un-log asks the client for nothing")
        #expect(await rig.notifications.restOverAt == nil)
    }

    @Test("Killed mid-round after Q4 ended the rest: the relaunch resumes no rest, the same cursor, and asks nothing")
    func kill_midRound_afterQ4() async throws {
        let rig = Rig()
        try await rig.host.start(Self.session)
        for (exercise, set, seconds) in [(1, 0, 10.0), (2, 0, 20.0), (3, 0, 30.0), (1, 1, 60.0)] {
            try await rig.host.apply(Self.logged(exercise, set, at: seconds))
        }
        let before = try #require(try await rig.host.current())
        let again = FakeNotifications()
        let relaunched = Rig.host(rig.memory, again)
        let resumed = try #require(try await relaunched.resumeFromStore())
        let same = resumed == before
        #expect(same, "the relaunched workout is the one the killed process held")
        #expect(resumed.rest == nil)
        #expect(resumed.cursor == Cursor(exerciseIndex: 3, setIndex: 1), "C2, the round's next row")
        #expect(await again.calls == [])
        // The round goes on: C2 ends round 2 and schedules on the new client.
        try await relaunched.apply(Self.logged(3, 1, at: 400))
        #expect(await again.calls == [.scheduleRestOver(Sample.at(520))])
    }

    @Test("Killed with the group's rest running: the relaunch resumes that rest; the next member cancels it")
    func kill_duringGroupRest() async throws {
        let rig = Rig()
        try await rig.host.start(Self.session)
        for (exercise, set, seconds) in [(1, 0, 10.0), (2, 0, 20.0), (3, 0, 30.0)] {
            try await rig.host.apply(Self.logged(exercise, set, at: seconds))
        }
        let again = FakeNotifications()
        let relaunched = Rig.host(rig.memory, again)
        let resumed = try #require(try await relaunched.resumeFromStore())
        #expect(resumed.rest == RestTimer(endsAt: Sample.at(150), total: .seconds(120)))
        let next = try await relaunched.apply(Self.logged(1, 1, at: 60))
        #expect(next.rest == nil)
        #expect(await again.calls == [.cancelRestOver], "the notification the killed process scheduled is cancelled")
    }

    @Test(
        "Seeded walks on a 3-member block: after every change the scheduled notification is the workout's rest",
        arguments: [true, false]
    )
    func seeded_scheduledIsTheRest(autoRest: Bool) async throws {
        for seed in HostRestNotificationAdversarialTests.seeds.prefix(20) {
            var generator = SplitMix64(seed: seed)
            let rig = Rig()
            var session = Self.session
            session.autoRest = autoRest
            try await rig.host.start(session)
            var clock = 10.0
            for step in 0 ..< 40 {
                clock += Double(Int.random(in: 0 ... 120, using: &generator))
                let event = HostRestNotificationAdversarialTests.event(&generator, in: session, at: clock)
                let state = try await rig.host.apply(event)
                let due = await rig.notifications.restOverAt
                #expect(due == state.rest?.endsAt, "seed \(seed), step \(step), \(event)")
            }
        }
    }
}
