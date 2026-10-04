import LedgerTestSupport
import Testing

/// F07 S1 adversarial round 1: `FakeLinkBus` (criterion 5) beyond two endpoints and one link: determinism per seed
/// over every knob at once, no duplicate unless configured, each copy of a duplicate, ordering under delay,
/// partitions in both directions and healing, many endpoints, and the edges of its inputs.
@Suite("Adversarial F07 S1 · FakeLinkBus")
struct FakeLinkBusAdversarialTests {
    typealias Bus = FakeLinkBus<Int>

    /// A message as an endpoint received it, comparable across buses.
    struct Seen: Hashable {
        let recipient: Int
        let from: Int
        let payload: Int
        let arrival: Duration
    }

    /// Every endpoint's inbox, in order.
    static func inboxes(_ bus: Bus) -> [Seen] {
        bus.endpoints.flatMap { endpoint in
            bus.received(by: endpoint).map {
                Seen(recipient: endpoint.index, from: $0.from.index, payload: $0.payload, arrival: $0.arrival)
            }
        }
    }

    /// Five endpoints, every knob on: broadcasts, a partition that comes and goes, time moved in steps.
    static func script(seed: UInt64) -> [Seen] {
        let bus = Bus(
            endpoints: 5,
            link: .init(delay: .milliseconds(1) ... .milliseconds(80), loss: 0.2, duplication: 0.3),
            seed: seed
        )
        let points = bus.endpoints
        for round in 0 ..< 40 {
            if round == 10 {
                bus.partition(points[0], points[3])
            }
            if round == 25 {
                bus.heal(points[0], points[3])
            }
            bus.broadcast(round, from: points[round % 5])
            bus.advance(by: .milliseconds(round % 3 * 20))
        }
        bus.flush()
        return inboxes(bus)
    }

    @Test(
        "The same seed replays the same deliveries, arrival times included, with every knob on",
        arguments: [1, 2026, .max]
    )
    func sameSeed_sameDeliveries(seed: UInt64) {
        #expect(Self.script(seed: seed) == Self.script(seed: seed))
        #expect(Self.script(seed: seed) != Self.script(seed: seed &+ 1))
    }

    @Test("Lossy and delayed but not duplicating: no endpoint ever receives a message twice", arguments: 0 ..< 50)
    func noDuplication_neverTwice(seed: Int) {
        let bus = Bus(endpoints: 4, link: .init(delay: .zero ... .seconds(2), loss: 0.5), seed: UInt64(seed))
        for number in 0 ..< 200 {
            bus.broadcast(number, from: bus.endpoints[number % 4])
            bus.advance(by: .milliseconds(10))
        }
        bus.flush()
        for endpoint in bus.endpoints {
            let payloads = bus.received(by: endpoint).map(\.payload)
            #expect(Set(payloads).count == payloads.count, "seed \(seed), endpoint \(endpoint.index)")
        }
    }

    @Test("Duplication 1 and no loss: every message arrives exactly twice")
    func fullDuplication_exactlyTwice() {
        let bus = Bus(endpoints: 2, link: .init(delay: .zero ... .seconds(1), duplication: 1), seed: 9)
        for number in 0 ..< 100 {
            bus.send(number, from: bus.endpoints[0], to: bus.endpoints[1])
        }
        bus.flush()
        let payloads = bus.received(by: bus.endpoints[1]).map(\.payload)
        #expect(payloads.count == 200)
        #expect(Dictionary(grouping: payloads, by: \.self).values.allSatisfy { $0.count == 2 })
    }

    @Test(
        "Under delay an inbox is in arrival order, and messages due together keep the order sent",
        arguments: 0 ..< 20
    )
    func delayedInbox_isInArrivalOrder(seed: Int) {
        let bus = Bus(endpoints: 3, link: .init(delay: .zero ... .milliseconds(5)), seed: UInt64(seed))
        for number in 0 ..< 300 {
            bus.send(number, from: bus.endpoints[number % 2], to: bus.endpoints[2])
            if number.isMultiple(of: 7) {
                bus.advance(by: .milliseconds(3))
            }
        }
        bus.flush()
        let inbox = bus.received(by: bus.endpoints[2])
        #expect(inbox.count == 300)
        let inOrder = zip(inbox, inbox.dropFirst()).allSatisfy { earlier, later in
            earlier.arrival < later.arrival || (earlier.arrival == later.arrival && earlier.payload < later.payload)
        }
        #expect(inOrder, "seed \(seed)")
    }
}

