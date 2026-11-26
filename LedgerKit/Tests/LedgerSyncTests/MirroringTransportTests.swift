import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S6: the mirrored session's transport on a scripted channel and a manual clock. Each test drives the
/// channel and the clock from its own task and waits on what the transport announces: its status, the channel's
/// sends and the clock's sleeps.
@Suite("MirroringTransport", .tags(.sync), .timeLimit(.minutes(1)))
struct MirroringTransportTests {
    typealias Status = MirroringTransport.Status

    static let workout = Sample.session.id
    static let handshake = WireFrame.handshake(workoutID: workout, contiguousSeq: [Subject.device: 1])
    static let log = Sample.log([Sample.logged(0, 0), Sample.logged(0, 1), Sample.logged(0, 2)])

    static func envelopes(_ range: ClosedRange<Int>) -> WireFrame {
        .envelopes(Array(log[range]))
    }

    @Test("Nothing is sent before the channel is up (F16 reports it after .prepared and the mirror's start)")
    func nothingBeforeTheChannelIsUp() async throws {
        var rig = await Rig()
        await #expect(throws: TransportError.unreachable) { try await rig.transport.send(Self.handshake) }
        await rig.connect(true)
        try await rig.transport.send(Self.handshake)
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.handshake) // the first send the channel saw
        await rig.stop()
    }

    @Test("Frames handed within 150 ms go as one batch, neighbouring envelopes as one frame")
    func batches150ms() async throws {
        var rig = await Rig()
        await rig.connect(true)
        try await rig.transport.send(Self.handshake)
        for index in 0 ... 2 {
            try await rig.transport.send(Self.envelopes(index ... index))
        }
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.handshake)
        #expect(try await rig.nextSent() == Self.envelopes(0 ... 2))
        try await rig.transport.send(Self.envelopes(3 ... 3))
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.envelopes(3 ... 3)) // no handshake again until a reconnect
        await rig.run() // a second run returns at once
        await rig.stop()
    }

    @Test("After the channel comes up, the batch leads with the handshake, or with an empty one when none came")
    func handshakeFirstAfterConnect() async throws {
        var rig = await Rig()
        await rig.connect(true)
        try await rig.transport.send(Self.envelopes(0 ... 1))
        try await rig.transport.send(Self.handshake)
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.handshake)
        #expect(try await rig.nextSent() == Self.envelopes(0 ... 1))

        try await rig.transport.send(Self.envelopes(2 ... 2))
        #expect(await rig.clock.nextSleep(skipping: MirroringTransport.watchdog) == MirroringTransport.batchWindow)
        await rig.connect(false) // what was queued is lost with the link
        await rig.connect(true)
        try await rig.transport.send(Self.envelopes(3 ... 3))
        rig.clock.advance(by: MirroringTransport.batchWindow)
        #expect(try await rig.nextSent() == .handshake(workoutID: Self.workout, contiguousSeq: [:]))
        #expect(try await rig.nextSent() == Self.envelopes(3 ... 3))
        await rig.stop()
    }

    @Test("A send unanswered for 3 s degrades the transport for the workouts it knew, until a new workout")
    func watchdogDegradesAfter3s() async throws {
        var rig = await Rig()
        var link = rig.transport.link.makeAsyncIterator()
        #expect(await link.next() == false)
        rig.channel.script(.hang)
        await rig.connect(true)
        #expect(await link.next() == true)
        try await rig.transport.send(Self.handshake)
        try await rig.transport.send(Self.envelopes(0 ... 0))
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.handshake) // hangs
        #expect(await rig.clock.nextSleep(skipping: MirroringTransport.batchWindow) == MirroringTransport.watchdog)
        rig.clock.advance(by: MirroringTransport.watchdog)
        #expect(await rig.status.next() == .degraded)
        #expect(await link.next() == false)
        await #expect(throws: TransportError.unreachable) { try await rig.transport.send(Self.envelopes(1 ... 1)) }
        rig.channel.connect(true)
        #expect(await rig.status.next() == .degraded) // a reconnect does not cure it
        let other = WireFrame.envelopes(Sample.log([], of: Sample.other))
        try await rig.transport.send(other)
        #expect(await rig.status.next() == .open)
        await rig.endWindow()
        // The hung batch's envelopes were never sent; the new workout's go, after a handshake (the reconnect).
        #expect(try await rig.nextSent() == .handshake(workoutID: Sample.other.id, contiguousSeq: [:]))
        #expect(try await rig.nextSent() == other)
        await rig.stop()
    }

    @Test("A send that fails with an underlying error is tried once more; any other failure is not")
    func retriesOnceOnDelegateNotSetUp() async throws {
        var rig = await Rig()
        let notSetUp = HealthError.underlying(code: 3)
        rig.channel.script(.fails(notSetUp), .fails(notSetUp), .fails(HealthError.noActiveSession))
        await rig.connect(true)
        try await rig.transport.send(Self.handshake)
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.handshake)
        #expect(try await rig.nextSent() == Self.handshake) // the one retry
        try await rig.transport.send(Self.envelopes(0 ... 0))
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.envelopes(0 ... 0)) // not a third try of the handshake
        try await rig.transport.send(Self.envelopes(1 ... 1))
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.envelopes(1 ... 1)) // no retry of `noActiveSession`
        await rig.stop()
    }

    @Test("A frame that cannot be encoded is dropped and the batch goes on")
    func unencodableFrame_isDropped() async throws {
        var rig = await Rig()
        await rig.connect(true)
        let infinite = EventBuilders.envelope(
            Sample.logged(0, 0, at: .infinity),
            device: Subject.device,
            seq: 2,
            at: Sample.at(0),
            workoutID: Self.workout
        )
        try await rig.transport.send(Self.handshake)
        try await rig.transport.send(.envelopes([infinite]))
        try await rig.transport.send(.replayRequest(workoutID: Self.workout, contiguousSeq: [:]))
        await rig.endWindow()
        #expect(try await rig.nextSent() == Self.handshake)
        #expect(try await rig.nextSent() == .replayRequest(workoutID: Self.workout, contiguousSeq: [:]))
        await rig.stop()
    }

    @Test("Each batch the peer sent arrives frame by frame; one that cannot be read is dropped")
    func incoming_decodesEachFrame() async throws {
        let rig = await Rig()
        let parts = try WireCodec.encode(Self.handshake) + WireCodec.encode(Self.envelopes(0 ... 1))
        rig.channel.deliver([parts[0], Data([0x00, 0x01]), parts[1]])
        var incoming = rig.transport.incoming.makeAsyncIterator()
        #expect(await incoming.next() == Self.handshake)
        #expect(await incoming.next() == Self.envelopes(0 ... 1))
        await rig.stop()
        #expect(await incoming.next() == nil) // run's end ends the stream
    }
}

