import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criteria 2, 3 and 10: an own action on the host. What the contract cannot see: the stamp (`seq`
/// and the hybrid logical clock), what is stored and when, and a store that refuses.
@Suite("LocalWorkoutSessionActor · own actions", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorTests {
    typealias Update = WorkoutSessionUpdate

    @Test("Each accepted event takes this device's next seq, from 1, and is stored in the order applied")
    func apply_assignsNextSeq() async throws {
        let subject = Subject()
        let events = [Sample.logged(0, 0), Sample.retargeted(0, 1, pounds: 190), .restSkipped]
        try await subject.host.start(Sample.session)
        for event in events {
            try await subject.host.apply(event)
        }
        let log = await subject.log()
        #expect(log.map(\.seq) == [1, 2, 3, 4])
        #expect(log.map(\.event) == [.started(Sample.session)] + events)
        #expect(log.allSatisfy { $0.device == Subject.device && $0.workoutID == Sample.session.id })
        #expect(try await subject.host.current() == WorkoutEngine.replay(log))
    }

    @Test("An event is stored before anyone is told: while the store holds the append, the workout stands as it was")
    func apply_storesBeforePublishing() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        await subject.probe.hold(.append)
        async let applied = subject.host.apply(Sample.logged(0, 0))
        await subject.probe.waitUntilHeld()
        #expect(try await subject.host.current() == Sample.session)
        var joining = await Listener(subject.host)
        #expect(await joining.next() == Update(state: Sample.session))
        await subject.probe.release()
        let next = try await applied
        #expect(try await subject.host.current() == next)
        #expect(await joining.next() == Update(state: next, haptics: [.setLogged]))
    }

    @Test("An event the engine ignores stores nothing and takes no seq or stamp")
    func apply_ignoredEvent_storesNothing() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        await subject.probe.clearCalls()
        let ignored: [WorkoutEvent] = [.started(Sample.other), Sample.logged(0, 0, at: .infinity)]
        for event in ignored {
            #expect(try await subject.host.apply(event) == Sample.session)
        }
        #expect(await subject.writes() == [])
        try await subject.host.apply(.restSkipped)
        let log = await subject.log()
        #expect(log.map(\.seq) == [1, 2])
        // The clock read the same time for every call, so the accepted event is one tick after the start.
        #expect(log.map(\.wallClock) == [EventBuilders.start, EventBuilders.start.addingTimeInterval(0.001)])
    }

    @Test("A store that refuses the append: the call throws and nothing changes, neither state, seq, clock nor stream")
    func apply_storeRefuses_changesNothing() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        var listener = await Listener(subject.host)
        await subject.probe.fail(.append)
        await #expect(throws: StoreProbe.Refusal(call: .append)) {
            try await subject.host.apply(Sample.logged(0, 0))
        }
        #expect(try await subject.host.current() == Sample.session)
        #expect(await subject.log().map(\.seq) == [1])
        // The retry takes the seq and the stamp the refused event would have taken.
        let retried = try await subject.host.apply(Sample.logged(0, 0))
        let log = await subject.log()
        #expect(log.map(\.seq) == [1, 2])
        #expect(log.map(\.wallClock) == [EventBuilders.start, EventBuilders.start.addingTimeInterval(0.001)])
        let mark = try await mark(subject.host)
        #expect(await listener.updates(before: mark) == [
            Update(state: Sample.session), Update(state: retried, haptics: [.setLogged])
        ])
    }

    @Test("A store that refuses the start: nothing is live, and the next start begins at seq 1")
    func start_storeRefuses_startsNothing() async throws {
        let subject = Subject()
        var listener = await Listener(subject.host)
        await subject.probe.fail(.append)
        await #expect(throws: StoreProbe.Refusal(call: .append)) { try await subject.host.start(Sample.session) }
        #expect(try await subject.host.current() == nil)
        #expect(await subject.log().isEmpty)
        try await subject.host.start(Sample.session)
        #expect(await subject.log().map(\.seq) == [1])
        let mark = try await mark(subject.host)
        #expect(await listener.updates(before: mark) == [Update(state: nil), Update(state: Sample.session)])
    }

    @Test("A store that stored the event and then threw: the next call reads the store first, and tells the streams")
    func append_lostAcknowledgement_isRecovered() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        var listener = await Listener(subject.host)
        await subject.probe.fail(.append, afterStoring: true)
        await #expect(throws: StoreProbe.Refusal(call: .append)) {
            try await subject.host.apply(Sample.logged(0, 0))
        }
        #expect(await subject.host.needsRecovery)
        let logged = try #require(await WorkoutEngine.replay(subject.log()))
        #expect(logged.doneSets == 1)
        #expect(try await subject.host.current() == logged)
        #expect(await !subject.host.needsRecovery)
        try await subject.host.apply(.restSkipped)
        #expect(await subject.log().map(\.seq) == [1, 2, 3])
        let mark = try await mark(subject.host)
        // The corrected state carries no haptic: the host did not see the set being logged.
        let heard = await listener.updates(before: mark)
        #expect(heard.prefix(2) == [Update(state: Sample.session), Update(state: logged)])
    }

    @Test("After a workout ends, the next one's seq starts at 1 again")
    func start_afterAnEnd_startsItsSeqAtOne() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        try await subject.host.apply(Sample.logged(0, 0))
        try await subject.host.discard(endedAt: Sample.at(600))
        try await subject.host.start(Sample.other)
        try await subject.host.apply(.restSkipped)
        #expect(await subject.log(of: Sample.other.id).map(\.seq) == [1, 2])
    }

    @Test("An update carries the engine's haptics for its event and nothing else of its effects")
    func effects_forwardHapticsOnly() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        var listener = await Listener(subject.host)
        // The last set of the first exercise's round: the engine buzzes, starts a rest and schedules its notification.
        let next = try await subject.host.apply(Sample.logged(0, 0))
        let envelope = try #require(await subject.log().last)
        let effects = WorkoutEngine.reduce(Sample.session, envelope).1
        #expect(effects.contains(.scheduleRestNotification(endsAt: Sample.at(60 + 150))))
        _ = await listener.next()
        #expect(await listener.next() == Update(state: next, haptics: Update.haptics(from: effects)))
        #expect(Update.haptics(from: effects) == [.setLogged])
    }

    @Test("Thousands of dropped streams and hundreds of cancelled readers disturb no later subscriber or publication")
    func endedStreams_disturbNoOne() async throws {
        let subject = Subject()
        var kept = await Listener(subject.host)
        for _ in 0 ..< 2000 {
            _ = await subject.host.updates()
        }
        try await subject.host.start(Sample.session)
        var expected = [Update(state: nil), Update(state: Sample.session)]
        for number in 0 ..< 100 {
            let stream = await subject.host.updates()
            let reader = Task { for await _ in stream {} }
            reader.cancel()
            await reader.value
            let next = try await subject.host.apply(Sample.retargeted(0, 0, pounds: Decimal(100 + number)))
            expected.append(Update(state: next))
        }
        var late = await Listener(subject.host)
        let mark = try await mark(subject.host)
        #expect(await kept.updates(before: mark) == expected)
        #expect(await late.updates(before: mark) == [Update(state: expected.last?.state)])
    }
}
