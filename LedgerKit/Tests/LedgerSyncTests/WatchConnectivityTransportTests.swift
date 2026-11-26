import Foundation
import LedgerDomain
@testable import LedgerSync
import LedgerTestSupport
import Synchronization
import Testing

/// A session that says whether the peer is reachable, keeps and announces every message it is handed, and,
/// when told to, reports each as failed before it returns.
final class StandInMessageSession: MessageSession {
    private struct State {
        var isReachable = true
        var failsEach = false
        var sent: [Data] = []
        var failures = 0
    }

    /// Each message as it is handed over. One consumer.
    let messages: AsyncStream<Data>
    private let messagesSink: AsyncStream<Data>.Continuation
    private let state = Mutex(State())

    init() {
        (messages, messagesSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    var isReachable: Bool {
        get { state.withLock { $0.isReachable } }
        set { state.withLock { $0.isReachable = newValue } }
    }

    var failsEach: Bool {
        get { state.withLock { $0.failsEach } }
        set { state.withLock { $0.failsEach = newValue } }
    }

    var sent: [Data] {
        state.withLock { $0.sent }
    }

    var failures: Int {
        state.withLock { $0.failures }
    }

    func sendMessageData(_ data: Data, failed: @escaping @Sendable (any Error) -> Void) {
        let fails = state.withLock { state in
            state.sent.append(data)
            if state.failsEach {
                state.failures += 1
            }
            return state.failsEach
        }
        messagesSink.yield(data)
        if fails {
            failed(TransportError.unreachable)
        }
    }
}

/// F17 S7: the WatchConnectivity transport over a stand-in session (testing-strategy §3: no WatchConnectivity in
/// tests). The stand-in queues what it is handed and returns, as `sendMessageData` does, and announces each message.
@Suite("WatchConnectivityTransport", .tags(.sync), .timeLimit(.minutes(1)))
struct WatchConnectivityTransportTests {
    static let workout = Sample.session.id
    static let handshake = WireFrame.handshake(workoutID: workout, contiguousSeq: [Subject.device: 2])

    /// The frames `messages` decode to.
    static func frames(_ messages: [Data]) throws -> [WireFrame] {
        try messages.map(WireCodec.decode)
    }

    @Test("A frame goes as a message only while the peer is reachable; otherwise the send throws unreachable")
    func onlyWhenReachable() async throws {
        let session = StandInMessageSession()
        let transport = WatchConnectivityTransport(session: session)
        session.isReachable = false
        await #expect(throws: TransportError.unreachable) { try await transport.send(Self.handshake) }
        #expect(session.sent.isEmpty)
        session.isReachable = true
        try await transport.send(Self.handshake)
        #expect(try Self.frames(session.sent) == [Self.handshake])
    }

    @Test("A message the session reports as failed is logged and swallowed: the send has already returned")
    func failures_areSwallowed() async throws {
        let session = StandInMessageSession()
        let transport = WatchConnectivityTransport(session: session)
        session.failsEach = true
        try await transport.send(Self.handshake)
        try await transport.send(.envelopes(Sample.log([])))
        #expect(session.failures == 2)
        #expect(session.sent.count == 2)
    }

    @Test("A frame over 60 000 bytes goes as several messages under the limit, which decode back to it in order")
    func largeFrame_isCut() async throws {
        let session = StandInMessageSession()
        let transport = WatchConnectivityTransport(session: session)
        let log = Sample.log(Array(repeating: Sample.logged(0, 0), count: 400))
        try await transport.send(.envelopes(log))
        #expect(session.sent.count > 1)
        #expect(session.sent.allSatisfy { $0.count <= WireCodec.frameLimit })
        let received = try Self.frames(session.sent).flatMap { frame -> [EventEnvelope] in
            guard case let .envelopes(envelopes) = frame else {
                return []
            }
            return envelopes
        }
        #expect(received.map(\.key) == log.map(\.key))
    }

    @Test("A frame that cannot be encoded is refused and nothing is sent: tooLarge, or the codec's unencodable")
    func unencodable_isRefused() async {
        let session = StandInMessageSession()
        let transport = WatchConnectivityTransport(session: session)
        let devices = (0 ..< 2000).map { DeviceID(EventBuilders.uuid(0x10000 + $0)) }
        let crowd = Dictionary(uniqueKeysWithValues: devices.map { ($0, UInt64.max) })
        await #expect(throws: TransportError.tooLarge) {
            try await transport.send(.handshake(workoutID: Self.workout, contiguousSeq: crowd))
        }
        let never = EventBuilders.envelope(.restSkipped, seq: 2, at: Date(timeIntervalSinceReferenceDate: .infinity))
        await #expect(throws: WireCodecError.unencodable) { try await transport.send(.envelopes([never])) }
        #expect(session.sent.isEmpty)
    }

    @Test("The link starts down, then reports each change of reachability once")
    func link_reportsEachChange() async {
        let transport = WatchConnectivityTransport(session: StandInMessageSession())
        var link = transport.link.makeAsyncIterator()
        #expect(await link.next() == false)
        transport.reachabilityChanged(false) // no change
        transport.reachabilityChanged(true)
        transport.reachabilityChanged(true) // no change
        transport.reachabilityChanged(false)
        transport.reachabilityChanged(true)
        #expect(await link.next() == true)
        #expect(await link.next() == false)
        #expect(await link.next() == true)
    }

    @Test("Each message from the peer is decoded onto incoming; one that cannot be read is dropped")
    func incoming_decodesEachMessage() async throws {
        let transport = WatchConnectivityTransport(session: StandInMessageSession())
        var incoming = transport.incoming.makeAsyncIterator()
        transport.received(Data([0x00, 0x01, 0x02]))
        try transport.received(#require(WireCodec.encode(Self.handshake).first))
        #expect(await incoming.next() == Self.handshake)
    }

    @Test("A host's sender is never held by the transport: every own envelope is handed over as it is stored")
    func host_isNeverHeld() async throws {
        let session = StandInMessageSession()
        let transport = WatchConnectivityTransport(session: session)
        let subject = Subject()
        // The clock never moves: had a send waited on the session, the host's 3 s timeout could not end it.
        await subject.host.connect(transport, clock: ManualClock())
        var messages = session.messages.makeAsyncIterator()
        try await subject.host.start(Sample.session)
        _ = try await subject.host.apply(Sample.logged(0, 0))
        _ = try await subject.host.apply(Sample.logged(0, 1))
        var keys: [EnvelopeKey] = []
        for _ in 1 ... 3 {
            let message = try #require(await messages.next())
            if case let .envelopes(envelopes) = try WireCodec.decode(message) {
                keys += envelopes.map(\.key)
            }
        }
        #expect(keys == (1 ... 3).map { EnvelopeKey(device: Subject.device, seq: $0) })
    }
}