extension FakeLinkBusAdversarialTests {
    @Test("Without delay each pair is first in, first out")
    func noDelay_isFIFOPerPair() {
        let bus = Bus(endpoints: 3, seed: 1)
        for number in 0 ..< 100 {
            bus.send(number, from: bus.endpoints[number % 2], to: bus.endpoints[2])
        }
        bus.advance(by: .zero)
        #expect(bus.received(by: bus.endpoints[2]).map(\.payload) == Array(0 ..< 100))
    }

    @Test("A partition cuts both directions; one pair's partition leaves the others; healing restores it")
    func partition_isSymmetricAndLocal() {
        let bus = Bus(endpoints: 3, seed: 1)
        let (phone, watch, third) = (bus.endpoints[0], bus.endpoints[1], bus.endpoints[2])
        bus.partition(watch, phone)
        bus.send(1, from: phone, to: watch)
        bus.send(2, from: watch, to: phone)
        bus.send(3, from: phone, to: third)
        bus.send(4, from: third, to: watch)
        bus.flush()
        #expect(bus.received(by: phone).isEmpty)
        #expect(bus.received(by: watch).map(\.payload) == [4])
        #expect(bus.received(by: third).map(\.payload) == [3])
        bus.heal(phone, watch)
        bus.send(5, from: phone, to: watch)
        bus.flush()
        #expect(bus.received(by: watch).map(\.payload) == [4, 5])
    }

    @Test("A message on its way when a partition comes and goes before it is due still arrives")
    func partitionHealedBeforeArrival_delivers() {
        let bus = Bus(endpoints: 2, link: .init(delay: .seconds(1) ... .seconds(1)), seed: 1)
        let (phone, watch) = (bus.endpoints[0], bus.endpoints[1])
        bus.send(1, from: phone, to: watch)
        bus.partition(phone, watch)
        bus.advance(by: .milliseconds(500))
        bus.heal(phone, watch)
        bus.advance(by: .milliseconds(500))
        #expect(bus.received(by: watch).map(\.payload) == [1])
    }

    @Test("Two hundred endpoints, each broadcasting once: every one receives from every other, once")
    func manyEndpoints_broadcastReachesAll() {
        let bus = Bus(endpoints: 200, seed: 3)
        for endpoint in bus.endpoints {
            bus.broadcast(endpoint.index, from: endpoint)
        }
        bus.flush()
        for endpoint in bus.endpoints {
            let senders = bus.received(by: endpoint).map(\.from.index)
            #expect(Set(senders) == Set(0 ..< 200).subtracting([endpoint.index]) && senders.count == 199)
        }
        #expect(bus.inFlightCount == 0)
    }

    @Test("No endpoints, or a negative count, is an empty bus; loss 1 delivers nothing")
    func edges_emptyBusAndTotalLoss() {
        #expect(Bus(endpoints: 0, seed: 1).endpoints.isEmpty)
        #expect(Bus(endpoints: -3, seed: 1).endpoints.isEmpty)
        let bus = Bus(endpoints: 2, link: .init(loss: 1), seed: 1)
        for number in 0 ..< 1000 {
            bus.send(number, from: bus.endpoints[0], to: bus.endpoints[1])
        }
        bus.flush()
        #expect(bus.received(by: bus.endpoints[1]).isEmpty)
    }

    @Test("F7-7: time never runs backwards: arrivals never decrease, even after advance(by:) a negative interval")
    func negativeAdvance_keepsArrivalsMonotonic() {
        let bus = Bus(endpoints: 2, seed: 1)
        let (phone, watch) = (bus.endpoints[0], bus.endpoints[1])
        bus.advance(by: .seconds(10))
        bus.send(1, from: phone, to: watch)
        bus.flush()
        bus.advance(by: .seconds(-20))
        bus.send(2, from: phone, to: watch)
        bus.flush()
        let arrivals = bus.received(by: watch).map(\.arrival)
        #expect(arrivals == arrivals.sorted(), "\(arrivals)")
    }

    @Test("F7-7: an endpoint of another bus is refused, not silently given an inbox no broadcast reaches")
    func foreignEndpoint_isNotAnInbox() {
        let small = Bus(endpoints: 2, seed: 1)
        let foreign = Bus(endpoints: 8, seed: 1).endpoints[7]
        small.send(1, from: small.endpoints[0], to: foreign)
        small.broadcast(2, from: small.endpoints[0])
        small.flush()
        #expect(small.received(by: foreign).isEmpty, "a message reached endpoint 7 of a two-endpoint bus")
    }
}
