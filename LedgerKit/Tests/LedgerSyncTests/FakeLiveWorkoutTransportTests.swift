import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F17 S2: `FakeLiveNetwork` and `FakeLiveWorkoutTransport`, the faults criteria 4–7 are tested under once the host
/// sends and receives (S3, S4): loss, duplication and reordering (4), a partition and its heal (5), a send that
/// hangs (6), and a long solo stretch (7).
@Suite("FakeLiveWorkoutTransport", .tags(.sync), .timeLimit(.minutes(1)))
struct FakeLiveWorkoutTransportTests {
    @Test("Frames go both ways once the network's time reaches them, in order, and both links start up")
    func frames_goBothWays_inOrder() async throws {
        let network = FakeLiveNetwork(seed: 1)
        #expect(await Self.next(1, of: network.phone.link) == [true])
        #expect(await Self.next(1, of: network.watch.link) == [true])
        try await network.phone.send(Self.frame(1))
        try await network.phone.send(Self.frame(2))
        try await network.watch.send(Self.frame(3))
        #expect(network.watch.received.isEmpty && network.phone.received.isEmpty)
        network.flush()
        #expect(await Self.next(2, of: network.watch.incoming) == [Self.frame(1), Self.frame(2)])
        #expect(await Self.next(1, of: network.phone.incoming) == [Self.frame(3)])
        #expect(network.phone.sent == [Self.frame(1), Self.frame(2)] && network.watch.sent == [Self.frame(3)])
        #expect(await Self.next(2, of: network.phone.handed) == [Self.frame(1), Self.frame(2)])
        network.flush() // nothing is handed over twice
        #expect(network.watch.received.count == 2 && network.phone.received.count == 1)
    }

    @Test("Criterion 4's faults: loss 0.3, duplication 0.2 and reordering, the same for a seed, over 100 seeds")
    func lossDuplicationReorder_perSeed() async throws {
        let link = FakeLiveNetwork.Link(delay: .milliseconds(1) ... .milliseconds(400), loss: 0.3, duplication: 0.2)
        var (lost, duplicated, reordered) = (false, false, false)
        for seed in 0 ..< UInt64(100) {
            let received = try await Self.sendAll(50, over: FakeLiveNetwork(link: link, seed: seed))
            let again = try await Self.sendAll(50, over: FakeLiveNetwork(link: link, seed: seed))
            #expect(received == again, "seed \(seed)")
            #expect(Set(received).isSubset(of: Set(1 ... 50)), "seed \(seed)")
            lost = lost || Set(received).count < 50
            duplicated = duplicated || Set(received).count < received.count
            reordered = reordered || received != received.sorted()
        }
        #expect(lost && duplicated && reordered)
    }

    @Test("Criterion 4's stream: what the watch received reaches its incoming in the same order")
    func received_isWhatIncomingYields() async throws {
        let link = FakeLiveNetwork.Link(delay: .milliseconds(1) ... .milliseconds(400), loss: 0.3, duplication: 0.2)
        let network = FakeLiveNetwork(link: link, seed: 42)
        let received = try await Self.sendAll(30, over: network)
        let yielded = await Self.next(received.count, of: network.watch.incoming)
        #expect(yielded.compactMap(Self.number) == received)
    }

    @Test("A delayed frame arrives only once advance reaches it")
    func advance_deliversWhatIsDue() async throws {
        let network = FakeLiveNetwork(link: .init(delay: .seconds(1) ... .seconds(1)), seed: 2)
        try await network.phone.send(Self.frame(1))
        network.advance(by: .milliseconds(999))
        #expect(network.watch.received.isEmpty)
        network.advance(by: .milliseconds(1))
        #expect(network.watch.received == [Self.frame(1)])
        network.setLink(.init(loss: 1))
        try await network.phone.send(Self.frame(2))
        network.flush()
        #expect(network.watch.received == [Self.frame(1)] && network.phone.sent.count == 2)
    }

    @Test("Criterion 5's partition: both links go down, sends throw unreachable, frames on their way are lost")
    func partition_thenHeal() async throws {
        let network = FakeLiveNetwork(link: .init(delay: .seconds(1) ... .seconds(1)), seed: 3)
        try await network.phone.send(Self.frame(1))
        network.partition()
        network.partition() // a second cut changes nothing
        #expect(network.isPartitioned)
        await #expect(throws: TransportError.unreachable) { try await network.watch.send(Self.frame(2)) }
        network.flush()
        #expect(network.watch.received.isEmpty && network.phone.received.isEmpty && network.watch.sent.isEmpty)
        network.heal()
        #expect(!network.isPartitioned)
        #expect(await Self.next(3, of: network.phone.link) == [true, false, true])
        #expect(await Self.next(3, of: network.watch.link) == [true, false, true])
        try await network.watch.send(Self.frame(3))
        network.flush()
        #expect(network.phone.received == [Self.frame(3)])
    }

