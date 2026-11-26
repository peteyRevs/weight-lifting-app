import Foundation
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S6: both channels as one transport. Mirroring runs on a scripted channel, WatchConnectivity is the phone
/// side of a `FakeLiveNetwork`, and the transports' time is a manual clock; each test waits on the connection
/// stream, the network's `handed` and the channel's sends.
@Suite("CompositeTransport", .tags(.sync), .timeLimit(.minutes(1)))
struct CompositeTransportTests {
    struct Rig {
        let channel = ScriptedChannel()
        let network = FakeLiveNetwork(seed: 6)
        let clock = ManualClock()
        let transport: CompositeTransport
        let running: Task<Void, Never>
        var connection: AsyncStream<LiveConnectionState>.AsyncIterator

        /// Running, with WatchConnectivity up (the network's links start up) and mirroring down.
        init(watchConnectivity: (any LiveWorkoutTransport)? = nil) async {
            let mirroring = MirroringTransport(channel: channel, clock: clock)
            transport = CompositeTransport(
                mirroring: mirroring,
                watchConnectivity: watchConnectivity ?? network.phone,
                clock: clock
            )
            running = Task { [transport] in await transport.run() }
            connection = transport.connection.makeAsyncIterator()
            #expect(await connection.next() == .solo)
        }

        mutating func next() async -> LiveConnectionState? {
            await connection.next()
        }

        func stop() async {
            running.cancel()
            await running.value
            channel.release()
        }
    }

    static let started = WireFrame.envelopes(Sample.log([]))

    /// Whether `frame` carries the phone's second envelope.
    static func holdsSeq2(_ frame: WireFrame) -> Bool {
        guard case let .envelopes(envelopes) = frame else {
            return false
        }
        return envelopes.contains { $0.key == EnvelopeKey(device: Subject.device, seq: 2) }
    }

    @Test("The connection: mirroring first, then WatchConnectivity, then 30 s reconnecting, then solo")
    func connectionStateDerivation() async {
        var rig = await Rig()
        var link = rig.transport.link.makeAsyncIterator()
        #expect(await link.next() == false)
        #expect(await rig.next() == .connected(.watchConnectivity))
        #expect(await link.next() == true)
        rig.channel.connect(true)
        #expect(await rig.next() == .connected(.mirroring))
        #expect(await link.next() == true) // the host's handshake goes on mirroring too
        rig.channel.connect(false)
        #expect(await rig.next() == .connected(.watchConnectivity))
        rig.network.partition()
        #expect(await rig.next() == .reconnecting)
        #expect(await link.next() == false)
        #expect(await rig.clock.nextSleep(skipping: .zero) == CompositeTransport.reconnectWindow)
        rig.clock.advance(by: CompositeTransport.reconnectWindow)
        #expect(await rig.next() == .solo)
        rig.network.heal()
        #expect(await rig.next() == .connected(.watchConnectivity))
        #expect(await link.next() == true)
        await rig.transport.run() // a second run returns at once
        await rig.stop()
        #expect(await rig.next() == nil)
    }

    @Test("Criterion 6: a hung mirrored send never holds up the host; .degraded(.mirroring), the frame goes on WC")
    func hungMirroring_degrades_andWatchConnectivityCarries() async throws {
        var rig = await Rig()
        #expect(await rig.next() == .connected(.watchConnectivity))
        rig.channel.connect(true)
        #expect(await rig.next() == .connected(.mirroring))
        rig.channel.script(.hang)
        let subject = Subject()
        await subject.host.connect(rig.transport, clock: ManualClock())
        var handed = rig.network.phone.handed.makeAsyncIterator()

        try await subject.host.start(Sample.session) // returns with no time gone by, the send queued
        #expect(try await subject.host.current()?.id == Sample.session.id)
        while let frame = await handed.next(), frame != Self.started {} // and on its way over WC
        #expect(await rig.clock.nextSleep(skipping: .zero) == MirroringTransport.batchWindow)
        rig.clock.advance(by: MirroringTransport.batchWindow)
        #expect(await rig.clock.nextSleep(skipping: MirroringTransport.batchWindow) == MirroringTransport.watchdog)
        rig.clock.advance(by: MirroringTransport.watchdog)
        #expect(await rig.next() == .degraded(.mirroring))

        _ = try await subject.host.apply(Sample.logged(0, 0))
        let state = try await subject.host.current()
        #expect(Peer.isDone(state, 0, 0))
        while let frame = await handed.next(), !Self.holdsSeq2(frame) {} // mirroring refuses it now; WC carries it
        rig.network.flush()
        #expect(rig.network.watch.received.contains(Self.started))
        #expect(rig.network.watch.received.contains(where: Self.holdsSeq2))
        rig.network.partition()
        #expect(await rig.next() == .reconnecting) // degraded mirroring reaches no one
        await rig.stop()
    }

    @Test("Frames from either channel arrive on one stream")
    func incoming_isMerged() async throws {
        var rig = await Rig()
        #expect(await rig.next() == .connected(.watchConnectivity))
        var incoming = rig.transport.incoming.makeAsyncIterator()
        try rig.channel.deliver(WireCodec.encode(Self.started))
        #expect(await incoming.next() == Self.started)
        let handshake = WireFrame.handshake(workoutID: Sample.session.id, contiguousSeq: [:])
        try await rig.network.watch.send(handshake)
        rig.network.flush()
        #expect(await incoming.next() == handshake)
        await rig.stop()
    }

    @Test("A send throws only when neither channel took the frame")
    func send_throwsWhenNeitherTakesIt() async throws {
        var rig = await Rig(watchConnectivity: FakeLiveWorkoutTransport())
        await #expect(throws: TransportError.unreachable) { try await rig.transport.send(Self.started) }
        rig.channel.connect(true)
        #expect(await rig.next() == .connected(.mirroring))
        try await rig.transport.send(Self.started) // mirroring took it
        await rig.stop()
    }

    @Test("The liveConnection client: each reader gets the state shown, then each change, until run() ends")
    func states_haveManyReaders() async {
        var rig = await Rig()
        #expect(await rig.next() == .connected(.watchConnectivity))
        var first = await rig.transport.states().makeAsyncIterator()
        var second = await rig.transport.states().makeAsyncIterator()
        #expect(await first.next() == .connected(.watchConnectivity))
        #expect(await second.next() == .connected(.watchConnectivity))
        rig.channel.connect(true)
        #expect(await first.next() == .connected(.mirroring))
        #expect(await second.next() == .connected(.mirroring))
        await rig.stop()
        #expect(await first.next() == nil)
        var late = await rig.transport.states().makeAsyncIterator()
        #expect(await late.next() == .connected(.mirroring))
        #expect(await late.next() == nil)
    }
}
