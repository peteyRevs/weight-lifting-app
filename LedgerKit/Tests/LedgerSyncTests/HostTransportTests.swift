import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S4a: the host on a transport. It sends its own envelopes as it stores them, never waiting on the send
/// (criterion 6's host half), answers handshakes and replay requests from its store, sends a handshake on every
/// link-up and after a resume (criterion 10), and asks again for what a failed receipt did not store. Each test
/// drives its `FakeLiveNetwork` from its own task alone.
@Suite("LocalWorkoutSessionActor · the transport", .tags(.sync), .timeLimit(.minutes(1)))
struct HostTransportTests {
    /// A phone host connected to the phone side of a network, and what it hands the network.
    struct Rig {
        let network = FakeLiveNetwork(seed: 11)
        let clock = ManualClock()
        let subject: Subject
        var handed: AsyncStream<WireFrame>.AsyncIterator

        init(_ subject: Subject = Subject()) async {
            self.subject = subject
            handed = network.phone.handed.makeAsyncIterator()
            await subject.host.connect(network.phone, clock: clock)
        }

        mutating func next() async -> WireFrame? {
            await handed.next()
        }
    }

    /// The keys of an `.envelopes` frame, nil for another frame.
    static func keys(_ frame: WireFrame?) -> [EnvelopeKey]? {
        guard case let .envelopes(envelopes) = frame else {
            return nil
        }
        return envelopes.map(\.key)
    }

    static func key(_ device: DeviceID, _ seq: UInt64) -> EnvelopeKey {
        EnvelopeKey(device: device, seq: seq)
    }

    static let workout = Sample.session.id