    @Test("Criterion 7's solo stretch: ten minutes apart, nothing crosses; after the heal one flush delivers")
    func soloForTenMinutes_thenReconnect() async throws {
        let network = FakeLiveNetwork(seed: 4)
        network.partition()
        for number in 1 ... UInt64(12) {
            await #expect(throws: TransportError.unreachable) { try await network.watch.send(Self.frame(number)) }
            network.advance(by: .seconds(50))
        }
        network.heal()
        for number in 1 ... UInt64(12) {
            try await network.watch.send(Self.frame(number))
        }
        network.flush()
        #expect(network.phone.received.compactMap(Self.number) == Array(1 ... 12))
    }

    @Test("Criterion 6's hang: a send waits, announced, until it is cancelled, and then sends nothing")
    func hang_waitsUntilCancelled() async throws {
        let network = FakeLiveNetwork(seed: 5)
        network.phone.hang = true
        #expect(network.phone.hang)
        let send = Task { try await network.phone.send(Self.frame(1)) }
        #expect(await Self.next(1, of: network.phone.hung) == [Self.frame(1)])
        #expect(network.phone.waitingSends == 1)
        send.cancel()
        await #expect(throws: CancellationError.self) { try await send.value }
        network.flush()
        #expect(network.phone.sent.isEmpty && network.watch.received.isEmpty)
        #expect(network.phone.waitingSends == 0)
        try await network.watch.send(Self.frame(2)) // the other side is not hung
        network.flush()
        #expect(network.phone.received == [Self.frame(2)])
    }

    @Test("Criterion 6's late return: turning hang off lets every waiting send go on, or fail as the link says")
    func hang_releasedSendsGoOn() async throws {
        let network = FakeLiveNetwork(seed: 6)
        network.phone.hang = true
        let first = Task { try await network.phone.send(Self.frame(1)) }
        let second = Task { try await network.phone.send(Self.frame(2)) }
        _ = await Self.next(2, of: network.phone.hung)
        network.phone.hang = false
        try await first.value
        try await second.value
        network.flush()
        #expect(Set(network.watch.received.compactMap(Self.number)) == [1, 2])
        network.phone.hang = true
        let third = Task { try await network.phone.send(Self.frame(3)) }
        var hung = network.phone.hung.makeAsyncIterator()
        _ = await hung.next()
        network.partition()
        network.phone.hang = false
        await #expect(throws: TransportError.unreachable) { try await third.value }
        #expect(network.phone.waitingSends == 0)
    }

    @Test("A transport made alone reaches no one: its link is down and every send throws unreachable")
    func alone_reachesNoOne() async {
        let transport = FakeLiveWorkoutTransport()
        #expect(await Self.next(1, of: transport.link) == [false])
        await #expect(throws: TransportError.unreachable) { try await transport.send(Self.frame(1)) }
        #expect(transport.sent.isEmpty && transport.received.isEmpty && !transport.hang)
    }
}

extension FakeLiveWorkoutTransportTests {
    /// A small frame that carries `number`.
    static func frame(_ number: UInt64) -> WireFrame {
        .handshake(workoutID: EventBuilders.workoutID, contiguousSeq: [EventBuilders.phone: number])
    }

    /// The number `frame(_:)` put in `frame`.
    static func number(_ frame: WireFrame) -> UInt64? {
        guard case let .handshake(_, vector) = frame else {
            return nil
        }
        return vector[EventBuilders.phone]
    }

    /// The next `count` elements of `stream`.
    static func next<Element>(_ count: Int, of stream: AsyncStream<Element>) async -> [Element] {
        var iterator = stream.makeAsyncIterator()
        var elements: [Element] = []
        for _ in 0 ..< count {
            guard let element = await iterator.next() else {
                break
            }
            elements.append(element)
        }
        return elements
    }

    /// Sends frames 1 … `count` from the phone, then delivers everything; the numbers the watch received.
    static func sendAll(_ count: UInt64, over network: FakeLiveNetwork) async throws -> [UInt64] {
        for number in 1 ... count {
            try await network.phone.send(frame(number))
        }
        network.flush()
        return network.watch.received.compactMap(number)
    }
}
