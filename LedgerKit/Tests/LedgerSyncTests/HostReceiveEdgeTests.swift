import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S3: what the host drops or keeps aside on receipt (the drift bound, non-finite dates, a conflicting key, a
/// second live workout, an ended one nobody was shown, an incomplete log), its own relayed envelopes,
/// `hasWatchParticipant`, and a frame carried by `FakeLiveNetwork` from a watch host to a phone host.
@Suite("LocalWorkoutSessionActor · receiving, edges", .tags(.sync), .timeLimit(.minutes(1)))
struct HostReceiveEdgeTests {
    @Test("A stamp beyond the drift bound, or a date that is not finite, is dropped before anything is stored")
    func receipt_dropsWhatItCannotTrust() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        let ahead = Peer.set(0, 0, seq: 1, at: LocalWorkoutSessionActor.driftBound + 1)
        let edge = Peer.set(0, 1, seq: 2, at: LocalWorkoutSessionActor.driftBound)
        let notANumber = Peer.envelope(
            .finished(endedAt: Date(timeIntervalSinceReferenceDate: .nan)), seq: 3, at: 60
        )
        try await subject.host.receive([ahead, edge, notANumber])
        #expect(await subject.log().map(\.key) == [Sample.log([])[0].key, edge.key])
        let live = try #require(try await subject.host.current())
        #expect(!Peer.isDone(live, 0, 0) && Peer.isDone(live, 0, 1))
    }

    @Test("A batch with a key that conflicts with a stored envelope keeps the rest, and drops only that one")
    func conflict_dropsOnlyTheConflictingEnvelope() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        try await subject.host.receive([Peer.set(0, 0, seq: 1)])
        let reused = Peer.set(1, 0, seq: 1) // the watch reused seq 1 for another set
        try await subject.host.receive([reused, Peer.set(2, 0, seq: 2)])
        let live = try #require(try await subject.host.current())
        #expect(Peer.isDone(live, 0, 0) && !Peer.isDone(live, 1, 0) && Peer.isDone(live, 2, 0))
        #expect(await subject.log().count == 3)
    }

    @Test("A store that fails mid-receipt throws; the next call reads the store again and goes on")
    func storeFailure_throws_thenRecovers() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        await subject.probe.fail(.append)
        #expect(await failure { try await subject.host.receive([Peer.set(0, 0, seq: 1)]) } != nil)
        try await subject.host.receive([Peer.set(0, 0, seq: 1)])
        #expect(try await Peer.isDone(subject.host.current(), 0, 0))
    }

    @Test("The phone's own envelopes relayed back move its seq on, so it never reuses one")
    func relayedOwnEnvelopes_moveTheSeqOn() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        let relayed = Peer.envelope(Sample.logged(0, 0), seq: 5, at: 60, from: Subject.device)
        try await subject.host.receive([relayed])
        _ = try await subject.host.apply(Sample.logged(0, 1, at: 90))
        #expect(await subject.log().filter { $0.device == Subject.device }.map(\.seq) == [1, 5, 6])
        #expect(await !subject.host.hasWatchParticipant(Sample.session.id))
    }

    @Test("A second live workout from the watch is stored and kept aside; the live one is unchanged")
    func secondLiveWorkout_isKeptAside() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        var listener = await Listener(subject.host)
        _ = await listener.next()
        try await subject.host.receive(Peer.log([Sample.logged(0, 0)], of: Sample.other))
        let marked = try await mark(subject.host)
        #expect(await listener.updates(before: marked).isEmpty)
        #expect(try await subject.host.current()?.id == Sample.session.id)
        #expect(await subject.log(of: Sample.other.id).count == 2)
    }

    @Test("A workout that arrives already finished is saved without being shown")
    func endedWorkout_isSavedUnshown() async throws {
        let subject = Subject()
        var listener = await Listener(subject.host)
        _ = await listener.next()
        try await subject.host.receive(Peer.log([Sample.logged(0, 0), .finished(endedAt: Sample.at(300))]))
        #expect(try await subject.stores.workouts.workout(id: Sample.session.id)?.phase == .finished)
        #expect(await subject.stores.events.uncompactedWorkoutIDs().isEmpty)
        #expect(await subject.host.hasWatchParticipant(Sample.session.id)) // remembered after the log went
        try await subject.host.start(Sample.other)
        #expect(try #require(await listener.next()).state?.id == Sample.other.id)
    }

    @Test("A finish that arrives for a log with unreadable rows is kept, live or not, and never saved")
    func incompleteLog_isNeverSaved() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        await subject.probe.pretendUnreadable(1)
        try await subject.host.receive([Peer.envelope(.finished(endedAt: Sample.at(300)), seq: 1, at: 300)])
        #expect(try await subject.host.current()?.phase == .live)
        try await subject.host.receive(Peer.log([.finished(endedAt: Sample.at(300))], of: Sample.other))
        #expect(try await subject.stores.workouts.workout(id: Sample.session.id) == nil)
        #expect(try await subject.stores.workouts.workout(id: Sample.other.id) == nil)
        #expect(await subject.stores.events.uncompactedWorkoutIDs().count == 2)
    }

    @Test("A store that cannot be read answers that a watch took part, so the phone never saves it twice")
    func participant_unreadableStore_answersTrue() async throws {
        let subject = Subject()
        try await subject.host.start(Sample.session)
        #expect(await !subject.host.hasWatchParticipant(Sample.session.id))
        await subject.probe.fail(.envelopes)
        #expect(await subject.host.hasWatchParticipant(Sample.session.id))
    }

    @Test("A watch host's log, carried as one frame by FakeLiveNetwork, gives the phone host the same workout")
    func network_carriesTheWatchLog() async throws {
        let network = FakeLiveNetwork(seed: 7)
        let watchStores = InMemoryStores()
        let watch = LocalWorkoutSessionActor(
            events: watchStores.events, workouts: watchStores.workouts, programs: watchStores.programs,
            device: Peer.device, now: { EventBuilders.start }
        )
        let phone = Subject()
        try await watch.start(Sample.session)
        _ = try await watch.apply(Sample.logged(0, 0))
        _ = try await watch.apply(.restStarted(endsAt: Sample.at(200), total: .seconds(120)))
        let watchLog = await watchStores.events.envelopes(for: Sample.session.id)
        try await network.watch.send(.envelopes(watchLog))
        network.flush()
        var incoming = network.phone.incoming.makeAsyncIterator()
        guard case let .envelopes(received) = try #require(await incoming.next()) else {
            Issue.record("the frame is not an envelopes frame")
            return
        }
        try await phone.host.receive(received)
        let same = try await phone.host.current() == watch.current()
        #expect(same)
    }
}
