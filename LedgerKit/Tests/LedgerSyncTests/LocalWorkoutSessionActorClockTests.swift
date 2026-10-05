import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criterion 3: the host's stamps. A stamp is `max(now, newest + 1 ms)`, continues from the store
/// after a relaunch, and is never a time that is not finite (F04 findings 6 and 12; ADR-004's amendment).
@Suite("LocalWorkoutSessionActor · the clock", .tags(.sync), .timeLimit(.minutes(1)))
struct LocalWorkoutSessionActorClockTests {
    static let tick = HybridLogicalClock.tick
    static let start = EventBuilders.start

    @Test("A system clock that steps back never yields a stamp older than one already stored")
    func stamps_surviveAStepBack() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        subject.clock.set(Self.start.addingTimeInterval(-3600))
        try await subject.host.apply(Sample.logged(0, 0))
        try await subject.host.apply(Sample.retargeted(0, 1, pounds: 190))
        subject.clock.set(Self.start.addingTimeInterval(10))
        try await subject.host.apply(.restSkipped)
        let stamps = await subject.log().map(\.wallClock)
        #expect(stamps == [
            Self.start,
            Self.start.addingTimeInterval(Self.tick),
            Self.start.addingTimeInterval(Self.tick).addingTimeInterval(Self.tick),
            Self.start.addingTimeInterval(10)
        ])
        // The log reads back in the order the events were applied, so replay is the host's own state.
        #expect(await subject.log().map(\.seq) == [1, 2, 3, 4])
        #expect(try await subject.host.current() == WorkoutEngine.replay(subject.log()))
    }

    @Test(
        "After a relaunch the clock continues from the store's newest stamp, whether the launch or the call recovers",
        arguments: [true, false]
    )
    func relaunch_continuesTheClock(launchRecovers: Bool) async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        try await subject.host.apply(Sample.logged(0, 0))
        // An un-log stamped before the log it undoes would be replayed first, and lost (finding 12).
        subject.clock.set(Self.start.addingTimeInterval(-86400))
        let relaunched = subject.relaunched()
        if launchRecovers {
            try await relaunched.host.resumeFromStore()
        }
        let unlogged = try await relaunched.host.apply(.setUnlogged(
            exerciseIndex: 0,
            setID: EventBuilders.setID(0, 0)
        ))
        let log = await subject.log()
        #expect(log.map(\.seq) == [1, 2, 3])
        #expect(log.last?.wallClock == Self.start.addingTimeInterval(Self.tick).addingTimeInterval(Self.tick))
        #expect(unlogged.doneSets == 0)
        #expect(WorkoutEngine.replay(log) == unlogged)
    }

    static let notFinite: [Double] = [.nan, .infinity, -.infinity]

    @Test("A clock that is not finite: start throws the host's own error, never notStartable", arguments: notFinite)
    func start_clockNotFinite_isTheHostsFault(reading: Double) async throws {
        let subject = Subject()
        subject.clock.set(Date(timeIntervalSinceReferenceDate: reading))
        var listener = await Listener(subject.host)
        await #expect(throws: LedgerSyncError.noFiniteStamp) { try await subject.host.start(Sample.session) }
        #expect(try await subject.host.current() == nil)
        #expect(await subject.writes() == [])
        subject.clock.set(Self.start)
        try await subject.host.start(Sample.session)
        let mark = try await mark(subject.host)
        #expect(await listener.updates(before: mark) == [
            WorkoutSessionUpdate(state: nil), WorkoutSessionUpdate(state: Sample.session)
        ])
    }

    @Test(
        "A clock that is not finite: apply and the ends throw, never answer as for an ignored event",
        arguments: notFinite
    )
    func apply_clockNotFinite_isTheHostsFault(reading: Double) async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        subject.clock.set(Date(timeIntervalSinceReferenceDate: reading))
        await subject.probe.clearCalls()
        await #expect(throws: LedgerSyncError.noFiniteStamp) { try await subject.host.apply(Sample.logged(0, 0)) }
        await #expect(throws: LedgerSyncError.noFiniteStamp) {
            _ = try await subject.host.finish(endedAt: Sample.at(600))
        }
        await #expect(throws: LedgerSyncError.noFiniteStamp) {
            try await subject.host.discard(endedAt: Sample.at(600))
        }
        #expect(try await subject.host.current() == Sample.session)
        #expect(await subject.writes() == [])
        // Once the clock reads a time again the host goes on from its last stamp.
        subject.clock.set(Self.start)
        try await subject.host.apply(Sample.logged(0, 0))
        #expect(await subject.log().map(\.wallClock) == [Self.start, Self.start.addingTimeInterval(Self.tick)])
    }

    @Test("A stored stamp that is not finite is not what the clock continues from")
    func recovery_skipsNonFiniteStamps() async throws {
        var log = Sample.log([Sample.logged(0, 0)])
        log.append(EventBuilders.envelope(
            .restSkipped,
            seq: 3,
            at: Date(timeIntervalSinceReferenceDate: .infinity),
            workoutID: Sample.session.id
        ))
        let subject = Subject(seed: InMemoryStores.Seed(envelopes: log))
        let resumed = try await subject.host.resumeFromStore()
        #expect(resumed?.doneSets == 1)
        try await subject.host.apply(Sample.retargeted(0, 1, pounds: 190))
        let stored = await subject.log().first { $0.seq == 4 }
        // The newest finite stamp is the logged set's, ten seconds after the start; the device clock reads the start.
        #expect(stored?.wallClock == Self.start.addingTimeInterval(10 + Self.tick))
    }
}