    @Test("Each own envelope is sent as it is stored, in order, one frame each")
    func ownEnvelopes_areSentInOrder() async throws {
        var rig = await Rig()
        try await rig.subject.host.start(Sample.session)
        _ = try await rig.subject.host.apply(Sample.logged(0, 0))
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 1)])
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 2)])
    }

    @Test("Criterion 6, host half: a hung send never holds up a call, and is given up after 3 s")
    func hungSend_neverBlocks_andTimesOut() async throws {
        var rig = await Rig()
        rig.network.phone.hang = true
        try await rig.subject.host.start(Sample.session)
        #expect(try await rig.subject.host.current()?.id == Self.workout)
        var hung = rig.network.phone.hung.makeAsyncIterator()
        #expect(await Self.keys(hung.next()) == [Self.key(Subject.device, 1)])
        _ = try await rig.subject.host.apply(Sample.logged(0, 0)) // returns while the first send hangs
        #expect(await rig.clock.nextSleep(skipping: .zero) == LocalWorkoutSessionActor.sendTimeout)
        rig.clock.advance(by: LocalWorkoutSessionActor.sendTimeout)
        #expect(await Self.keys(hung.next()) == [Self.key(Subject.device, 2)]) // the sender gave the first up
        #expect(rig.network.phone.sent.isEmpty)
    }

    @Test("Criterion 10: after a relaunch, the link coming up sends a handshake with the stored vector")
    func relaunch_sendsTheHandshake() async throws {
        let before = Subject()
        try await before.host.start(Sample.session)
        _ = try await before.host.apply(Sample.logged(0, 0))
        try await before.host.receive([Peer.set(0, 1, seq: 1)])
        var rig = await Rig(before.relaunched())
        let vector = [Subject.device: UInt64(2), Peer.device: 1]
        #expect(await rig.next() == .handshake(workoutID: Self.workout, contiguousSeq: vector))
        #expect(try await rig.subject.host.current()?.id == Self.workout)
        rig.network.partition()
        rig.network.heal()
        #expect(await rig.next() == .handshake(workoutID: Self.workout, contiguousSeq: vector))
    }

    @Test("A handshake gets what its vector lacks, then this host's handshake, at most once per 10 s")
    func handshake_repliesWithTheGap_thenOwnHandshake() async throws {
        var rig = await Rig()
        try await rig.subject.host.start(Sample.session)
        _ = try await rig.subject.host.apply(Sample.logged(0, 0))
        _ = try await rig.subject.host.apply(Sample.logged(0, 1))
        try await rig.subject.host.receive([Peer.set(1, 0, seq: 1), Peer.set(1, 1, seq: 2)])
        for _ in 0 ..< 3 {
            _ = await rig.next()
        }
        let peer = [Subject.device: UInt64(1), Peer.device: 2]
        try await rig.subject.host.receive(.handshake(workoutID: Self.workout, contiguousSeq: peer))
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 2), Self.key(Subject.device, 3)])
        let own = [Subject.device: UInt64(3), Peer.device: 2]
        #expect(await rig.next() == .handshake(workoutID: Self.workout, contiguousSeq: own))
        try await rig.subject.host.receive(.handshake(workoutID: Self.workout, contiguousSeq: [:]))
        #expect(await Self.keys(rig.next())?.count == 5)
        _ = try await rig.subject.host.apply(Sample.logged(0, 2))
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 4)]) // no second handshake within 10 s
        rig.subject.clock.set(Sample.at(10))
        try await rig.subject.host.receive(.handshake(workoutID: Self.workout, contiguousSeq: own))
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 4)])
        let later = [Subject.device: UInt64(4), Peer.device: 2]
        #expect(await rig.next() == .handshake(workoutID: Self.workout, contiguousSeq: later))
    }

    @Test("A replay request gets what it lacks and no handshake; relayed envelopes are sent too")
    func replayRequest_repliesOnly() async throws {
        var rig = await Rig()
        try await rig.subject.host.start(Sample.session)
        try await rig.subject.host.receive([Peer.set(0, 0, seq: 1)])
        _ = await rig.next()
        try await rig.subject.host.receive(.replayRequest(workoutID: Self.workout, contiguousSeq: [:]))
        let all = [Self.key(Subject.device, 1), Self.key(Peer.device, 1)]
        #expect(await Self.keys(rig.next()) == all)
        try await rig.subject.host.receive(.replayRequest(workoutID: Self.workout, contiguousSeq: [Peer.device: 1]))
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 1)])
        try await rig.subject.host.receive(
            .replayRequest(workoutID: Self.workout, contiguousSeq: [Subject.device: 1, Peer.device: 1])
        )
        _ = try await rig.subject.host.apply(Sample.logged(0, 1))
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 2)]) // nothing was lacking
    }

    @Test("The vector stops below a hole, so a lost envelope under a received one is replayed")
    func vector_stopsBelowAHole() async throws {
        var rig = await Rig()
        try await rig.subject.host.start(Sample.session)
        _ = await rig.next()
        try await rig.subject.host.receive([Peer.set(0, 0, seq: 1), Peer.set(0, 2, seq: 3)])
        try await rig.subject.host.receive(.handshake(workoutID: Self.workout, contiguousSeq: [Subject.device: 1]))
        #expect(await Self.keys(rig.next()) == [Self.key(Peer.device, 1), Self.key(Peer.device, 3)])
        let vector = [Subject.device: UInt64(1), Peer.device: 1]
        #expect(await rig.next() == .handshake(workoutID: Self.workout, contiguousSeq: vector))
    }

    @Test("A handshake for a workout this store has no log of is answered with an empty vector")
    func unknownWorkout_isAskedForWhole() async throws {
        var rig = await Rig()
        let other = Sample.other.id
        try await rig.subject.host.receive(.handshake(workoutID: other, contiguousSeq: [Peer.device: 4]))
        #expect(await rig.next() == .handshake(workoutID: other, contiguousSeq: [:]))
    }

    @Test("A receipt the store failed asks the peer again, at most once per 10 s, and still throws")
    func failedReceipt_asksAgain() async throws {
        var rig = await Rig()
        try await rig.subject.host.start(Sample.session)
        _ = await rig.next()
        await rig.subject.probe.fail(.append, times: 2)
        let frame = WireFrame.envelopes([Peer.set(0, 0, seq: 1)])
        #expect(await failure { try await rig.subject.host.receive(frame) } != nil)
        #expect(await rig.next() == .replayRequest(workoutID: Self.workout, contiguousSeq: [Subject.device: 1]))
        #expect(await failure { try await rig.subject.host.receive(frame) } != nil)
        _ = try await rig.subject.host.apply(Sample.logged(0, 1))
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 2)])
    }

    @Test("A second transport is refused; the first stays connected")
    func secondTransport_isIgnored() async throws {
        var rig = await Rig()
        await rig.subject.host.connect(FakeLiveWorkoutTransport())
        try await rig.subject.host.start(Sample.session)
        #expect(await Self.keys(rig.next()) == [Self.key(Subject.device, 1)])
    }
}
