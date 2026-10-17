import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S6, criterion 8: the host, not a screen, runs the engine's `.scheduleRestNotification` and
/// `.cancelRestNotification`, through the `NotificationsClient` it was given, so they run with no cover up.
/// A host that was given none (the app's, until F23) runs neither, and nothing traps.
@Suite("LocalWorkoutSessionActor · the rest notification", .tags(.sync), .timeLimit(.minutes(1)))
struct HostRestNotificationTests {
    typealias Call = FakeNotifications.Call

    struct Rig {
        let host: LocalWorkoutSessionActor
        let notifications = FakeNotifications()
        let probe: StoreProbe

        init(notifies: Bool = true) {
            let memory = InMemoryStores(seed: .empty)
            let probed = ProbedStores(events: memory.events, workouts: memory.workouts, programs: memory.programs)
            probe = probed.probe
            host = LocalWorkoutSessionActor(
                events: probed.events,
                workouts: probed.workouts,
                programs: probed.programs,
                device: EventBuilders.phone,
                notifications: notifies ? notifications : nil,
                now: { EventBuilders.start }
            )
        }
    }

    @Test("A logged set schedules the notification for the rest's end; +30s schedules it again; a skip cancels it")
    func restStarted_extended_skipped() async throws {
        let rig = Rig()
        try await rig.host.start(Sample.session)
        #expect(await rig.notifications.calls == [])
        // Bench rests 150 s: logged at 60 s, the rest ends at 210 s.
        try await rig.host.apply(Sample.logged(0, 0, at: 60))
        #expect(await rig.notifications.calls == [.scheduleRestOver(Sample.at(210))])
        try await rig.host.apply(.restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: Sample.at(100)))
        #expect(await rig.notifications.restOverAt == Sample.at(240))
        try await rig.host.apply(.restSkipped)
        #expect(await rig.notifications.calls == [
            .scheduleRestOver(Sample.at(210)), .scheduleRestOver(Sample.at(240)), .cancelRestOver
        ])
        #expect(await rig.notifications.restOverAt == nil)
    }

    @Test("An event that changes no rest calls nothing: a stepper, an un-log, an event the engine ignores")
    func otherEvents_callNothing() async throws {
        let rig = Rig()
        try await rig.host.start(Sample.session)
        try await rig.host.apply(Sample.retargeted(0, 1, pounds: 190))
        try await rig.host.apply(.started(Sample.other))
        #expect(await rig.notifications.calls == [])
        try await rig.host.apply(Sample.logged(0, 0, at: 60))
        try await rig.host.apply(.setUnlogged(exerciseIndex: 0, setID: EventBuilders.setID(0, 0)))
        #expect(await rig.notifications.calls == [.scheduleRestOver(Sample.at(210))], "rule 22")
    }

    @Test("A snapshot that starts with a rest schedules it (rule 1)")
    func startWithARest_schedulesIt() async throws {
        let rig = Rig()
        var resting = Sample.session
        resting.rest = RestTimer(endsAt: Sample.at(45), total: .seconds(60))
        try await rig.host.start(resting)
        #expect(await rig.notifications.calls == [.scheduleRestOver(Sample.at(45))])
    }

    @Test("A discard and a finish cancel the notification, with no screen listening", arguments: [true, false])
    func end_cancels(isDiscard: Bool) async throws {
        let rig = Rig()
        try await rig.host.start(Sample.session)
        try await rig.host.apply(Sample.logged(0, 0, at: 60))
        if isDiscard {
            try await rig.host.discard(endedAt: Sample.at(90))
        } else {
            _ = try await rig.host.finish(endedAt: Sample.at(90))
        }
        #expect(await rig.notifications.calls == [.scheduleRestOver(Sample.at(210)), .cancelRestOver])
        #expect(try await rig.host.current() == nil)
    }

    @Test("A change the store refuses schedules nothing: the notification follows the stored envelope")
    func refusedAppend_schedulesNothing() async throws {
        let rig = Rig()
        try await rig.host.start(Sample.session)
        await rig.probe.fail(.append)
        await #expect(throws: StoreProbe.Refusal(call: .append)) {
            try await rig.host.apply(Sample.logged(0, 0, at: 60))
        }
        #expect(await rig.notifications.calls == [])
    }

    @Test("An end whose save fails has still cancelled the notification: the workout ended in its log")
    func endThatFailsToSave_hasCancelled() async throws {
        let rig = Rig()
        try await rig.host.start(Sample.session)
        try await rig.host.apply(Sample.logged(0, 0, at: 60))
        await rig.probe.fail(.materialize)
        await #expect(throws: StoreProbe.Refusal(call: .materialize)) {
            _ = try await rig.host.finish(endedAt: Sample.at(90))
        }
        #expect(await rig.notifications.calls.last == .cancelRestOver)
        #expect(await rig.notifications.calls.count == 2)
    }

    @Test("Recovery schedules nothing: a notification the system holds outlives the process")
    func recovery_schedulesNothing() async throws {
        let rig = Rig()
        try await rig.host.start(Sample.session)
        try await rig.host.apply(Sample.logged(0, 0, at: 60))
        let before = await rig.notifications.calls
        try await rig.host.resumeFromStore()
        #expect(await rig.notifications.calls == before)
    }

    @Test("A host that was given no client runs the same workout and calls nothing: the app's case until F23")
    func noClient_runsNothing_andDoesNotTrap() async throws {
        let rig = Rig(notifies: false)
        try await rig.host.start(Sample.session)
        let rested = try await rig.host.apply(Sample.logged(0, 0, at: 60))
        #expect(rested.rest == RestTimer(endsAt: Sample.at(210), total: .seconds(150)))
        try await rig.host.apply(.restSkipped)
        try await rig.host.discard(endedAt: Sample.at(90))
        #expect(await rig.notifications.calls == [])
    }
}
