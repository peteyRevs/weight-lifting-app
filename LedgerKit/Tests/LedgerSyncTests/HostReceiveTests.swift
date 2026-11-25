import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S3: the host takes the peer's envelopes (`receive(_:)`): stored first, rebuilt by replay, with
/// `effects(from:to:)`'s haptics (criterion 9 and its batch and terminal companions), and a workout the peer
/// started or ended becomes what readers see.
@Suite("LocalWorkoutSessionActor · receiving", .tags(.sync), .timeLimit(.minutes(1)))
struct HostReceiveTests {
    /// A phone host with `Sample.session` started, and a listener past its start.
    static func started() async throws -> (Subject, Listener) {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        var listener = await Listener(subject.host)
        _ = await listener.next()
        return (subject, listener)
    }

    @Test("Criterion 9: a set logged on the watch is published with one setLogged haptic, and stored")
    func remoteSet_isPublishedWithOneHaptic() async throws {
        var (subject, listener) = try await Self.started()
        try await subject.host.receive([Peer.set(0, 0, seq: 1)])
        let update = try #require(await listener.next())
        #expect(update.haptics == [.setLogged])
        #expect(Peer.isDone(update.state, 0, 0))
        #expect(await subject.log().contains(Peer.set(0, 0, seq: 1)))
        let own = try await subject.host.apply(Sample.logged(0, 1, at: 90))
        #expect(Peer.isDone(own, 0, 0) && Peer.isDone(own, 0, 1))
        #expect(await subject.log().filter { $0.device == Subject.device }.map(\.seq) == [1, 2])
    }

    @Test("Criterion 9's batch: three remote sets in one frame buzz once, in one update")
    func remoteBatch_buzzesOnce() async throws {
        var (subject, listener) = try await Self.started()
        try await subject.host.receive([Peer.set(0, 0, seq: 1), Peer.set(0, 1, seq: 2), Peer.set(0, 2, seq: 3)])
        let update = try #require(await listener.next())
        #expect(update.haptics == [.setLogged])
        #expect((0 ..< 3).allSatisfy { Peer.isDone(update.state, 0, $0) })
        let marked = try await mark(subject.host)
        #expect(await listener.updates(before: marked).isEmpty)
    }

    @Test("A frame received twice changes nothing the second time, and publishes nothing")
    func duplicate_isIdempotent() async throws {
        var (subject, listener) = try await Self.started()
        let frame = [Peer.set(0, 0, seq: 1), Peer.set(1, 0, seq: 2)]
        try await subject.host.receive(frame)
        _ = await listener.next()
        try await subject.host.receive(frame.reversed())
        let marked = try await mark(subject.host)
        #expect(await listener.updates(before: marked).isEmpty)
        #expect(await subject.log().count == 3 + 1) // started, two remote sets, the mark
    }

    @Test("Criterion 9's terminal: the watch's finish, with a late set, ends the workout here with no haptic")
    func remoteFinish_endsTheWorkout_noHaptic() async throws {
        var (subject, listener) = try await Self.started()
        let finish = Peer.envelope(.finished(endedAt: Sample.at(300)), seq: 2, at: 300)
        try await subject.host.receive([Peer.set(0, 0, seq: 1), finish])
        let update = try #require(await listener.next())
        #expect(update.state?.phase == .finished && update.haptics.isEmpty)
        #expect(Peer.isDone(update.state, 0, 0))
        #expect(try await subject.host.current() == nil)
        #expect(try await subject.stores.workouts.workout(id: Sample.session.id)?.phase == .finished)
        #expect(await subject.stores.events.uncompactedWorkoutIDs().isEmpty)
    }

    @Test("The watch's discard drops the workout here")
    func remoteDiscard_dropsTheWorkout() async throws {
        var (subject, listener) = try await Self.started()
        try await subject.host.receive([Peer.envelope(.discarded(endedAt: Sample.at(100)), seq: 1, at: 100)])
        #expect(try #require(await listener.next()).state?.phase == .discarded)
        #expect(try await subject.host.current() == nil)
        #expect(try await subject.stores.workouts.workout(id: Sample.session.id) == nil)
        #expect(await subject.stores.events.uncompactedWorkoutIDs().isEmpty)
    }

    @Test("A workout the watch started becomes the live one, with one haptic for its done sets; own seqs start at 1")
    func remoteStart_becomesLive() async throws {
        let subject = Subject()
        var listener = await Listener(subject.host)
        #expect(try #require(await listener.next()).state == nil)
        let snapshot = EventBuilders.session(EventBuilders.seedExercises, device: Peer.device)
        try await subject.host.receive(Peer.log([Sample.logged(0, 0)], of: snapshot))
        let update = try #require(await listener.next())
        #expect(update.state?.id == Sample.session.id && update.haptics == [.setLogged])
        #expect(try await subject.host.current()?.originDevice == Peer.device)
        _ = try await subject.host.apply(Sample.logged(0, 1, at: 90))
        #expect(await subject.log().filter { $0.device == Subject.device }.map(\.seq) == [1])
        #expect(await subject.host.hasWatchParticipant(Sample.session.id))
    }

    @Test("Envelopes that arrive before their started wait in the store, and fold in when it comes")
    func beforeStarted_waitsForIt() async throws {
        let subject = Subject()
        let log = Peer.log([Sample.logged(0, 0), Sample.logged(0, 1)])
        try await subject.host.receive(Array(log.dropFirst()))
        #expect(try await subject.host.current() == nil)
        #expect(await subject.log().count == 2)
        try await subject.host.receive([log[0]])
        let live = try #require(try await subject.host.current())
        #expect(Peer.isDone(live, 0, 0) && Peer.isDone(live, 0, 1))
    }

    @Test("The rest the watch starts schedules the rest notification here")
    func remoteRest_schedulesTheNotification() async throws {
        let stores = InMemoryStores()
        let notifications = FakeNotifications()
        let host = LocalWorkoutSessionActor(
            events: stores.events, workouts: stores.workouts, programs: stores.programs,
            device: Subject.device, notifications: notifications, now: { EventBuilders.start }
        )
        try await host.start(Sample.session)
        try await host.receive([Peer.envelope(
            .restStarted(endsAt: Sample.at(150), total: .seconds(90)),
            seq: 1,
            at: 60
        )])
        #expect(await notifications.calls == [.scheduleRestOver(Sample.at(150))])
    }
}