extension MirroringTransportTests {
    /// A running transport over a scripted channel.
    struct Rig {
        let channel = ScriptedChannel()
        let clock = ManualClock()
        let transport: MirroringTransport
        let running: Task<Void, Never>
        var status: AsyncStream<Status>.AsyncIterator
        var sends: AsyncStream<Data>.AsyncIterator

        init() async {
            transport = MirroringTransport(channel: channel, clock: clock)
            running = Task { [transport] in await transport.run() }
            status = transport.status.makeAsyncIterator()
            sends = channel.sends.makeAsyncIterator()
            #expect(await status.next() == .down)
        }

        /// Reports the channel's connection and waits for the transport to take it.
        mutating func connect(_ isUp: Bool) async {
            channel.connect(isUp)
            #expect(await status.next() == (isUp ? .open : .down))
        }

        /// Waits for a batch to begin, then ends its window.
        func endWindow() async {
            #expect(await clock.nextSleep(skipping: MirroringTransport.watchdog) == MirroringTransport.batchWindow)
            clock.advance(by: MirroringTransport.batchWindow)
        }

        /// The frame of the next channel send.
        mutating func nextSent() async throws -> WireFrame? {
            try await frame(of: sends.next())
        }

        func stop() async {
            running.cancel()
            await running.value
            channel.release()
        }

        func run() async {
            await transport.run()
        }
    }
}
